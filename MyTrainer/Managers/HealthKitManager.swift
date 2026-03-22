import Foundation
import HealthKit
import Observation

struct WorkoutWeekSummary: Sendable {
    let typeID: Int
    let activityType: HKWorkoutActivityType
    let totalDuration: TimeInterval
    let totalCalories: Double
    let workoutCount: Int
    let weekStartDate: Date
}

struct DailyWorkoutEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let dayAbbreviation: String
    let durationMinutes: Double
    let calories: Double
    let workoutCount: Int
}

@Observable
@MainActor
final class HealthKitManager {
    private let healthStore = HKHealthStore()
    var authorizationDenied = false

    private var mondayCalendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchWorkouts(
        activityType: HKWorkoutActivityType,
        from startDate: Date,
        to endDate: Date,
        isIndoor: Bool? = nil
    ) async -> [HKWorkout] {
        let typePredicate = HKQuery.predicateForWorkouts(with: activityType)
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [typePredicate, datePredicate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let allWorkouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: compound,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }

        // Filter by indoor/outdoor if specified
        guard let isIndoor else { return allWorkouts }

        return allWorkouts.filter { workout in
            let indoorValue = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool
            if isIndoor {
                // Treadmill: must be explicitly marked indoor
                return indoorValue == true
            } else {
                // Outdoor: either explicitly outdoor or no metadata (default = outdoor)
                return indoorValue != true
            }
        }
    }

    func fetchWeekSummary(
        typeInfo: WorkoutTypeInfo,
        weekOffset: Int
    ) async -> WorkoutWeekSummary {
        let cal = mondayCalendar
        let now = Date()
        guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else {
            return WorkoutWeekSummary(
                typeID: typeInfo.typeID,
                activityType: typeInfo.activityType,
                totalDuration: 0,
                totalCalories: 0,
                workoutCount: 0,
                weekStartDate: now
            )
        }

        let weekStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart)!
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!

        let workouts = await fetchWorkouts(
            activityType: typeInfo.activityType,
            from: weekStart,
            to: weekEnd,
            isIndoor: typeInfo.isIndoor
        )

        let totalDuration = workouts.reduce(0.0) { $0 + $1.duration }
        let totalCalories = workouts.reduce(0.0) { total, workout in
            let energyStats = workout.statistics(for: HKQuantityType(.activeEnergyBurned))
            let cal = energyStats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            return total + cal
        }

        return WorkoutWeekSummary(
            typeID: typeInfo.typeID,
            activityType: typeInfo.activityType,
            totalDuration: totalDuration,
            totalCalories: totalCalories,
            workoutCount: workouts.count,
            weekStartDate: weekStart
        )
    }

    func fetchDailyBreakdown(
        typeInfo: WorkoutTypeInfo,
        weekOffset: Int
    ) async -> [DailyWorkoutEntry] {
        let cal = mondayCalendar
        let now = Date()
        guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else {
            return []
        }

        let weekStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart)!
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!

        let workouts = await fetchWorkouts(
            activityType: typeInfo.activityType,
            from: weekStart,
            to: weekEnd,
            isIndoor: typeInfo.isIndoor
        )

        let dayAbbreviations = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        return (0..<7).map { dayIndex in
            let dayStart = cal.date(byAdding: .day, value: dayIndex, to: weekStart)!
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

            let dayWorkouts = workouts.filter { w in
                w.startDate >= dayStart && w.startDate < dayEnd
            }

            let duration = dayWorkouts.reduce(0.0) { $0 + $1.duration } / 60.0
            let calories = dayWorkouts.reduce(0.0) { total, workout in
                let stats = workout.statistics(for: HKQuantityType(.activeEnergyBurned))
                return total + (stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }

            return DailyWorkoutEntry(
                date: dayStart,
                dayAbbreviation: dayAbbreviations[dayIndex],
                durationMinutes: duration,
                calories: calories,
                workoutCount: dayWorkouts.count
            )
        }
    }

    func percentageChange(current: Double, previous: Double) -> Double? {
        guard previous != 0 else { return nil }
        return ((current - previous) / previous) * 100
    }
}
