import EventKit
import Foundation

struct CalendarEventDraft: Identifiable, Sendable, Equatable {
    let id = UUID()
    let title: String
    let startDate: Date
    let durationMinutes: Int
    let notes: String?
    let reminderMinutes: Int?

    var endDate: Date {
        startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    var confirmationText: String {
        let date = startDate.formatted(
            .dateTime
                .locale(Locale(identifier: "ru_RU"))
                .weekday(.wide)
                .day()
                .month(.wide)
                .hour()
                .minute()
        )
        return "«\(title)» — \(date), \(durationMinutes) мин."
    }
}

enum CalendarServiceError: LocalizedError {
    case accessDenied
    case noWritableCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Нет разрешения на добавление событий в календарь. Разреши доступ в настройках iOS."
        case .noWritableCalendar:
            return "На устройстве не найден календарь, в который можно добавить тренировку."
        }
    }
}

@MainActor
final class CalendarService {
    private let eventStore = EKEventStore()

    func createEvent(from draft: CalendarEventDraft) async throws -> String {
        let granted = try await eventStore.requestWriteOnlyAccessToEvents()
        guard granted else { throw CalendarServiceError.accessDenied }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarServiceError.noWritableCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.notes = draft.notes
        event.calendar = calendar
        if let reminderMinutes = draft.reminderMinutes, reminderMinutes > 0 {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-reminderMinutes * 60)))
        }

        try eventStore.save(event, span: .thisEvent, commit: true)
        return "Тренировка добавлена в календарь: \(draft.confirmationText)"
    }
}
