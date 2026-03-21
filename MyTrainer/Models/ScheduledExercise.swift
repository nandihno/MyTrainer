import Foundation
import SwiftData

@Model
final class ScheduledExercise {
    var id: UUID = UUID()
    var exercise: Exercise?
    var dayOfWeek: Int = 1
    var orderIndex: Int = 0
    var sets: Int = 3
    var reps: Int = 10
    var durationSeconds: Int = 0

    init(
        exercise: Exercise,
        dayOfWeek: Int,
        orderIndex: Int,
        sets: Int? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil
    ) {
        self.id = UUID()
        self.exercise = exercise
        self.dayOfWeek = dayOfWeek
        self.orderIndex = orderIndex
        self.sets = sets ?? exercise.defaultSets
        self.reps = reps ?? exercise.defaultReps
        self.durationSeconds = durationSeconds ?? exercise.defaultDurationSeconds
    }

    var isTimeBased: Bool {
        reps == 0
    }

    var subtitle: String {
        if isTimeBased {
            return "\(sets) sets \u{00D7} \(formattedDuration)"
        } else {
            return "\(sets) sets \u{00D7} \(reps) reps"
        }
    }

    var formattedDuration: String {
        if durationSeconds >= 60 {
            let minutes = durationSeconds / 60
            let seconds = durationSeconds % 60
            if seconds == 0 {
                return "\(minutes)m"
            }
            return "\(minutes)m \(seconds)s"
        }
        return "\(durationSeconds)s"
    }
}
