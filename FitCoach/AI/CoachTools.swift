import Foundation

enum CoachToolResult {
    case text(String)
    case requiresCalendarConfirmation(CalendarEventDraft)
}

/// Белый список действий агента. Qwen выбирает действие,
/// а приложение проверяет аргументы и выполняет разрешённый Swift-код.
enum CoachTools {
    static func planningGuide(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"

        return """
        Текущее локальное время: \(formatter.string(from: now)).
        Часовой пояс устройства: \(TimeZone.current.identifier).

        Доступные инструменты:
        1. get_nutrition_status — актуальные нормы калорий, БЖУ и воды, съеденное и остаток на сегодня. Аргументы: {}.
        2. suggest_next_load — расчёт следующего рабочего веса. Аргументы: {"exercise":"название", "last_weight_kg":число (необязательно), "last_reps":число (необязательно), "is_compound":true/false (необязательно)}.
        3. get_exercise_history — история конкретного упражнения. Аргументы: {"exercise":"название"}.
        4. create_calendar_event — подготовить будущую тренировку для системного календаря. Аргументы: {"title":"название", "start_at":"ISO 8601 с часовым поясом", "duration_minutes":60, "notes":"описание" (необязательно), "reminder_minutes":30 (необязательно)}.

        Правила:
        - Выбери до трёх инструментов, необходимых для ответа на последний запрос.
        - Для вопроса о следующем весе всегда выбирай suggest_next_load.
        - Для вопроса о съеденном, остатке или норме выбирай get_nutrition_status.
        - Для просьбы показать прогресс или историю упражнения выбирай get_exercise_history.
        - create_calendar_event выбирай только при явной просьбе запланировать или добавить тренировку в календарь.
        - Относительные даты («завтра», «в пятницу») преобразуй в точный ISO 8601, используя текущее время выше.
        - За один запрос создавай не больше одного календарного события.
        - Для общих советов инструменты не нужны.

        Верни только JSON без Markdown:
        {"actions":[{"name":"имя_инструмента","arguments":{}}]}
        Если инструменты не нужны, верни {"actions":[]}.
        """
    }

    static func prepare(name: String, arguments: [String: Any], context: CoachContext) -> CoachToolResult {
        switch name {
        case "get_nutrition_status":
            return .text(context.nutritionText)

        case "suggest_next_load":
            guard let exercise = string(arguments["exercise"]) else {
                return .text("Не указано упражнение. Нужно уточнить его у пользователя.")
            }
            let last = lastSet(of: exercise, in: context)
            guard let weight = double(arguments["last_weight_kg"]) ?? last?.weightKg,
                  let reps = int(arguments["last_reps"]) ?? last?.reps else {
                return .text("В журнале нет подходов «\(exercise)». Нужно спросить, с каким весом и на сколько повторов пользователь работал.")
            }
            let suggestion = TrainingEngine.nextLoad(
                weightKg: weight,
                reps: reps,
                isCompound: bool(arguments["is_compound"]) ?? true
            )
            return .text("«\(exercise)»: прошлый результат — \(CoachContext.formatWeight(weight)) кг × \(reps). Рекомендация — \(CoachContext.formatWeight(suggestion.weightKg)) кг × \(suggestion.reps). \(suggestion.note)")

        case "get_exercise_history":
            guard let exercise = string(arguments["exercise"]) else {
                return .text("Не указано упражнение. Нужно уточнить его у пользователя.")
            }
            let sets = context.workoutLog.filter { matches($0.exercise, exercise) }.prefix(8)
            guard !sets.isEmpty else { return .text("В журнале нет подходов «\(exercise)».") }
            let history = sets.map {
                "\(CoachContext.dayFormatter.string(from: $0.date)): \($0.exercise) — \($0.sets)×\($0.reps) @ \(CoachContext.formatWeight($0.weightKg)) кг"
            }.joined(separator: "\n")
            return .text(history)

        case "create_calendar_event":
            return calendarDraft(from: arguments)

        default:
            return .text("Неизвестный инструмент \(name).")
        }
    }

    static func isAllowed(_ name: String) -> Bool {
        [
            "get_nutrition_status",
            "suggest_next_load",
            "get_exercise_history",
            "create_calendar_event"
        ].contains(name)
    }

    private static func calendarDraft(from arguments: [String: Any]) -> CoachToolResult {
        guard let title = string(arguments["title"]),
              let startString = string(arguments["start_at"]),
              let startDate = isoDate(startString) else {
            return .text("Для календаря нужны название и точные дата со временем. Уточни их у пользователя.")
        }
        guard startDate > Date() else {
            return .text("Указанное время тренировки уже прошло. Нужно уточнить будущую дату.")
        }

        let duration = min(max(int(arguments["duration_minutes"]) ?? 60, 15), 360)
        let reminder = int(arguments["reminder_minutes"]).map { min(max($0, 0), 1_440) }
        let draft = CalendarEventDraft(
            title: title,
            startDate: startDate,
            durationMinutes: duration,
            notes: string(arguments["notes"]),
            reminderMinutes: reminder
        )
        return .requiresCalendarConfirmation(draft)
    }

    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func lastSet(of exercise: String, in context: CoachContext) -> WorkoutRecord? {
        context.workoutLog.first { matches($0.exercise, exercise) }
    }

    private static func matches(_ logged: String, _ query: String) -> Bool {
        let a = logged.lowercased().replacingOccurrences(of: "ё", with: "е")
        let b = query.lowercased().replacingOccurrences(of: "ё", with: "е")
        return a.contains(b) || b.contains(a)
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            return Double(string.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        double(value).map(Int.init)
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? String {
            return ["true", "да", "1"].contains(value.lowercased())
        }
        return nil
    }
}
