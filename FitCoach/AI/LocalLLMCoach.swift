import Foundation
import Observation

enum CoachLLMError: LocalizedError {
    case badURL
    case http(status: Int, body: String)
    case noContent
    case invalidAgentPlan

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Некорректный адрес сервера. Проверь настройки коуча."
        case .http(let status, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Сервер вернул \(status). \(detail.isEmpty ? "" : String(detail.prefix(300)))"
        case .noContent:
            return "Модель не вернула текст. Проверь, запущен ли сервер и загружена ли модель."
        case .invalidAgentPlan:
            return "Модель не смогла составить план действий. Попробуй переформулировать вопрос."
        }
    }
}

/// ИИ-агент на базе локальной Gemma 3.
/// Цикл: модель выбирает инструменты → приложение выполняет их → модель формирует ответ.
@MainActor
@Observable
final class LocalLLMCoach {
    private let settings: CoachSettings
    /// Обновляется перед каждым сообщением, чтобы модель видела свежие данные.
    var context: CoachContext
    private var history: [LLMMessage] = []

    /// Сколько последних вопросов пользователя держать в истории: у локальной модели короткое окно контекста.
    private static let maxUserTurns = 6

    init(settings: CoachSettings, context: CoachContext) {
        self.settings = settings
        self.context = context
    }

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
        guard let http = response as? HTTPURLResponse else {
            throw CoachLLMError.http(status: -1, body: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CoachLLMError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        struct ModelsResponse: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }

        return try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id)
    }

    func streamRespond(to prompt: String) -> AsyncThrowingStream<String, Error> {
        trimHistory()
        let checkpoint = history.count
        history.append(LLMMessage(role: "user", content: prompt))

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    let actions = try await self.planActions()
                    let toolResults = actions.map { action in
                        let result = CoachTools.run(
                            name: action.name,
                            arguments: action.arguments,
                            context: self.context
                        )
                        return "Инструмент \(action.name):\n\(result)"
                    }
                    if !toolResults.isEmpty {
                        continuation.yield("Проверяю данные и выполняю расчёт…")
                    }

                    let content = try await Self.stream(
                        config: self.settings.config,
                        messages: self.requestMessages(toolResults: toolResults),
                        onText: { continuation.yield($0) }
                    )
                    guard !content.isEmpty else { throw CoachLLMError.noContent }
                    self.history.append(LLMMessage(role: "assistant", content: content))
                    continuation.finish()
                } catch {
                    // Не сохраняем неудавшийся вопрос в истории диалога.
                    self.history.removeSubrange(checkpoint...)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Первый запрос к модели: выбрать необходимые действия, не формируя ответ пользователю.
    private func planActions() async throws -> [AgentAction] {
        let plannerPrompt = """
        Ты планировщик действий ИИ-агента фитнес-приложения.
        Проанализируй последний запрос с учётом истории и выбери только необходимые инструменты.

        \(CoachTools.planningGuide)
        """
        let messages = [["role": "system", "content": plannerPrompt]] + history.map(\.json)
        let plan = try await Self.complete(config: settings.config, messages: messages)
        return try Self.parseActions(from: plan)
    }

    private func requestMessages(toolResults: [String]) -> [[String: Any]] {
        var messages = [["role": "system", "content": context.systemPrompt]] + history.map(\.json)
        if !toolResults.isEmpty {
            messages.append([
                "role": "system",
                "content": "Результаты инструментов приложения. Считай эти данные точными и используй их в ответе:\n\n\(toolResults.joined(separator: "\n\n"))"
            ])
        }
        return messages
    }

    /// Оставляем последние `maxUserTurns` вопросов вместе с ответами.
    private func trimHistory() {
        let userIndices = history.indices.filter { history[$0].role == "user" }
        guard userIndices.count >= Self.maxUserTurns else { return }
        history.removeSubrange(..<userIndices[userIndices.count - Self.maxUserTurns + 1])
    }

    private static func stream(
        config: LLMConfig,
        messages: [[String: Any]],
        onText: (String) -> Void
    ) async throws -> String {
        let request = try makeRequest(config: config, messages: messages)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CoachLLMError.http(status: -1, body: "")
        }

        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw CoachLLMError.http(status: http.statusCode, body: body)
        }

        var content = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let text = try? JSONDecoder().decode(ChatChunk.self, from: data).choices.first?.delta.content,
                  !text.isEmpty else { continue }

            content += text
            onText(content)
        }

        return content
    }

    /// Непотоковый запрос используется для скрытого этапа планирования действий.
    private static func complete(config: LLMConfig, messages: [[String: Any]]) async throws -> String {
        let request = try makeRequest(
            config: config,
            messages: messages,
            stream: false,
            temperature: 0
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachLLMError.http(status: -1, body: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CoachLLMError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        let decoded = try JSONDecoder().decode(ChatCompletion.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw CoachLLMError.noContent
        }
        return content
    }

    private static func parseActions(from content: String) throws -> [AgentAction] {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              start <= end,
              let data = String(content[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawActions = object["actions"] as? [[String: Any]] else {
            throw CoachLLMError.invalidAgentPlan
        }

        return rawActions.prefix(3).compactMap { item in
            guard let name = item["name"] as? String, CoachTools.isAllowed(name) else { return nil }
            return AgentAction(name: name, arguments: item["arguments"] as? [String: Any] ?? [:])
        }
    }

    private static func makeRequest(config: LLMConfig, messages: [[String: Any]]) throws -> URLRequest {
        try makeRequest(config: config, messages: messages, stream: true, temperature: 0.6)
    }

    private static func makeRequest(
        config: LLMConfig,
        messages: [[String: Any]],
        stream: Bool,
        temperature: Double
    ) throws -> URLRequest {
        guard let base = URL(string: config.baseURLString) else { throw CoachLLMError.badURL }

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": stream,
            "temperature": temperature
        ]

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

private struct AgentAction {
    let name: String
    let arguments: [String: Any]
}

private struct LLMMessage {
    let role: String
    let content: String

    var json: [String: Any] {
        ["role": role, "content": content]
    }
}

private struct ChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }

    let choices: [Choice]
}

private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }

    let choices: [Choice]
}
