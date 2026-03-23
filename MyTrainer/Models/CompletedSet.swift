import Foundation
import SwiftData

@Model
final class CompletedSet {
    var id: UUID = UUID()
    var scheduledExercise: ScheduledExercise?
    var dailyExercise: DailyExercise?
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
        self.dailyExercise = nil
        self.setNumber = setNumber
        self.completedAt = completedAt
        self.isBonus = isBonus
        self.notes = notes
    }

    /// Init for one-off (DailyExercise) sets
    init(
        dailyExercise: DailyExercise,
        setNumber: Int,
        completedAt: Date = Date(),
        isBonus: Bool = false,
        notes: String = ""
    ) {
        self.id = UUID()
        self.scheduledExercise = nil
        self.dailyExercise = dailyExercise
        self.setNumber = setNumber
        self.completedAt = completedAt
        self.isBonus = isBonus
        self.notes = notes
    }
}
