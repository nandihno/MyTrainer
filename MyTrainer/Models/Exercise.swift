import Foundation
import SwiftData

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var appleWorkoutType: Int = 0
    var defaultSets: Int = 3
    var defaultReps: Int = 10
    var defaultDurationSeconds: Int = 0
    var notes: String = ""
    var createdAt: Date = Date()

    init(
        name: String,
        appleWorkoutType: Int,
        defaultSets: Int = 3,
        defaultReps: Int = 10,
        defaultDurationSeconds: Int = 0,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.appleWorkoutType = appleWorkoutType
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.defaultDurationSeconds = defaultDurationSeconds
        self.notes = notes
        self.createdAt = Date()
    }

    var isTimeBased: Bool {
        defaultReps == 0
    }
}
