import SwiftUI

struct CoachSettingsView: View {
    @State private var settings = CoachSettings.shared
    @State private var status: String?
    @State private var isChecking = false

    var body: some View {
        Form {
            Section("Сервер ИИ") {
                TextField("Адрес (OpenAI-совместимый)", text: $settings.baseURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                LabeledContent("Диалог и изображения", value: CoachSettings.chatModel)
                LabeledContent("Агент и инструменты", value: CoachSettings.agentModel)
                SecureField("API-ключ (для Ollama не нужен)", text: $settings.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await check() }
                } label: {
                    HStack {
                        if isChecking { ProgressView() }
                        Text(isChecking ? "Проверяю..." : "Проверить связь")
                    }
                }
                .disabled(isChecking)
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Проверка")
            } footer: {
                Text("Ollama (на Mac):\n1. Установи Ollama\n2. Выполни: ollama pull \(CoachSettings.chatModel)\n3. Выполни: ollama pull \(CoachSettings.agentModel)\n4. Адрес сервера: http://127.0.0.1:11434/v1\n\nQwen планирует действия и выбирает инструменты. Gemma формирует ответы и анализирует изображения. Запись в системный календарь всегда требует подтверждения.\n\nДля реального iPhone укажи IP Mac в сети (например http://192.168.1.5:11434/v1) и запусти Ollama с OLLAMA_HOST=0.0.0.0.")
            }
        }
        .navigationTitle("ИИ-коуч")
    }

    private func check() async {
        isChecking = true
        status = nil
        do {
            let models = try await LocalLLMCoach.availableModels(config: settings.chatConfig)
            let required = [CoachSettings.chatModel, CoachSettings.agentModel]
            let missing = required.filter { !models.contains($0) }
            if missing.isEmpty {
                status = "Связь есть. Gemma и Qwen готовы к работе."
            } else {
                status = "Связь есть, но не загружены: \(missing.joined(separator: ", ")). Выполни ollama pull для каждой модели."
            }
        } catch {
            status = "Ошибка: \(error.localizedDescription)"
        }
        isChecking = false
    }
}
