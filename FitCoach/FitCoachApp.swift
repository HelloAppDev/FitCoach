import SwiftUI
import SwiftData

@main
struct FitCoachApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: UserProfile.self, WorkoutSet.self, MealEntry.self)
        } catch {
            fatalError("Не удалось создать хранилище: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
