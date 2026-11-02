import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var exercise: String
    var weightKg: Double
    var reps: Int
    var sets: Int
    var date: Date

    init(exercise: String, weightKg: Double, reps: Int, sets: Int, date: Date = Date()) {
        self.exercise = exercise
        self.weightKg = weightKg
        self.reps = reps
        self.sets = sets
        self.date = date
    }

    var volume: Double { weightKg * Double(reps) * Double(sets) }
}
