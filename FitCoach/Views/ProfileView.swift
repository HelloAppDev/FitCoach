import SwiftUI
import SwiftData

struct ProfileView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context

    private var targets: NutritionTargets { NutritionEngine.targets(for: profile) }

    var body: some View {
        NavigationStack {
            Form {
                Section("О себе") {
                    TextField("Имя", text: $profile.name)
                    Picker("Пол", selection: Binding(
                        get: { profile.sex },
                        set: { profile.sexRaw = $0.rawValue }
                    )) {
                        ForEach(Sex.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Возраст: \(profile.age)", value: $profile.age, in: 14...90)
                }

                Section("Тело") {
                    Stepper("Рост: \(Int(profile.heightCm)) см", value: $profile.heightCm, in: 120...230, step: 1)
                    Stepper("Вес: \(profile.weightKg, specifier: "%.1f") кг", value: $profile.weightKg, in: 35...200, step: 0.5)
                }

                Section("Активность") {
                    Picker("Уровень", selection: Binding(
                        get: { profile.activity },
                        set: { profile.activityRaw = $0.rawValue }
                    )) {
                        ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Тренировок в неделю: \(profile.workoutsPerWeek)", value: $profile.workoutsPerWeek, in: 0...7)
                }

                Section("Цель") {
                    Picker("Цель", selection: Binding(
                        get: { profile.goal },
                        set: { profile.goalRaw = $0.rawValue }
                    )) {
                        ForEach(Goal.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("ИИ-коуч") {
                    NavigationLink("Настройки модели") { CoachSettingsView() }
                }

                Section("Расчётные нормы") {
                    row("BMR", "\(Int(targets.bmr)) ккал")
                    row("TDEE", "\(Int(targets.tdee)) ккал")
                    row("Калории", "\(Int(targets.calories)) ккал")
                    row("Белок", "\(Int(targets.proteinG)) г")
                    row("Углеводы", "\(Int(targets.carbsG)) г")
                    row("Жир", "\(Int(targets.fatG)) г")
                    row("Вода", "\(Int(targets.waterMl)) мл")
                }
            }
            .navigationTitle("Профиль")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
