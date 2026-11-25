import Foundation
import Observation

enum CoachLLMError: LocalizedError {
    case badURL
    case http(status: Int, body: String)
    case noContent
    case invalidAgentPlan
    case noPendingCalendarEvent

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Некорректный адрес сервера. Проверь настройки коуча."
        case .http(let status, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Сервер вернул \(status). \(detail.isEmpty ? "" : String(detail.prefix(300)))"
        case .noContent:
            return "Модель не вернула текст. Проверь, запущен ли сервер и загружены ли модели."
        case .invalidAgentPlan:
            return "Qwen не смог составить план действий. Попробуй переформулировать вопрос."
        case .noPendingCalendarEvent:
            return "Нет тренировки, ожидающей добавления в календарь."
        }
    }
}

/// Двухмодельный ИИ-агент:
/// Qwen планирует разрешённые действия, Gemma отвечает пользователю и анализирует изображения.
@MainActor
@Observable
final class LocalLLMCoach {
    private let settings: CoachSettings
    private let calendarService: CalendarService
    var context: CoachContext
    private(set) var pendingCalendarEvent: CalendarEventDraft?
    private var history: [LLMMessage] = []

    private static let maxUserTurns = 6

    init(
        settings: CoachSettings,
        context: CoachContext,
        calendarService: CalendarService? = nil
    ) {
        self.settings = settings
        self.context = context
        self.calendarService = calendarService ?? CalendarService()
    }

    func reset() {
        history.removeAll()
        pendingCalendarEvent = nil
    }

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

    func streamRespond(to prompt: String, imageData: Data? = nil) -> AsyncThrowingStream<String, Error> {
        trimHistory()
        let checkpoint = history.count
        history.append(LLMMessage(role: "user", content: prompt, imageData: imageData))

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    let actions = try await self.planActions()
                    var toolResults: [String] = []

                    for action in actions {
                        switch CoachTools.prepare(
                            name: action.name,
                            arguments: action.arguments,
                            context: self.context
                        ) {
                        case .text(let result):
                            toolResults.append("Инструмент \(action.name):\n\(result)")
                        case .requiresCalendarConfirmation(let draft):
                            if self.pendingCalendarEvent == nil {
                                self.pendingCalendarEvent = draft
                                toolResults.append(
                                    "Инструмент create_calendar_event подготовил событие, но ещё не записал его. Ожидается подтверждение пользователя: \(draft.confirmationText)"
                                )
                            }
                        }
                    }

                    if !toolResults.isEmpty {
                        continuation.yield("Проверяю данные и подготавливаю действия…")
                    }

                    let content = try await Self.stream(
                        config: self.settings.chatConfig,
                        messages: self.requestMessages(toolResults: toolResults),
                        onText: { continuation.yield($0) }
                    )
                    guard !content.isEmpty else { throw CoachLLMError.noContent }

                    // Изображение нужно только для текущего ответа; в дальнейшей истории оставляем маркер.
                    if imageData != nil {
                        self.history[checkpoint] = LLMMessage(
                            role: "user",
                            content: "\(prompt) [было приложено изображение]"
                        )
                    }
                    self.history.append(LLMMessage(role: "assistant", content: content))
                    continuation.finish()
                } catch {
                    self.pendingCalendarEvent = nil
                    self.history.removeSubrange(checkpoint...)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func confirmPendingCalendarEvent() async throws -> String {
        guard let draft = pendingCalendarEvent else { throw CoachLLMError.noPendingCalendarEvent }
        let result = try await calendarService.createEvent(from: draft)
        pendingCalendarEvent = nil
        history.append(LLMMessage(role: "assistant", content: result))
        return result
    }

    func cancelPendingCalendarEvent() -> String {
        guard let draft = pendingCalendarEvent else {
            return "Нет тренировки, ожидающей добавления в календарь."
        }
        pendingCalendarEvent = nil
        let result = "Добавление «\(draft.title)» в календарь отменено."
        history.append(LLMMessage(role: "assistant", content: result))
        return result
    }

    /// Qwen получает только текст разговора и выбирает действия агента.
    private func planActions() async throws -> [AgentAction] {
        let plannerPrompt = """
        Ты планировщик действий ИИ-агента фитнес-приложения.
        Проанализируй последний запрос с учётом истории и выбери только необходимые инструменты.
        Не отвечай пользователю и не утверждай, что действие уже выполнено.

        \(CoachTools.planningGuide())
        """
        let messages = [["role": "system", "content": plannerPrompt]] + history.map(\.plannerJSON)
        let plan = try await Self.complete(
            config: settings.agentConfig,
            messages: messages,
            jsonMode: true
        )
        return try Self.parseActions(from: plan)
    }

    /// Gemma получает контекст, результаты инструментов и текущее изображение.
    private func requestMessages(toolResults: [String]) -> [[String: Any]] {
        var messages = [["role": "system", "content": context.systemPrompt]] + history.map(\.json)
        if !toolResults.isEmpty {
            messages.append([
                "role": "system",
                "content": """
                Результаты инструментов приложения. Считай эти данные точными.
                Если календарное событие только подготовлено, прямо скажи: «Событие ещё не добавлено в календарь — подтвердите действие кнопкой ниже».
                До подтверждения запрещено писать, что тренировка уже назначена, запланирована, добавлена или сохранена.

                \(toolResults.joined(separator: "\n\n"))
                """
            ])
        }
        return messages
    }

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
        let request = try makeRequest(
            config: config,
            messages: messages,
            stream: true,
            temperature: 0.6,
            jsonMode: false
        )
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

    private static func complete(
        config: LLMConfig,
        messages: [[String: Any]],
        jsonMode: Bool
    ) async throws -> String {
        let request = try makeRequest(
            config: config,
            messages: messages,
            stream: false,
            temperature: 0,
            jsonMode: jsonMode
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

        var calendarActionSeen = false
        return rawActions.prefix(3).compactMap { item in
            guard let name = item["name"] as? String, CoachTools.isAllowed(name) else { return nil }
            if name == "create_calendar_event" {
                guard !calendarActionSeen else { return nil }
                calendarActionSeen = true
            }
            return AgentAction(name: name, arguments: item["arguments"] as? [String: Any] ?? [:])
        }
    }

    private static func makeRequest(
        config: LLMConfig,
        messages: [[String: Any]],
        stream: Bool,
        temperature: Double,
        jsonMode: Bool
    ) throws -> URLRequest {
        guard let base = URL(string: config.baseURLString) else { throw CoachLLMError.badURL }

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": stream,
            "temperature": temperature
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

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
    let imageData: Data?

    init(role: String, content: String, imageData: Data? = nil) {
        self.role = role
        self.content = content
        self.imageData = imageData
    }

    var json: [String: Any] {
        guard let imageData else { return ["role": role, "content": content] }
        return [
            "role": role,
            "content": [
                ["type": "text", "text": content],
                ["type": "image_url", "image_url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]
            ]
        ]
    }

    var plannerJSON: [String: Any] {
        let marker = imageData == nil ? "" : " [пользователь приложил изображение для Gemma]"
        return ["role": role, "content": content + marker]
    }
}

private struct ChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
}

private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
