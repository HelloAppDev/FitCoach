import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var age = 30
    @State private var sex: Sex = .male
    @State private var heightCm = 175.0
    @State private var weightKg = 75.0
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: Goal = .maintain
    @State private var workoutsPerWeek = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("О себе") {
                    TextField("Имя", text: $name)
                    Picker("Пол", selection: $sex) {
                        ForEach(Sex.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Возраст: \(age)", value: $age, in: 14...90)
                }

                Section("Тело") {
                    HStack {
                        Text("Рост")
                        Spacer()
                        TextField("см", value: $heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("см").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Вес")
                        Spacer()
                        TextField("кг", value: $weightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("кг").foregroundStyle(.secondary)
                    }
                }

                Section("Активность") {
                    Picker("Уровень", selection: $activity) {
                        ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                    }
                    Text(activity.detail).font(.footnote).foregroundStyle(.secondary)
                    Stepper("Тренировок в неделю: \(workoutsPerWeek)", value: $workoutsPerWeek, in: 0...7)
                }

                Section("Цель") {
                    Picker("Цель", selection: $goal) {
                        ForEach(Goal.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Начать") { createProfile() }
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
            }
            .navigationTitle("Твой профиль")
        }
    }

    private func createProfile() {
        let profile = UserProfile(
            name: name.isEmpty ? "Атлет" : name,
            age: age,
            sex: sex,
            heightCm: heightCm,
            weightKg: weightKg,
            activity: activity,
            goal: goal,
            workoutsPerWeek: workoutsPerWeek
        )
        context.insert(profile)
        try? context.save()
    }
}
