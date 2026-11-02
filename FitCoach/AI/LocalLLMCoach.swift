import Foundation
import Observation

enum CoachLLMError: LocalizedError {
    case badURL
    case http(status: Int, body: String)
    case noContent
    case toolsUnsupported
    case tooManyToolCalls

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Некорректный адрес сервера. Проверь настройки коуча."
        case .http(let status, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Сервер вернул \(status). \(detail.isEmpty ? "" : String(detail.prefix(300)))"
        case .noContent:
            return "Модель не вернула текст. Проверь, запущен ли сервер и загружена ли модель."
        case .toolsUnsupported:
            return "Модель не поддерживает вызов инструментов."
        case .tooManyToolCalls:
            return "Модель зациклилась на вызовах инструментов. Попробуй переформулировать вопрос."
        }
    }
}

/// ИИ-агент поверх любого OpenAI-совместимого сервера (Ollama, LM Studio и т.п.).
/// Цикл агента: запрос → модель просит инструмент → приложение его выполняет →
/// результат уходит модели → … → финальный текстовый ответ.
@MainActor
@Observable
final class LocalLLMCoach {
    private let settings: CoachSettings
    /// Обновляется перед каждым сообщением, чтобы модель видела свежие данные.
    var context: CoachContext
    private var history: [LLMMessage] = []
    /// Модели, которые ответили «does not support tools» — с ними работаем без инструментов.
    private var modelsWithoutTools: Set<String> = []

    /// Сколько последних вопросов пользователя держать в истории: у маленьких моделей короткое окно контекста.
    private static let maxUserTurns = 6
    /// Сколько раз подряд модель может вызвать инструменты, прежде чем мы остановим цикл.
    private static let maxToolRounds = 4

    init(settings: CoachSettings, context: CoachContext) {
        self.settings = settings
        self.context = context
    }

    /// Включены ли инструменты для текущей модели (выключаются, если сервер ответил, что модель их не умеет).
    var toolsEnabled: Bool { !modelsWithoutTools.contains(settings.model) }

    func reset() {
        history.removeAll()
    }

    /// Запрос к серверу списка моделей — используется для проверки связи.
    static func availableModels(config: LLMConfig) async throws -> [String] {
        guard let base = URL(string: config.baseURLString) else { throw CoachLLMError.badURL }
        var request = URLRequest(url: base.appendingPathComponent("models"))
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CoachLLMError.http(status: -1, body: "") }
        guard (200..<300).contains(http.statusCode) else {
            throw CoachLLMError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        struct ModelsResponse: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map(\.id)
    }

    func streamRespond(to prompt: String) -> AsyncThrowingStream<String, Error> {
        trimHistory()
        let checkpoint = history.count
        history.append(LLMMessage(role: "user", content: prompt))

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    for _ in 0..<Self.maxToolRounds {
                        let reply = try await self.completion { continuation.yield($0) }

                        if reply.toolCalls.isEmpty {
                            guard !reply.content.isEmpty else { throw CoachLLMError.noContent }
                            self.history.append(LLMMessage(role: "assistant", content: reply.content))
                            continuation.finish()
                            return
                        }

                        // Модель попросила инструменты: выполняем их и отдаём результаты обратно.
                        continuation.yield("Смотрю твои данные…")
                        self.history.append(LLMMessage(role: "assistant", content: reply.content, toolCalls: reply.toolCalls))
                        for call in reply.toolCalls {
                            let output = CoachTools.run(name: call.name, argumentsJSON: call.arguments, context: self.context)
                            self.history.append(LLMMessage(role: "tool", content: output, toolCallID: call.id))
                        }
                    }
                    throw CoachLLMError.tooManyToolCalls
                } catch {
                    // Откатываем весь неудавшийся обмен, включая промежуточные вызовы инструментов.
                    self.history.removeSubrange(checkpoint...)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Один запрос к модели. Если модель не умеет инструменты — повторяем без них.
    private func completion(onText: (String) -> Void) async throws -> LLMReply {
        let config = settings.config
        if toolsEnabled {
            do {
                return try await Self.stream(config: config, messages: requestMessages(tools: true), tools: true, onText: onText)
            } catch CoachLLMError.toolsUnsupported {
                modelsWithoutTools.insert(config.model)
            }
        }
        return try await Self.stream(config: config, messages: requestMessages(tools: false), tools: false, onText: onText)
    }

    private func requestMessages(tools: Bool) -> [[String: Any]] {
        [["role": "system", "content": context.systemPrompt(toolsEnabled: tools)]] + history.map(\.json)
    }

    /// Оставляем последние `maxUserTurns` вопросов вместе с ответами и вызовами инструментов.
    private func trimHistory() {
        let userIndices = history.indices.filter { history[$0].role == "user" }
        guard userIndices.count >= Self.maxUserTurns else { return }
        history.removeSubrange(..<userIndices[userIndices.count - Self.maxUserTurns + 1])
    }

    private static func stream(
        config: LLMConfig,
        messages: [[String: Any]],
        tools: Bool,
        onText: (String) -> Void
    ) async throws -> LLMReply {
        let request = try makeRequest(config: config, messages: messages, tools: tools)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CoachLLMError.http(status: -1, body: "")
        }

        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line }
            if tools && body.contains("does not support tools") { throw CoachLLMError.toolsUnsupported }
            throw CoachLLMError.http(status: http.statusCode, body: body)
        }

        var content = ""
        // Вызовы инструментов могут приходить кусками — собираем их по index.
        var calls: [Int: LLMToolCall] = [:]
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let delta = try? JSONDecoder().decode(ChatChunk.self, from: data).choices.first?.delta else { continue }

            if let text = delta.content, !text.isEmpty {
                content += text
                onText(content)
            }
            for (position, part) in (delta.toolCalls ?? []).enumerated() {
                let index = part.index ?? position
                var call = calls[index] ?? LLMToolCall(id: part.id ?? "call_\(index)", name: "", arguments: "")
                call.name += part.function?.name ?? ""
                call.arguments += part.function?.arguments ?? ""
                calls[index] = call
            }
        }

        let toolCalls = calls.keys.sorted().compactMap { calls[$0] }.filter { !$0.name.isEmpty }
        return LLMReply(content: content, toolCalls: toolCalls)
    }

    private static func makeRequest(config: LLMConfig, messages: [[String: Any]], tools: Bool) throws -> URLRequest {
        guard let base = URL(string: config.baseURLString) else { throw CoachLLMError.badURL }

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": true,
            "temperature": 0.6
        ]
        if tools { body["tools"] = CoachTools.definitions }

        var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        return request
    }
}

// MARK: - Формат сообщений OpenAI Chat Completions

private struct LLMToolCall {
    let id: String
    var name: String
    var arguments: String
}

private struct LLMReply {
    let content: String
    let toolCalls: [LLMToolCall]
}

private struct LLMMessage {
    let role: String
    let content: String
    var toolCalls: [LLMToolCall] = []
    var toolCallID: String?

    var json: [String: Any] {
        var json: [String: Any] = ["role": role, "content": content]
        if !toolCalls.isEmpty {
            json["tool_calls"] = toolCalls.map {
                ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]]
            }
        }
        if let toolCallID { json["tool_call_id"] = toolCallID }
        return json
    }
}

private struct ChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        let delta: Delta
    }

    struct ToolCallDelta: Decodable {
        struct Function: Decodable {
            let name: String?
            let arguments: String?
        }
        let index: Int?
        let id: String?
        let function: Function?
    }

    let choices: [Choice]
}
