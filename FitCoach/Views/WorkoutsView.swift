import SwiftUI
import SwiftData

struct WorkoutsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSet.date, order: .reverse) private var workouts: [WorkoutSet]

    @State private var showingAdd = false

    private var plan: [TrainingDay] { TrainingEngine.weeklyPlan(daysPerWeek: profile.workoutsPerWeek) }

    var body: some View {
        NavigationStack {
            List {
                Section("План на неделю") {
                    ForEach(plan) { day in
                        DisclosureGroup(day.title) {
                            ForEach(day.exercises, id: \.self) { ex in
                                Text(ex).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("История") {
                    if workouts.isEmpty {
                        Text("Пока пусто").foregroundStyle(.secondary)
                    }
                    ForEach(workouts) { set in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(set.exercise).font(.headline)
                                Spacer()
                                Text(set.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("\(set.sets)×\(set.reps) @ \(set.weightKg, specifier: "%.1f") кг")
                                .font(.subheadline)
                            let s = TrainingEngine.nextLoad(last: set)
                            Text("Следующий раз: \(s.weightKg, specifier: "%.1f") кг × \(s.reps). \(s.note)")
                                .font(.caption).foregroundStyle(.blue)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Зал")
            .toolbar {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showingAdd) {
                AddWorkoutView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(workouts[index]) }
        try? context.save()
    }
}

struct AddWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var exercise = "Жим лежа"
    @State private var weight = 40.0
    @State private var reps = 8
    @State private var sets = 3

    var body: some View {
        NavigationStack {
            Form {
                TextField("Упражнение", text: $exercise)
                Stepper("Подходы: \(sets)", value: $sets, in: 1...10)
                Stepper("Повторы: \(reps)", value: $reps, in: 1...30)
                HStack {
                    Text("Вес, кг")
                    Spacer()
                    TextField("кг", value: $weight, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("Новая запись")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        context.insert(WorkoutSet(exercise: exercise, weightKg: weight, reps: reps, sets: sets))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
