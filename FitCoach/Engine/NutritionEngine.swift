import Foundation

struct NutritionTargets {
    let bmr: Double
    let tdee: Double
    let calories: Double
    let proteinG: Double
    let fatG: Double
    let carbsG: Double
    let waterMl: Double
}

enum NutritionEngine {

    /// Базальный метаболизм
    static func bmr(for profile: UserProfile) -> Double {
        let base = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age)
        switch profile.sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    /// Суточный расход с учетом активности.
    static func tdee(for profile: UserProfile) -> Double {
        bmr(for: profile) * profile.activity.multiplier
    }

    /// Целевые калории и макронутриенты.
    static func targets(for profile: UserProfile) -> NutritionTargets {
        let bmrValue = bmr(for: profile)
        let tdeeValue = tdee(for: profile)

        var calories = tdeeValue * (1 + profile.goal.calorieAdjustment)
        // Безопасный минимум.
        calories = max(calories, profile.sex == .male ? 1500 : 1200)

        let weight = profile.weightKg
        // Белок: 2.2 г/кг на похудении, 2.0 г/кг на наборе, 1.6 г/кг на поддержании.
        let proteinPerKg: Double
        switch profile.goal {
        case .lose: proteinPerKg = 2.2
        case .maintain: proteinPerKg = 1.6
        case .gain: proteinPerKg = 2.0
        }
        let protein = proteinPerKg * weight

        // Жир: 0.9 г/кг.
        let fat = 0.9 * weight

        // Углеводы: остаток калорий.
        let remaining = max(calories - protein * 4 - fat * 9, 0)
        let carbs = remaining / 4

        let water = 35.0 * weight

        return NutritionTargets(
            bmr: bmrValue,
            tdee: tdeeValue,
            calories: calories,
            proteinG: protein,
            fatG: fat,
            carbsG: carbs,
            waterMl: water
        )
    }

    /// Текстовый совет по питанию на основе остатка калорий за день.
    static func advice(profile: UserProfile, consumedCalories: Double, consumedProtein: Double) -> String {
        let t = targets(for: profile)
        let remaining = t.calories - consumedCalories
        let proteinLeft = t.proteinG - consumedProtein

        if remaining < -150 {
            return "Сегодня перебор примерно на \(Int(-remaining)) ккал. Ужин сделай легким: белок + овощи, минимум масла и углеводов."
        }
        if remaining < 150 {
            return "Ты в норме по калориям. Добери белок (\(Int(max(proteinLeft, 0))) г) и не ешь тяжелого на ночь."
        }
        if proteinLeft > 40 {
            return "Осталось \(Int(remaining)) ккал, но белка не хватает (\(Int(proteinLeft)) г). Добавь курицу, рыбу, творог или яйца."
        }
        return "Осталось \(Int(remaining)) ккал. Закрой их сбалансированно: белок + сложные углеводы (рис, гречка) + овощи."
    }
}
