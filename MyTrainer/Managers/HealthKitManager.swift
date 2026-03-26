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
    let averageHeartRate: Double?       // bpm, nil if no data
    let throughDayOfWeek: Int           // 1=Mon..7=Sun — how many days are included
}

struct DailyWorkoutEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let dayAbbreviation: String
    let durationMinutes: Double
    let calories: Double
    let workoutCount: Int
    let averageHeartRate: Double?       // bpm for that day
}

// MARK: - New Report Data Structures

struct HourlyEntry: Identifiable, Sendable {
    let id = UUID()
    let hour: Int              // 0-23
    let value: Double          // minutes or calories depending on context
}

struct HeartRatePoint: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let bpm: Double
}

struct HeartRateStats: Sendable {
    let average: Double?
    let lowest: Double?
    let highest: Double?
}

struct DayReportData: Sendable {
    let date: Date
    let hourlyExerciseMinutes: [HourlyEntry]
    let hourlyCalories: [HourlyEntry]
    let hourlySteps: [HourlyEntry]
    let workoutHeartRateAvg: Double?
    let totalDistanceKm: Double
    let coreTrainingMinutes: Double
    let strengthTrainingMinutes: Double
    let heartRateTimeline: [HeartRatePoint]
    let heartRateStats: HeartRateStats
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
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.stepCount),
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
                return indoorValue == true
            } else {
                return indoorValue != true
            }
        }
    }

    // MARK: - Heart Rate

    /// Fetch average heart rate across all samples that fall within a workout's time range.
    func fetchAverageHeartRate(for workouts: [HKWorkout]) async -> Double? {
        guard !workouts.isEmpty else { return nil }

        var allRates: [Double] = []

        for workout in workouts {
            let rates = await fetchHeartRateSamples(
                from: workout.startDate,
                to: workout.endDate
            )
            allRates.append(contentsOf: rates)
        }

        guard !allRates.isEmpty else { return nil }
        return allRates.reduce(0, +) / Double(allRates.count)
    }

    private func fetchHeartRateSamples(from start: Date, to end: Date) async -> [Double] {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let rates = (samples as? [HKQuantitySample])?.map {
                    $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                } ?? []
                continuation.resume(returning: rates)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Week Summary (day-scoped comparison)

    /// Fetches a summary for the given week, but only up through a specific day-of-week.
    /// `throughDayOfWeek`: 1=Mon..7=Sun. For current week this is today's day;
    /// for previous week we use the same value so comparisons are apples-to-apples.
    func fetchWeekSummary(
        typeInfo: WorkoutTypeInfo,
        weekOffset: Int,
        throughDayOfWeek: Int = 7
    ) async -> WorkoutWeekSummary {
        let cal = mondayCalendar
        let now = Date()
        guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else {
            return emptySummary(typeInfo: typeInfo, date: now, throughDay: throughDayOfWeek)
        }

        let weekStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart)!
        // Clamp end to throughDayOfWeek (e.g. if throughDay=1 Mon, only include Mon)
        let clampedEnd = cal.date(byAdding: .day, value: throughDayOfWeek, to: weekStart)!

        let workouts = await fetchWorkouts(
            activityType: typeInfo.activityType,
            from: weekStart,
            to: clampedEnd,
            isIndoor: typeInfo.isIndoor
        )

        let totalDuration = workouts.reduce(0.0) { $0 + $1.duration }
        let totalCalories = workouts.reduce(0.0) { total, workout in
            let energyStats = workout.statistics(for: HKQuantityType(.activeEnergyBurned))
            let cal = energyStats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            return total + cal
        }
        let avgHR = await fetchAverageHeartRate(for: workouts)

        return WorkoutWeekSummary(
            typeID: typeInfo.typeID,
            activityType: typeInfo.activityType,
            totalDuration: totalDuration,
            totalCalories: totalCalories,
            workoutCount: workouts.count,
            weekStartDate: weekStart,
            averageHeartRate: avgHR,
            throughDayOfWeek: throughDayOfWeek
        )
    }

    // MARK: - Daily Breakdown

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

        var entries: [DailyWorkoutEntry] = []
        for dayIndex in 0..<7 {
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
            let avgHR = await fetchAverageHeartRate(for: dayWorkouts)

            entries.append(DailyWorkoutEntry(
                date: dayStart,
                dayAbbreviation: dayAbbreviations[dayIndex],
                durationMinutes: duration,
                calories: calories,
                workoutCount: dayWorkouts.count,
                averageHeartRate: avgHR
            ))
        }

        return entries
    }

    // MARK: - Day Report (Today vs Same Day Last Week)

    func fetchDayReport(for date: Date) async -> DayReportData {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let now = Date()
        let isToday = cal.isDateInToday(date)
        let dayEnd = isToday ? now : cal.date(byAdding: .day, value: 1, to: dayStart)!

        async let hourlyEx = fetchHourlyWorkoutDuration(from: dayStart, to: dayEnd)
        async let hourlyCal = fetchHourlyCalories(from: dayStart, to: dayEnd)
        async let hourlySteps = fetchHourlySteps(from: dayStart, to: dayEnd)
        async let workoutHR = fetchWorkoutHeartRateAvg(from: dayStart, to: dayEnd)
        async let distance = fetchTotalDistance(from: dayStart, to: dayEnd)
        async let coreMin = fetchWorkoutMinutes(from: dayStart, to: dayEnd, activityTypes: [.coreTraining])
        async let strengthMin = fetchWorkoutMinutes(from: dayStart, to: dayEnd, activityTypes: [.traditionalStrengthTraining, .functionalStrengthTraining])
        async let hrTimeline = fetchHeartRateTimeline(from: dayStart, to: dayEnd)
        async let hrStats = fetchHeartRateStats(from: dayStart, to: dayEnd)

        return await DayReportData(
            date: date,
            hourlyExerciseMinutes: hourlyEx,
            hourlyCalories: hourlyCal,
            hourlySteps: hourlySteps,
            workoutHeartRateAvg: workoutHR,
            totalDistanceKm: distance,
            coreTrainingMinutes: coreMin,
            strengthTrainingMinutes: strengthMin,
            heartRateTimeline: hrTimeline,
            heartRateStats: hrStats
        )
    }

    /// Fetches workout duration bucketed by hour
    private func fetchHourlyWorkoutDuration(from start: Date, to end: Date) async -> [HourlyEntry] {
        let cal = Calendar.current
        let workouts = await fetchAllWorkouts(from: start, to: end)
        let currentHour = cal.component(.hour, from: end)
        let isToday = cal.isDateInToday(start)
        let maxHour = isToday ? currentHour : 23

        var buckets = [Int: Double]()
        for workout in workouts {
            let wStart = max(workout.startDate, start)
            let wEnd = min(workout.endDate, end)
            guard wEnd > wStart else { continue }
            distributeAcrossHours(start: wStart, end: wEnd, calendar: cal, into: &buckets)
        }

        return (0...maxHour).map { hour in
            HourlyEntry(hour: hour, value: buckets[hour] ?? 0)
        }
    }

    /// Fetches active calories bucketed by hour using statistics collection
    private func fetchHourlyCalories(from start: Date, to end: Date) async -> [HourlyEntry] {
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: end)
        let isToday = cal.isDateInToday(start)
        let maxHour = isToday ? currentHour : 23

        let calorieType = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let hourlyData: [Int: Double] = await withCheckedContinuation { continuation in
            let interval = DateComponents(hour: 1)
            let query = HKStatisticsCollectionQuery(
                quantityType: calorieType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var buckets = [Int: Double]()
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let hour = cal.component(.hour, from: stats.startDate)
                    let cals = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    buckets[hour] = cals
                }
                continuation.resume(returning: buckets)
            }
            healthStore.execute(query)
        }

        return (0...maxHour).map { hour in
            HourlyEntry(hour: hour, value: hourlyData[hour] ?? 0)
        }
    }

    /// Fetches step count bucketed by hour
    private func fetchHourlySteps(from start: Date, to end: Date) async -> [HourlyEntry] {
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: end)
        let isToday = cal.isDateInToday(start)
        let maxHour = isToday ? currentHour : 23

        let stepType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let hourlyData: [Int: Double] = await withCheckedContinuation { continuation in
            let interval = DateComponents(hour: 1)
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var buckets = [Int: Double]()
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let hour = cal.component(.hour, from: stats.startDate)
                    let steps = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    buckets[hour] = steps
                }
                continuation.resume(returning: buckets)
            }
            healthStore.execute(query)
        }

        return (0...maxHour).map { hour in
            HourlyEntry(hour: hour, value: hourlyData[hour] ?? 0)
        }
    }

    /// Average heart rate during workouts only for a given day
    private func fetchWorkoutHeartRateAvg(from start: Date, to end: Date) async -> Double? {
        let workouts = await fetchAllWorkouts(from: start, to: end)
        return await fetchAverageHeartRate(for: workouts)
    }

    /// Total walking + running distance (indoor + outdoor) in km
    private func fetchTotalDistance(from start: Date, to end: Date) async -> Double {
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: distanceType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                let km = stats?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0
                continuation.resume(returning: km)
            }
            healthStore.execute(query)
        }
    }

    /// Total workout minutes for specified activity types
    private func fetchWorkoutMinutes(from start: Date, to end: Date, activityTypes: [HKWorkoutActivityType]) async -> Double {
        var total: TimeInterval = 0
        for type in activityTypes {
            let workouts = await fetchWorkouts(activityType: type, from: start, to: end)
            total += workouts.reduce(0) { $0 + $1.duration }
        }
        return total / 60.0
    }

    /// Fetches all heart rate samples for a time range (for line graph)
    func fetchHeartRateTimeline(from start: Date, to end: Date) async -> [HeartRatePoint] {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let points = (samples as? [HKQuantitySample])?.map { sample in
                    HeartRatePoint(
                        timestamp: sample.startDate,
                        bpm: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    )
                } ?? []
                continuation.resume(returning: points)
            }
            healthStore.execute(query)
        }
    }

    /// Heart rate stats (avg, min, max) for a time range
    private func fetchHeartRateStats(from start: Date, to end: Date) async -> HeartRateStats {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let allRates: [Double] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let rates = (samples as? [HKQuantitySample])?.map {
                    $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                } ?? []
                continuation.resume(returning: rates)
            }
            healthStore.execute(query)
        }

        guard !allRates.isEmpty else {
            return HeartRateStats(average: nil, lowest: nil, highest: nil)
        }
        let avg = allRates.reduce(0, +) / Double(allRates.count)
        return HeartRateStats(average: avg, lowest: allRates.min(), highest: allRates.max())
    }

    /// Fetches all workouts regardless of type for a date range
    private func fetchAllWorkouts(from start: Date, to end: Date) async -> [HKWorkout] {
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: datePredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    /// Distributes workout duration across hourly buckets in minutes
    private func distributeAcrossHours(start: Date, end: Date, calendar: Calendar, into buckets: inout [Int: Double]) {
        var cursor = start
        while cursor < end {
            let hour = calendar.component(.hour, from: cursor)
            let nextHour = calendar.date(bySettingHour: hour + 1, minute: 0, second: 0, of: cursor) ?? end
            let bucketEnd = min(nextHour, end)
            let minutes = bucketEnd.timeIntervalSince(cursor) / 60.0
            buckets[hour, default: 0] += minutes
            cursor = bucketEnd
        }
    }

    /// Returns the same day of the week from last week
    func sameDayLastWeek(from date: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -1, to: date)!
    }

    // MARK: - Helpers

    func percentageChange(current: Double, previous: Double) -> Double? {
        guard previous != 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    /// Returns the 1-based day of week (Mon=1..Sun=7) for today.
    func todayDayOfWeek() -> Int {
        let cal = mondayCalendar
        // weekday: 1=Sun..7=Sat in the standard calendar,
        // but we need Mon=1..Sun=7
        let weekday = cal.component(.weekday, from: Date())
        // Convert: Sun(1)->7, Mon(2)->1, Tue(3)->2 ... Sat(7)->6
        return weekday == 1 ? 7 : weekday - 1
    }

    private func emptySummary(typeInfo: WorkoutTypeInfo, date: Date, throughDay: Int) -> WorkoutWeekSummary {
        WorkoutWeekSummary(
            typeID: typeInfo.typeID,
            activityType: typeInfo.activityType,
            totalDuration: 0,
            totalCalories: 0,
            workoutCount: 0,
            weekStartDate: date,
            averageHeartRate: nil,
            throughDayOfWeek: throughDay
        )
    }
}
