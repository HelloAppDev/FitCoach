import Foundation

struct TrainingDay: Identifiable {
    let id = UUID()
    let title: String
    let exercises: [String]
}

struct LoadSuggestion {
    let weightKg: Double
    let reps: Int
    let note: String
}

enum TrainingEngine {

    /// Базовое недельное распределение по числу тренировок.
    static func weeklyPlan(daysPerWeek: Int) -> [TrainingDay] {
        switch daysPerWeek {
        case ...2:
            return [
                TrainingDay(title: "Тренировка A (всё тело)", exercises: ["Приседания", "Жим лежа", "Тяга в наклоне", "Жим стоя", "Планка"]),
                TrainingDay(title: "Тренировка B (всё тело)", exercises: ["Становая тяга", "Подтягивания", "Отжимания на брусьях", "Выпады", "Пресс"])
            ]
        case 3:
            return [
                TrainingDay(title: "Push (жим)", exercises: ["Жим лежа", "Жим гантелей на наклонной", "Жим стоя", "Разводка", "Трицепс на блоке"]),
                TrainingDay(title: "Pull (тяга)", exercises: ["Становая тяга", "Подтягивания", "Тяга в наклоне", "Тяга блока к груди", "Бицепс"]),
                TrainingDay(title: "Legs (ноги)", exercises: ["Приседания", "Румынская тяга", "Выпады", "Сгибания ног", "Икры"])
            ]
        case 4:
            return [
                TrainingDay(title: "Верх A", exercises: ["Жим лежа", "Тяга в наклоне", "Жим гантелей сидя", "Подтягивания"]),
                TrainingDay(title: "Низ A", exercises: ["Приседания", "Румынская тяга", "Выпады", "Икры"]),
                TrainingDay(title: "Верх B", exercises: ["Жим на наклонной", "Тяга блока к груди", "Махи в стороны", "Тяга штанги к подбородку"]),
                TrainingDay(title: "Низ B", exercises: ["Фронтальные приседания", "Сгибания ног", "Ягодичный мост", "Пресс"])
            ]
        default:
            return [
                TrainingDay(title: "Push", exercises: ["Жим лежа", "Жим на наклонной", "Жим стоя", "Трицепс"]),
                TrainingDay(title: "Pull", exercises: ["Становая тяга", "Подтягивания", "Тяга в наклоне", "Бицепс"]),
                TrainingDay(title: "Legs", exercises: ["Приседания", "Румынская тяга", "Выпады", "Икры"]),
                TrainingDay(title: "Верх (легкий)", exercises: ["Жим гантелей", "Тяга блока", "Махи", "Спина"]),
                TrainingDay(title: "Низ (легкий)", exercises: ["Гоблет-присед", "Сгибания ног", "Ягодичный мост", "Пресс"])
            ]
        }
    }

    /// Прогрессивная перегрузка: если прошлый подход закрыт по плану — добавляем вес.
    static func nextLoad(last: WorkoutSet, isCompound: Bool = true) -> LoadSuggestion {
        nextLoad(weightKg: last.weightKg, reps: last.reps, isCompound: isCompound)
    }

    /// То же правило, но на «сырых» значениях (для ИИ-инструментов).
    static func nextLoad(weightKg: Double, reps: Int, isCompound: Bool) -> LoadSuggestion {
        let targetReps = 8
        if reps >= targetReps {
            let increment = isCompound ? 2.5 : 1.25
            return LoadSuggestion(
                weightKg: weightKg + increment,
                reps: targetReps - 2,
                note: "Прошлый раз закрыл \(reps) повторов — добавляем \(increment) кг."
            )
        } else {
            return LoadSuggestion(
                weightKg: weightKg,
                reps: reps + 1,
                note: "Вес пока не трогаем: добери повторы до \(targetReps)."
            )
        }
    }
}
