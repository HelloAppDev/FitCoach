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
                TextField("Модель", text: $settings.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                Text("Ollama (на Mac):\n1. Установи Ollama\n2. В терминале: ollama pull \(settings.model)\n3. Адрес сервера: http://127.0.0.1:11434/v1\n\nИнструменты агента (история упражнений, расчёт веса) работают только с моделями, которые умеют вызывать функции: qwen3, llama3.1/3.2, mistral. С gemma3 коуч отвечает без инструментов, по данным из промпта.\n\nДля реального iPhone укажи IP Mac в сети (например http://192.168.1.5:11434/v1) и запусти Ollama с OLLAMA_HOST=0.0.0.0.")
            }
        }
        .navigationTitle("ИИ-коуч")
    }

    private func check() async {
        isChecking = true
        status = nil
        do {
            let models = try await LocalLLMCoach.availableModels(config: settings.config)
            if models.isEmpty {
                status = "Сервер ответил, но список моделей пуст."
            } else {
                status = "Связь есть. Доступные модели: \(models.prefix(8).joined(separator: ", "))"
            }
        } catch {
            status = "Ошибка: \(error.localizedDescription)"
        }
        isChecking = false
    }
}
