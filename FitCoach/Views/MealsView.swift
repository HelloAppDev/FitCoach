import SwiftUI
import SwiftData

struct MealsView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if meals.isEmpty {
                    Text("Добавь первый приём пищи — и я посчитаю остаток калорий.")
                        .foregroundStyle(.secondary)
                }
                ForEach(meals) { meal in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(meal.name).font(.headline)
                            Spacer()
                            Text("\(Int(meal.calories)) ккал").foregroundStyle(.secondary)
                        }
                        Text("Б \(Int(meal.proteinG)) · У \(Int(meal.carbsG)) · Ж \(Int(meal.fatG))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Питание")
            .toolbar {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showingAdd) {
                AddMealView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(meals[index]) }
        try? context.save()
    }
}

struct AddMealView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Что съел", text: $name)
                HStack {
                    Text("Калории")
                    Spacer()
                    TextField("ккал", value: $calories, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Белок, г")
                    Spacer()
                    TextField("г", value: $protein, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Углеводы, г")
                    Spacer()
                    TextField("г", value: $carbs, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Жир, г")
                    Spacer()
                    TextField("г", value: $fat, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle("Новый приём пищи")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        context.insert(MealEntry(name: name.isEmpty ? "Приём пищи" : name, calories: calories, proteinG: protein, carbsG: carbs, fatG: fat))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
