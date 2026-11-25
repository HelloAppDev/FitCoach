import Foundation

/// Разрешённые действия ИИ-агента. Модель выбирает инструмент,  а данные читает и расчёты выполняет приложение
enum CoachTools {
    static let planningGuide = """
    Доступные инструменты:
    1. get_nutrition_status - актуальные нормы калорий, БЖУ и воды, а также остаток на сегодня. Аргументы: {}.
    2. suggest_next_load - расчёт следующего рабочего веса. Аргументы: {"exercise":"название", "last_weight_kg":число (необязательно), "last_reps":число (необязательно), "is_compound":true/false (необязательно)}.
    3. get_exercise_history - история конкретного упражнения. Аргументы: {"exercise":"название"}.
    
    Выбери до трёх инструментов, необходимых для ответа на последний запрос пользователя.
    Для вопроса о следующем весе всегда выбирай suggest_next_load.
    Для вопроса о съеденном, остатке или норме всегда выбирай get_nutrition_status.
    Для просьбы показать прогресс или историю упражнения выбирай get_exercise_history.
    Для общих советов инструменты не нужны.
    
    Верни только JSON без Markdown:
    {"actions":[{"name":"имя_инструмента","arguments":{}}]}
    Если инструменты не нужны, верни {"actions":[]}.
    """
    
    static func run(name: String, arguments: [String: Any], context: CoachContext) -> String {
        switch name {
            case "get_nutrition_status":
                return context.nutritionText
                
            case "suggest_next_load":
                guard let exercise = string(arguments["exercise"]) else {
                    return "Не указано упражнение. Нужно уточнить его у пользователя."
                }
                let last = lastSet(of: exercise, in: context)
                guard let weight = double(arguments["last_weight_kg"]) ?? last?.weightKg,
                      let reps = int(arguments["last_reps"]) ?? last?.reps else {
                    return "В журнале нет подходов «\(exercise)». Нужно спросить, с каким весом и на сколько повторов пользователь работал."
                }
                let suggestion = TrainingEngine.nextLoad(
                    weightKg: weight,
                    reps: reps,
                    isCompound: bool(arguments["is_compound"]) ?? true
                )
                return "«\(exercise)»: прошлый результат — \(CoachContext.formatWeight(weight)) кг × \(reps). Рекомендация — \(CoachContext.formatWeight(suggestion.weightKg)) кг × \(suggestion.reps). \(suggestion.note)"
                
            case "get_exercise_history":
                guard let exercise = string(arguments["exercise"]) else {
                    return "Не указано упражнение. Нужно уточнить его у пользователя."
                }
                let sets = context.workoutLog.filter { matches($0.exercise, exercise) }.prefix(8)
                guard !sets.isEmpty else { return "В журнале нет подходов «\(exercise)»." }
                return sets.map {
                    "\(CoachContext.dayFormatter.string(from: $0.date)): \($0.exercise) — \($0.sets)×\($0.reps) @ \(CoachContext.formatWeight($0.weightKg)) кг"
                }.joined(separator: "\n")
                
            default:
                return "Неизвестный инструмент \(name)."
        }
    }
    
    static func isAllowed(_ name: String) -> Bool {
        ["get_nutrition_status", "suggest_next_load", "get_exercise_history"].contains(name)
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
