import Foundation
import SwiftData

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return "Мужской"
        case .female: return "Женский"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: return "Сидячий"
        case .light: return "Легкая активность"
        case .moderate: return "Средняя активность"
        case .active: return "Высокая активность"
        case .veryActive: return "Очень высокая"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: return "Работа за столом, мало движения"
        case .light: return "Тренировки 1–3 раза в неделю"
        case .moderate: return "Тренировки 3–5 раз в неделю"
        case .active: return "Тренировки 6–7 раз в неделю"
        case .veryActive: return "Физическая работа + тренировки"
        }
    }

    /// Множитель TDEE (Mifflin-St Jeor).
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case lose
    case maintain
    case gain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lose: return "Похудеть"
        case .maintain: return "Держать форму"
        case .gain: return "Набрать массу"
        }
    }

    /// Отклонение калорий от TDEE.
    var calorieAdjustment: Double {
        switch self {
        case .lose: return -0.18
        case .maintain: return 0.0
        case .gain: return 0.12
        }
    }
}

@Model
final class UserProfile {
    var name: String
    var age: Int
    var sexRaw: String
    var heightCm: Double
    var weightKg: Double
    var activityRaw: String
    var goalRaw: String
    var workoutsPerWeek: Int
    var createdAt: Date

    init(
        name: String = "",
        age: Int = 30,
        sex: Sex = .male,
        heightCm: Double = 175,
        weightKg: Double = 75,
        activity: ActivityLevel = .moderate,
        goal: Goal = .maintain,
        workoutsPerWeek: Int = 3
    ) {
        self.name = name
        self.age = age
        self.sexRaw = sex.rawValue
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityRaw = activity.rawValue
        self.goalRaw = goal.rawValue
        self.workoutsPerWeek = workoutsPerWeek
        self.createdAt = Date()
    }

    var sex: Sex { Sex(rawValue: sexRaw) ?? .male }
    var activity: ActivityLevel { ActivityLevel(rawValue: activityRaw) ?? .moderate }
    var goal: Goal { Goal(rawValue: goalRaw) ?? .maintain }
}
