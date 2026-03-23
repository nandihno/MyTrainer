import SwiftUI
import SwiftData
import HealthKit

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allExercises: [Exercise]
    @Query private var allScheduledExercises: [ScheduledExercise]

    @State private var healthKitManager = HealthKitManager()
    @State private var weekOffset: Int = 0
    @State private var summaries: [Int: WorkoutWeekSummary] = [:]
    @State private var previousSummaries: [Int: WorkoutWeekSummary] = [:]
    @State private var dailyBreakdowns: [Int: [DailyWorkoutEntry]] = [:]
    @State private var previousDailyBreakdowns: [Int: [DailyWorkoutEntry]] = [:]
    @State private var loadingTypes: Set<Int> = []
    @State private var authDenied = false

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    private var libraryTypeInfos: [WorkoutTypeInfo] {
        let typeIDs = Set(allExercises.map(\.appleWorkoutType))
        return typeIDs.compactMap { WorkoutTypeInfo.info(for: $0) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var weekRangeLabel: String {
        let now = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return ""
        }
        let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: weekInterval.start)!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!

        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        let startDay = formatter.string(from: weekStart)

        formatter.dateFormat = "d MMM yyyy"
        let endFormatted = formatter.string(from: weekEnd)

        return "\(startDay)\u{2013}\(endFormatted)"
    }

    /// For the current week (offset 0), compare only up to today's day.
    /// For past weeks, compare the full 7 days.
    private var comparisonDayOfWeek: Int {
        if weekOffset == 0 {
            return healthKitManager.todayDayOfWeek()
        }
        return 7 // full week for past weeks
    }

    /// Human-readable label for the comparison scope
    private var comparisonScopeLabel: String {
        if weekOffset == 0 {
            let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            let today = healthKitManager.todayDayOfWeek()
            if today == 1 {
                return "Comparing Monday vs last Monday"
            } else {
                return "Comparing Mon\u{2013}\(dayNames[today - 1]) vs same days last week"
            }
        }
        return "Comparing full week vs previous week"
    }

    var body: some View {
        NavigationStack {
            Group {
                if authDenied {
                    authDeniedView
                } else {
                    VStack(spacing: 0) {
                        weekNavigator
                        reportsList
                    }
                }
            }
            .background(Color(.appBackground))
            .navigationTitle("Reports")
            .task {
                do {
                    try await healthKitManager.requestAuthorization()
                } catch {
                    authDenied = true
                }
                await loadSummaries()
            }
        }
    }

    private var weekNavigator: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    weekOffset -= 1
                    Task { await loadSummaries() }
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }

                Spacer()

                Text(weekRangeLabel)
                    .font(.subheadline.bold())

                Spacer()

                Button {
                    weekOffset += 1
                    Task { await loadSummaries() }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .disabled(weekOffset >= 0)
            }
            .padding(.horizontal)

            Text(comparisonScopeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var reportsList: some View {
        ScrollView {
            if libraryTypeInfos.isEmpty {
                ContentUnavailableView {
                    Label("No exercises yet", systemImage: "books.vertical")
                } description: {
                    Text("Add exercises to your Library to see reports here")
                }
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(libraryTypeInfos) { typeInfo in
                        let tid = typeInfo.typeID
                        MetricCardView(
                            typeInfo: typeInfo,
                            currentSummary: summaries[tid],
                            previousSummary: previousSummaries[tid],
                            currentDaily: dailyBreakdowns[tid] ?? [],
                            previousDaily: previousDailyBreakdowns[tid] ?? [],
                            exercises: allExercises,
                            scheduledExercises: allScheduledExercises,
                            isLoading: loadingTypes.contains(tid),
                            healthKitManager: healthKitManager,
                            comparisonDayOfWeek: comparisonDayOfWeek
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
    }

    private var authDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Health Access Required")
                .font(.title2.bold())

            Text("MyTrainer needs access to your workout data to display metrics. Please enable Health permissions in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    private func loadSummaries() async {
        let infos = libraryTypeInfos
        let throughDay = comparisonDayOfWeek

        for info in infos {
            loadingTypes.insert(info.typeID)
        }

        await withTaskGroup(of: (Int, WorkoutWeekSummary, WorkoutWeekSummary, [DailyWorkoutEntry], [DailyWorkoutEntry]).self) { group in
            for info in infos {
                group.addTask {
                    async let current = healthKitManager.fetchWeekSummary(
                        typeInfo: info, weekOffset: weekOffset, throughDayOfWeek: throughDay
                    )
                    async let previous = healthKitManager.fetchWeekSummary(
                        typeInfo: info, weekOffset: weekOffset - 1, throughDayOfWeek: throughDay
                    )
                    async let daily = healthKitManager.fetchDailyBreakdown(
                        typeInfo: info, weekOffset: weekOffset
                    )
                    async let prevDaily = healthKitManager.fetchDailyBreakdown(
                        typeInfo: info, weekOffset: weekOffset - 1
                    )
                    return (info.typeID, await current, await previous, await daily, await prevDaily)
                }
            }

            for await (typeID, current, previous, daily, prevDaily) in group {
                summaries[typeID] = current
                previousSummaries[typeID] = previous
                dailyBreakdowns[typeID] = daily
                previousDailyBreakdowns[typeID] = prevDaily
                loadingTypes.remove(typeID)
            }
        }
    }
}
