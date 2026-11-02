import Foundation

/// Инструменты агента. Модель сама решает, когда их вызвать,
/// а считает всегда приложение (движки), а не модель.
enum CoachTools {

    /// Описания в формате OpenAI function calling — уходят в каждый запрос.
    static let definitions: [[String: Any]] = [
        function(
            name: "get_nutrition_status",
            description: "Возвращает рассчитанные приложением нормы калорий, БЖУ и воды, а также сколько съедено и осталось на сегодня.",
            properties: [:],
            required: []
        ),
        function(
            name: "suggest_next_load",
            description: "Подсказывает следующий рабочий вес и число повторов по правилу прогрессивной перегрузки. Если вес и повторы не указаны, берёт последний подход из журнала.",
            properties: [
                "exercise": ["type": "string", "description": "Название упражнения, например «Жим лежа»"],
                "last_weight_kg": ["type": "number", "description": "Вес в прошлый раз, кг (необязательно)"],
                "last_reps": ["type": "integer", "description": "Повторы в прошлый раз (необязательно)"],
                "is_compound": ["type": "boolean", "description": "Базовое многосуставное упражнение (присед, жим, тяга) — true, изолирующее — false"]
            ],
            required: ["exercise"]
        ),
        function(
            name: "get_exercise_history",
            description: "Возвращает последние записанные подходы пользователя в указанном упражнении.",
            properties: [
                "exercise": ["type": "string", "description": "Название упражнения"]
            ],
            required: ["exercise"]
        )
    ]

    /// Выполняет вызов инструмента и возвращает текст, который уйдёт модели.
    static func run(name: String, argumentsJSON: String, context: CoachContext) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) as? [String: Any] ?? [:]

        switch name {
        case "get_nutrition_status":
            return context.nutritionText

        case "suggest_next_load":
            guard let exercise = string(args["exercise"]) else { return "Ошибка: не указано упражнение." }
            let last = lastSet(of: exercise, in: context)
            guard let weight = double(args["last_weight_kg"]) ?? last?.weightKg,
                  let reps = int(args["last_reps"]) ?? last?.reps else {
                return "В журнале нет подходов «\(exercise)». Спроси пользователя, с каким весом и на сколько повторов он работал."
            }
            let isCompound = bool(args["is_compound"]) ?? true
            let s = TrainingEngine.nextLoad(weightKg: weight, reps: reps, isCompound: isCompound)
            return "«\(exercise)»: в прошлый раз \(CoachContext.formatWeight(weight)) кг × \(reps). Следующая тренировка: \(CoachContext.formatWeight(s.weightKg)) кг × \(s.reps). \(s.note)"

        case "get_exercise_history":
            guard let exercise = string(args["exercise"]) else { return "Ошибка: не указано упражнение." }
            let sets = context.workoutLog.filter { matches($0.exercise, exercise) }.prefix(8)
            guard !sets.isEmpty else { return "В журнале нет подходов «\(exercise)»." }
            return sets.map {
                "\(CoachContext.dayFormatter.string(from: $0.date)): \($0.exercise) — \($0.sets)×\($0.reps) @ \(CoachContext.formatWeight($0.weightKg)) кг"
            }.joined(separator: "\n")

        default:
            return "Ошибка: неизвестный инструмент \(name)."
        }
    }

    // MARK: - Helpers

    private static func function(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": ["type": "object", "properties": properties, "required": required]
            ]
        ]
    }

    private static func lastSet(of exercise: String, in context: CoachContext) -> WorkoutRecord? {
        context.workoutLog.first { matches($0.exercise, exercise) }
    }

    private static func matches(_ logged: String, _ query: String) -> Bool {
        let a = logged.lowercased().replacingOccurrences(of: "ё", with: "е")
        let b = query.lowercased().replacingOccurrences(of: "ё", with: "е")
        return a.contains(b) || b.contains(a)
    }

    // Небольшие модели иногда присылают числа строками — принимаем оба варианта.
    private static func string(_ value: Any?) -> String? {
        guard let s = value as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    private static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        double(value).map { Int($0) }
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let s = value as? String { return ["true", "да", "1"].contains(s.lowercased()) }
        return nil
    }
}
