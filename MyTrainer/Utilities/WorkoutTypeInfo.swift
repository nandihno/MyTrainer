import SwiftUI
import HealthKit

struct WorkoutTypeInfo: Identifiable {
    let typeID: Int
    let activityType: HKWorkoutActivityType
    let displayName: String
    let color: Color
    let symbol: String

    var id: Int { typeID }
}

extension WorkoutTypeInfo {
    // Offset used for treadmill variants so they get unique IDs
    // while sharing the same HKWorkoutActivityType
    private static let treadmillOffset = 10000

    static let allTypes: [WorkoutTypeInfo] = [
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.coreTraining.rawValue),
            activityType: .coreTraining,
            displayName: "Core Training",
            color: Color(red: 0.96, green: 0.62, blue: 0.04),
            symbol: "figure.core.training"
        ),
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.traditionalStrengthTraining.rawValue),
            activityType: .traditionalStrengthTraining,
            displayName: "Strength Training",
            color: Color(red: 0.39, green: 0.40, blue: 0.95),
            symbol: "dumbbell.fill"
        ),
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.functionalStrengthTraining.rawValue),
            activityType: .functionalStrengthTraining,
            displayName: "Functional Strength",
            color: Color(red: 0.58, green: 0.20, blue: 0.92),
            symbol: "figure.strengthtraining.functional"
        ),
        // Running — Outdoor
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.running.rawValue),
            activityType: .running,
            displayName: "Outdoor Running",
            color: Color(red: 0.98, green: 0.45, blue: 0.09),
            symbol: "figure.run"
        ),
        // Running — Treadmill
        WorkoutTypeInfo(
            typeID: treadmillOffset + Int(HKWorkoutActivityType.running.rawValue),
            activityType: .running,
            displayName: "Treadmill Running",
            color: Color(red: 0.95, green: 0.55, blue: 0.20),
            symbol: "figure.run.treadmill"
        ),
        // Walking — Outdoor
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.walking.rawValue),
            activityType: .walking,
            displayName: "Outdoor Walking",
            color: Color(red: 0.08, green: 0.72, blue: 0.65),
            symbol: "figure.walk"
        ),
        // Walking — Treadmill
        WorkoutTypeInfo(
            typeID: treadmillOffset + Int(HKWorkoutActivityType.walking.rawValue),
            activityType: .walking,
            displayName: "Treadmill Walking",
            color: Color(red: 0.15, green: 0.65, blue: 0.60),
            symbol: "figure.walk.treadmill"
        ),
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.cycling.rawValue),
            activityType: .cycling,
            displayName: "Cycling",
            color: Color(red: 0.23, green: 0.51, blue: 0.96),
            symbol: "figure.outdoor.cycle"
        ),
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.yoga.rawValue),
            activityType: .yoga,
            displayName: "Yoga",
            color: Color(red: 0.96, green: 0.25, blue: 0.37),
            symbol: "figure.yoga"
        ),
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.highIntensityIntervalTraining.rawValue),
            activityType: .highIntensityIntervalTraining,
            displayName: "HIIT",
            color: Color(red: 0.94, green: 0.27, blue: 0.27),
            symbol: "bolt.heart.fill"
        ),
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.flexibility.rawValue),
            activityType: .flexibility,
            displayName: "Flexibility",
            color: Color(red: 0.13, green: 0.77, blue: 0.37),
            symbol: "figure.flexibility"
        ),
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.cooldown.rawValue),
            activityType: .cooldown,
            displayName: "Cool Down",
            color: Color(red: 0.05, green: 0.65, blue: 0.91),
            symbol: "snowflake"
        ),
        WorkoutTypeInfo(
            typeID: Int(HKWorkoutActivityType.crossTraining.rawValue),
            activityType: .crossTraining,
            displayName: "Cross Training",
            color: Color(red: 0.49, green: 0.23, blue: 0.93),
            symbol: "figure.cross.training"
        ),
    ]

    /// Lookup by typeID (stored in Exercise.appleWorkoutType)
    static let typeMap: [Int: WorkoutTypeInfo] = {
        Dictionary(uniqueKeysWithValues: allTypes.map { ($0.typeID, $0) })
    }()

    static func info(for typeID: Int) -> WorkoutTypeInfo? {
        typeMap[typeID]
    }

    /// All typeIDs that map to a given HKWorkoutActivityType (for HealthKit grouping)
    static func typeIDs(for activityType: HKWorkoutActivityType) -> [Int] {
        allTypes.filter { $0.activityType == activityType }.map(\.typeID)
    }

    /// Unique HKWorkoutActivityTypes across all entries (for HealthKit queries)
    static var uniqueActivityTypes: [HKWorkoutActivityType] {
        var seen = Set<UInt>()
        return allTypes.compactMap { info in
            if seen.insert(info.activityType.rawValue).inserted {
                return info.activityType
            }
            return nil
        }
    }
}
