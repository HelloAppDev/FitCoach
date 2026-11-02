import SwiftUI
import SwiftData

struct HomeView: View {
    let profile: UserProfile

    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @Query(sort: \WorkoutSet.date, order: .reverse) private var workouts: [WorkoutSet]

    private var targets: NutritionTargets { NutritionEngine.targets(for: profile) }

    private var todaysMeals: [MealEntry] {
        meals.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var consumedCalories: Double { todaysMeals.reduce(0) { $0 + $1.calories } }
    private var consumedProtein: Double { todaysMeals.reduce(0) { $0 + $1.proteinG } }

    private var todaysWorkouts: [WorkoutSet] {
        workouts.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    calorieCard
                    macroRow
                    adviceCard
                    trainingCard
                }
                .padding()
            }
            .navigationTitle("Привет, \(profile.name)")
        }
    }

    private var calorieCard: some View {
        VStack(spacing: 8) {
            Text("Калории сегодня")
                .font(.headline)
            Text("\(Int(consumedCalories)) / \(Int(targets.calories))")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            ProgressView(value: min(consumedCalories, targets.calories), total: targets.calories)
                .tint(consumedCalories > targets.calories ? .red : .green)
            Text("TDEE \(Int(targets.tdee)) ккал · BMR \(Int(targets.bmr)) ккал")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var macroRow: some View {
        HStack(spacing: 12) {
            macroBox("Белок", value: consumedProtein, target: targets.proteinG, unit: "г", color: .blue)
            macroBox("Углеводы", value: todaysMeals.reduce(0) { $0 + $1.carbsG }, target: targets.carbsG, unit: "г", color: .orange)
            macroBox("Жир", value: todaysMeals.reduce(0) { $0 + $1.fatG }, target: targets.fatG, unit: "г", color: .pink)
        }
    }

    private func macroBox(_ title: String, value: Double, target: Double, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(value))").font(.title3.bold())
            Text("из \(Int(target)) \(unit)").font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: min(value, target), total: max(target, 1)).tint(color)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Совет по питанию", systemImage: "lightbulb.fill")
                .font(.headline)
            Text(NutritionEngine.advice(profile: profile, consumedCalories: consumedCalories, consumedProtein: consumedProtein))
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var trainingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Сегодня в зале", systemImage: "dumbbell.fill")
                .font(.headline)
            if todaysWorkouts.isEmpty {
                Text("Пока нет записей. План на неделю — во вкладке «Зал».")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(todaysWorkouts) { set in
                    Text("• \(set.exercise): \(set.sets)×\(set.reps) @ \(set.weightKg, specifier: "%.1f") кг")
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
