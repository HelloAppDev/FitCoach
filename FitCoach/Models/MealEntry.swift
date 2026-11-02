import Foundation
import SwiftData

@Model
final class MealEntry {
    var name: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var date: Date

    init(name: String, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, date: Date = Date()) {
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.date = date
    }
}
