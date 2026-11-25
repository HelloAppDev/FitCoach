import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ChatView: View {
    let profile: UserProfile

    @Query(sort: \WorkoutSet.date, order: .reverse) private var workouts: [WorkoutSet]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]

    @State private var coach: LocalLLMCoach?
    @State private var input = ""
    @State private var messages: [ChatMessage] = []
    @State private var isStreaming = false
    @State private var connectionError: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isCalendarActionRunning = false

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

                if let draft = coach?.pendingCalendarEvent {
                    calendarConfirmation(draft)
                }

                if let selectedImageData {
                    selectedImagePreview(selectedImageData)
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
            VStack(alignment: .leading, spacing: 8) {
                if let data = message.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text(message.text.isEmpty ? "…" : message.text)
            }
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if message.role == .coach { Spacer() }
        }
    }

    private var inputBar: some View {
        HStack {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "photo")
            }
            .disabled(isStreaming || coach?.pendingCalendarEvent != nil)
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }

            TextField("Сообщение...", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button { send() } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(
                isStreaming ||
                coach == nil ||
                coach?.pendingCalendarEvent != nil ||
                (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImageData == nil)
            )
        }
        .padding()
    }

    private func selectedImagePreview(_ data: Data) -> some View {
        HStack(spacing: 12) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("Изображение будет отправлено Gemma")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                selectedPhoto = nil
                selectedImageData = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .padding(.horizontal)
    }

    private func calendarConfirmation(_ draft: CalendarEventDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Добавить тренировку в календарь?", systemImage: "calendar.badge.plus")
                .font(.subheadline.bold())
            Text(draft.confirmationText)
                .font(.footnote)
            HStack {
                Button("Отмена", role: .cancel) { cancelCalendarEvent() }
                    .disabled(isStreaming || isCalendarActionRunning)
                Spacer()
                Button("Добавить") {
                    Task { await confirmCalendarEvent() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStreaming || isCalendarActionRunning)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func makeContext() -> CoachContext {
        CoachContext(profile: profile, recentWorkouts: workouts, recentMeals: meals)
    }

    private func startIfNeeded() async {
        guard coach == nil else { return }
        coach = LocalLLMCoach(settings: .shared, context: makeContext())
        messages = [greeting]

        do {
            let models = try await LocalLLMCoach.availableModels(config: CoachSettings.shared.chatConfig)
            let missing = [CoachSettings.chatModel, CoachSettings.agentModel].filter { !models.contains($0) }
            connectionError = missing.isEmpty
                ? nil
                : "Не загружены модели: \(missing.joined(separator: ", "))."
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
        let typedText = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageData = selectedImageData
        guard !typedText.isEmpty || imageData != nil, let coach else { return }
        let text = typedText.isEmpty ? "Проанализируй это изображение." : typedText
        // Профиль, еда и тренировки могли измениться с прошлого сообщения.
        coach.context = makeContext()
        messages.append(ChatMessage(role: .user, text: text, imageData: imageData))
        input = ""
        selectedPhoto = nil
        selectedImageData = nil

        let coachID = UUID()
        messages.append(ChatMessage(id: coachID, role: .coach, text: ""))
        isStreaming = true

        Task {
            do {
                for try await partial in coach.streamRespond(to: text, imageData: imageData) {
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

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.82) else {
            selectedImageData = nil
            return
        }
        selectedImageData = jpeg
    }

    private func confirmCalendarEvent() async {
        guard let coach else { return }
        isCalendarActionRunning = true
        do {
            let result = try await coach.confirmPendingCalendarEvent()
            messages.append(ChatMessage(role: .coach, text: result))
        } catch {
            messages.append(ChatMessage(role: .coach, text: "Не удалось добавить тренировку: \(error.localizedDescription)"))
        }
        isCalendarActionRunning = false
    }

    private func cancelCalendarEvent() {
        guard let coach else { return }
        messages.append(ChatMessage(role: .coach, text: coach.cancelPendingCalendarEvent()))
    }
}

struct ChatMessage: Identifiable {
    enum Role { case user, coach }
    let id: UUID
    let role: Role
    var text: String
    let imageData: Data?

    init(id: UUID = UUID(), role: Role, text: String, imageData: Data? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.imageData = imageData
    }
}
