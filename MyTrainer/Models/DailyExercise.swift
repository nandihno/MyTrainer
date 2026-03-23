import Foundation
import SwiftData

/// A per-date exercise entry.
/// - When `scheduledExerciseID` is non-nil it overrides that template entry for this date only.
/// - When `scheduledExerciseID` is nil it is a one-off addition for this date only.
@Model
final class DailyExercise {
    var id: UUID = UUID()
    var exercise: Exercise?
    var date: Date = Date()                     // start-of-day for the target date
    var sets: Int = 3
    var reps: Int = 10
    var durationSeconds: Int = 0
    var orderIndex: Int = 0
    var scheduledExerciseID: UUID?               // links to ScheduledExercise.id when overriding
    var createdAt: Date = Date()

    init(
        exercise: Exercise,
        date: Date,
        sets: Int,
        reps: Int,
        durationSeconds: Int,
        orderIndex: Int,
        scheduledExerciseID: UUID? = nil
    ) {
        self.id = UUID()
        self.exercise = exercise
        self.date = date
        self.sets = sets
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.orderIndex = orderIndex
        self.scheduledExerciseID = scheduledExerciseID
        self.createdAt = Date()
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
            if seconds == 0 { return "\(minutes)m" }
            return "\(minutes)m \(seconds)s"
        }
        return "\(durationSeconds)s"
    }

    /// Whether this is a one-off addition (not overriding a template entry)
    var isOneOff: Bool {
        scheduledExerciseID == nil
    }
}
