import SwiftUI
import SwiftData
import HealthKit

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allExercises: [Exercise]
    @Query private var allScheduledExercises: [ScheduledExercise]

    @State private var healthKitManager = HealthKitManager()
    @State private var weekOffset: Int = 0
    @State private var summaries: [UInt: WorkoutWeekSummary] = [:]
    @State private var previousSummaries: [UInt: WorkoutWeekSummary] = [:]
    @State private var dailyBreakdowns: [UInt: [DailyWorkoutEntry]] = [:]
    @State private var previousDailyBreakdowns: [UInt: [DailyWorkoutEntry]] = [:]
    @State private var loadingTypes: Set<UInt> = []
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

    private var uniqueHKTypes: [HKWorkoutActivityType] {
        var seen = Set<UInt>()
        return libraryTypeInfos.compactMap { info in
            if seen.insert(info.activityType.rawValue).inserted {
                return info.activityType
            }
            return nil
        }
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
                        let rawValue = typeInfo.activityType.rawValue
                        MetricCardView(
                            typeInfo: typeInfo,
                            currentSummary: summaries[rawValue],
                            previousSummary: previousSummaries[rawValue],
                            currentDaily: dailyBreakdowns[rawValue] ?? [],
                            previousDaily: previousDailyBreakdowns[rawValue] ?? [],
                            exercises: allExercises,
                            scheduledExercises: allScheduledExercises,
                            isLoading: loadingTypes.contains(rawValue),
                            healthKitManager: healthKitManager
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
        for hkType in uniqueHKTypes {
            loadingTypes.insert(hkType.rawValue)
        }

        await withTaskGroup(of: (UInt, WorkoutWeekSummary, WorkoutWeekSummary, [DailyWorkoutEntry], [DailyWorkoutEntry]).self) { group in
            for hkType in uniqueHKTypes {
                group.addTask {
                    async let current = healthKitManager.fetchWeekSummary(
                        activityType: hkType, weekOffset: weekOffset
                    )
                    async let previous = healthKitManager.fetchWeekSummary(
                        activityType: hkType, weekOffset: weekOffset - 1
                    )
                    async let daily = healthKitManager.fetchDailyBreakdown(
                        activityType: hkType, weekOffset: weekOffset
                    )
                    async let prevDaily = healthKitManager.fetchDailyBreakdown(
                        activityType: hkType, weekOffset: weekOffset - 1
                    )
                    return (hkType.rawValue, await current, await previous, await daily, await prevDaily)
                }
            }

            for await (rawValue, current, previous, daily, prevDaily) in group {
                summaries[rawValue] = current
                previousSummaries[rawValue] = previous
                dailyBreakdowns[rawValue] = daily
                previousDailyBreakdowns[rawValue] = prevDaily
                loadingTypes.remove(rawValue)
            }
        }
    }
}
