import Foundation

struct CoachContext: Sendable {
    let name: String
    let age: Int
    let sexTitle: String
    let heightCm: Double
    let weightKg: Double
    let activityTitle: String
    let goalTitle: String
    let workoutsPerWeek: Int

    let bmr: Double
    let tdee: Double
    let calories: Double
    let proteinG: Double
    let fatG: Double
    let carbsG: Double
    let waterMl: Double

    let todayTitle: String
    let todayMealsCount: Int
    let eatenCalories: Double
    let eatenProteinG: Double
    let eatenFatG: Double
    let eatenCarbsG: Double

    let recentWorkoutsText: String
    let recentMealsText: String
    /// Журнал подходов для инструментов агента (свежие сверху).
    let workoutLog: [WorkoutRecord]

    init(profile: UserProfile, recentWorkouts: [WorkoutSet] = [], recentMeals: [MealEntry] = [], now: Date = Date()) {
        let t = NutritionEngine.targets(for: profile)
        self.name = profile.name
        self.age = profile.age
        self.sexTitle = profile.sex.title
        self.heightCm = profile.heightCm
        self.weightKg = profile.weightKg
        self.activityTitle = profile.activity.title
        self.goalTitle = profile.goal.title
        self.workoutsPerWeek = profile.workoutsPerWeek

        self.bmr = t.bmr
        self.tdee = t.tdee
        self.calories = t.calories
        self.proteinG = t.proteinG
        self.fatG = t.fatG
        self.carbsG = t.carbsG
        self.waterMl = t.waterMl

        // Итоги за сегодня считает приложение, а не модель.
        let calendar = Calendar.current
        let todayMeals = recentMeals.filter { calendar.isDate($0.date, inSameDayAs: now) }
        self.todayTitle = Self.dayFormatter.string(from: now)
        self.todayMealsCount = todayMeals.count
        self.eatenCalories = todayMeals.reduce(0) { $0 + $1.calories }
        self.eatenProteinG = todayMeals.reduce(0) { $0 + $1.proteinG }
        self.eatenFatG = todayMeals.reduce(0) { $0 + $1.fatG }
        self.eatenCarbsG = todayMeals.reduce(0) { $0 + $1.carbsG }

        self.recentWorkoutsText = Self.format(workouts: recentWorkouts)
        self.recentMealsText = Self.format(meals: recentMeals)
        self.workoutLog = recentWorkouts.map {
            WorkoutRecord(exercise: $0.exercise, weightKg: $0.weightKg, reps: $0.reps, sets: $0.sets, date: $0.date)
        }
    }

    var summary: String {
        var text = """
        Имя: \(name)
        Возраст: \(age), пол: \(sexTitle)
        Рост: \(Int(heightCm)) см, вес: \(weightKg) кг
        Активность: \(activityTitle), тренировок в неделю: \(workoutsPerWeek)
        Цель: \(goalTitle)

        """
        text += nutritionText
        text += recentWorkoutsText
        text += recentMealsText
        return text
    }

    /// Нормы и итоги за сегодня — отдельно, чтобы отдавать их из инструмента.
    var nutritionText: String {
        """
        Рассчитанные приложением нормы (это истина, не пересчитывай их сам):
        - BMR: \(Int(bmr)) ккал
        - TDEE (суточный расход): \(Int(tdee)) ккал
        - Целевые калории: \(Int(calories)) ккал
        - Белок: \(Int(proteinG)) г
        - Жиры: \(Int(fatG)) г
        - Углеводы: \(Int(carbsG)) г
        - Вода: \(Int(waterMl)) мл

        Сегодня \(todayTitle). Съедено за сегодня (\(todayMealsCount) приёмов пищи, посчитано приложением):
        - Калории: \(Int(eatenCalories)) ккал, \(Self.remainder(calories - eatenCalories, unit: "ккал"))
        - Белок: \(Int(eatenProteinG)) г, \(Self.remainder(proteinG - eatenProteinG, unit: "г"))
        - Жиры: \(Int(eatenFatG)) г, \(Self.remainder(fatG - eatenFatG, unit: "г"))
        - Углеводы: \(Int(eatenCarbsG)) г, \(Self.remainder(carbsG - eatenCarbsG, unit: "г"))
        """
    }

    func systemPrompt(toolsEnabled: Bool) -> String {
        let toolRules = toolsEnabled ? """

        - Следующий рабочий вес не придумывай — вызывай инструмент suggest_next_load.
        - Историю конкретного упражнения смотри инструментом get_exercise_history.
        - Если сомневаешься в нормах или остатке на сегодня — вызывай get_nutrition_status.
        """ : ""
        return """
        Ты персональный фитнес- и нутрициолог-коуч в приложении. Отвечай по-русски, дружелюбно, кратко и конкретно (2–5 предложений).

        Правила:
        - Числа калорий, БЖУ и воды бери только из данных ниже, никогда не выдумывай их.
        - Сколько съедено и сколько осталось на сегодня — бери готовые значения из блока «Съедено за сегодня», не складывай сам.
        - Советуй только здоровые методы: без экстремальных диет, без препаратов, без опасных советов.
        - Если речь о боли, травме или медицинской проблеме — посоветуй обратиться к врачу.
        - Давай конкретные продукты и упражнения, а не общие слова.\(toolRules)

        Данные пользователя:
        \(summary)
        """
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static func remainder(_ value: Double, unit: String) -> String {
        value >= 0 ? "осталось \(Int(value)) \(unit)" : "перебор \(Int(-value)) \(unit)"
    }

    private static func format(workouts: [WorkoutSet]) -> String {
        guard !workouts.isEmpty else { return "" }
        let lines = workouts.prefix(12).map { set in
            " \(dayFormatter.string(from: set.date)): \(set.exercise) — \(set.sets)×\(set.reps) @ \(formatWeight(set.weightKg)) кг"
        }
        return "\n\nПоследние тренировки:\n" + lines.joined(separator: "\n")
    }

    private static func format(meals: [MealEntry]) -> String {
        guard !meals.isEmpty else { return "" }
        let lines = meals.prefix(12).map { meal in
            " \(dayFormatter.string(from: meal.date)): \(meal.name) — \(Int(meal.calories)) ккал (Б \(Int(meal.proteinG)) / Ж \(Int(meal.fatG)) / У \(Int(meal.carbsG)))"
        }
        return "\n\nПоследние приёмы пищи:\n" + lines.joined(separator: "\n")
    }

    static func formatWeight(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct WorkoutRecord: Sendable {
    let exercise: String
    let weightKg: Double
    let reps: Int
    let sets: Int
    let date: Date
}
