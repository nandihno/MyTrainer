import Foundation
import SwiftData

@Model
final class CompletedSet {
    var id: UUID = UUID()
    var scheduledExercise: ScheduledExercise?
    var dailyExerciseID: UUID?          // links to DailyExercise.id (stored as UUID, not a relationship)
    var setNumber: Int = 1
    var completedAt: Date = Date()
    var isBonus: Bool = false
    var notes: String = ""

    /// Init for template-based (ScheduledExercise) sets
    init(
        scheduledExercise: ScheduledExercise,
        setNumber: Int,
        completedAt: Date = Date(),
        isBonus: Bool = false,
        notes: String = ""
    ) {
        self.id = UUID()
        self.scheduledExercise = scheduledExercise
        self.dailyExerciseID = nil
        self.setNumber = setNumber
        self.completedAt = completedAt
        self.isBonus = isBonus
        self.notes = notes
    }

    /// Init for one-off (DailyExercise) sets
    init(
        dailyExerciseID: UUID,
        setNumber: Int,
        completedAt: Date = Date(),
        isBonus: Bool = false,
        notes: String = ""
    ) {
        self.id = UUID()
        self.scheduledExercise = nil
        self.dailyExerciseID = dailyExerciseID
        self.setNumber = setNumber
        self.completedAt = completedAt
        self.isBonus = isBonus
        self.notes = notes
    }
}
