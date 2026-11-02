import SwiftUI
import SwiftData

struct ChatView: View {
    let profile: UserProfile

    @Query(sort: \WorkoutSet.date, order: .reverse) private var workouts: [WorkoutSet]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]

    @State private var coach: LocalLLMCoach?
    @State private var input = ""
    @State private var messages: [ChatMessage] = []
    @State private var isStreaming = false
    @State private var connectionError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let connectionError {
                    banner(connectionError)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                bubble(message).id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.last?.text) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if isStreaming {
                    ProgressView().padding(.bottom, 4)
                }

                inputBar
            }
            .navigationTitle("Тренер")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { resetChat() } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(isStreaming || coach == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { CoachSettingsView() } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .task { await startIfNeeded() }
        }
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Нет связи с моделью").font(.subheadline.bold())
                Text(text).font(.caption).foregroundStyle(.secondary)
                NavigationLink("Настроить сервер") { CoachSettingsView() }
                    .font(.caption.bold())
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer() }
            Text(message.text.isEmpty ? "…" : message.text)
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if message.role == .coach { Spacer() }
        }
    }

    private var inputBar: some View {
        HStack {
            TextField("Сообщение...", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button { send() } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(isStreaming || coach == nil || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private func makeContext() -> CoachContext {
        CoachContext(profile: profile, recentWorkouts: workouts, recentMeals: meals)
    }

    private func startIfNeeded() async {
        guard coach == nil else { return }
        coach = LocalLLMCoach(settings: .shared, context: makeContext())
        messages = [greeting]

        do {
            _ = try await LocalLLMCoach.availableModels(config: CoachSettings.shared.config)
            connectionError = nil
        } catch {
            connectionError = "Проверь, что локальный сервер ИИ запущен. \(error.localizedDescription)"
        }
    }

    private var greeting: ChatMessage {
        ChatMessage(role: .coach, text: "Привет, \(profile.name)! Я твой тренер. Спроси про питание или тренировки - например: «что съесть после тренировки?» или «какой вес ставить в жиме?»")
    }

    private func resetChat() {
        coach?.reset()
        messages = [greeting]
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let coach else { return }
        // Профиль, еда и тренировки могли измениться с прошлого сообщения.
        coach.context = makeContext()
        messages.append(ChatMessage(role: .user, text: text))
        input = ""

        let coachID = UUID()
        messages.append(ChatMessage(id: coachID, role: .coach, text: ""))
        isStreaming = true

        Task {
            do {
                for try await partial in coach.streamRespond(to: text) {
                    if let index = messages.firstIndex(where: { $0.id == coachID }) {
                        messages[index].text = partial
                    }
                }
                connectionError = nil
            } catch {
                if let index = messages.firstIndex(where: { $0.id == coachID }) {
                    messages[index].text = "Не получилось получить ответ: \(error.localizedDescription)"
                }
                connectionError = error.localizedDescription
            }
            isStreaming = false
        }
    }
}

struct ChatMessage: Identifiable {
    enum Role { case user, coach }
    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}
