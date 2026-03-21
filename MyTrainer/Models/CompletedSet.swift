import Foundation
import SwiftData

@Model
final class CompletedSet {
    var id: UUID = UUID()
    var scheduledExercise: ScheduledExercise?
    var setNumber: Int = 1
    var completedAt: Date = Date()
    var isBonus: Bool = false
    var notes: String = ""

    init(
        scheduledExercise: ScheduledExercise,
        setNumber: Int,
        completedAt: Date = Date(),
        isBonus: Bool = false,
        notes: String = ""
    ) {
        self.id = UUID()
        self.scheduledExercise = scheduledExercise
        self.setNumber = setNumber
        self.completedAt = completedAt
        self.isBonus = isBonus
        self.notes = notes
    }
}
