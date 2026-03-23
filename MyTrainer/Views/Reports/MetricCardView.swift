import SwiftUI
import Charts
import HealthKit

struct MetricCardView: View {
    let typeInfo: WorkoutTypeInfo
    let currentSummary: WorkoutWeekSummary?
    let previousSummary: WorkoutWeekSummary?
    let currentDaily: [DailyWorkoutEntry]
    let previousDaily: [DailyWorkoutEntry]
    let exercises: [Exercise]
    let scheduledExercises: [ScheduledExercise]
    let isLoading: Bool
    let healthKitManager: HealthKitManager
    let comparisonDayOfWeek: Int  // 1=Mon..7=Sun

    private var currentMinutes: Double {
        (currentSummary?.totalDuration ?? 0) / 60
    }

    private var previousMinutes: Double {
        (previousSummary?.totalDuration ?? 0) / 60
    }

    private var hasCurrentData: Bool {
        guard let summary = currentSummary else { return false }
        return summary.workoutCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if hasCurrentData {
                metricsRow
                heartRateRow
                dailyChart
                dayByDayComparisonChart
                exerciseBreakdown
            } else {
                Label("No Health data for this week", systemImage: "heart.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.cardBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: typeInfo.symbol)
                    .foregroundStyle(typeInfo.color)
                Text(typeInfo.displayName)
                    .font(.headline)
                    .foregroundStyle(typeInfo.color)
            }

            Spacer()

            if let summary = currentSummary, summary.workoutCount > 0 {
                Text("\(summary.workoutCount) workout\(summary.workoutCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Metrics

    private var metricsRow: some View {
        HStack(spacing: 16) {
            metricPill(
                value: "\(Int(currentMinutes))",
                unit: "min",
                icon: "clock"
            )
            metricPill(
                value: "~\(Int(currentSummary?.totalCalories ?? 0))",
                unit: "kcal",
                icon: "flame"
            )

            Spacer()

            durationChangeLabel
        }
    }

    private func metricPill(value: String, unit: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(typeInfo.color)
            Text(value)
                .font(.title3.bold())
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var durationChangeLabel: some View {
        if let change = healthKitManager.percentageChange(
            current: currentMinutes,
            previous: previousMinutes
        ) {
            changeBadge(change: change)
        } else if previousMinutes == 0 {
            Text("No prev. data")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Heart Rate

    @ViewBuilder
    private var heartRateRow: some View {
        let currentHR = currentSummary?.averageHeartRate
        let previousHR = previousSummary?.averageHeartRate

        if let hr = currentHR {
            HStack(spacing: 16) {
                // Current HR
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text("\(Int(hr))")
                        .font(.title3.bold())
                    Text("avg bpm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // HR change vs last week same period
                if let prevHR = previousHR {
                    if let change = healthKitManager.percentageChange(
                        current: hr,
                        previous: prevHR
                    ) {
                        VStack(alignment: .trailing, spacing: 2) {
                            changeBadge(change: change)
                            Text("was \(Int(prevHR)) bpm")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No prev. HR")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(0.06))
            )
        }
    }

    // MARK: - Shared Change Badge

    private func changeBadge(change: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.bold())
            Text("\(Int(abs(change)))%")
                .font(.caption.bold())
        }
        .foregroundStyle(change >= 0 ? .green : .red)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(change >= 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        )
    }

    // MARK: - Daily Bar Chart

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daily Duration")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(currentDaily) { entry in
                BarMark(
                    x: .value("Day", entry.dayAbbreviation),
                    y: .value("Minutes", entry.durationMinutes)
                )
                .foregroundStyle(
                    entry.durationMinutes > 0
                        ? typeInfo.color
                        : typeInfo.color.opacity(0.15)
                )
                .cornerRadius(4)
            }
            .chartYAxisLabel("min")
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))")
                                .font(.caption2)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let day = value.as(String.self) {
                            Text(day)
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 140)
        }
    }

    // MARK: - Day-by-Day Comparison Chart

    @ViewBuilder
    private var dayByDayComparisonChart: some View {
        // Only show days up to the comparison scope
        let daysToShow = comparisonDayOfWeek
        let currentSlice = Array(currentDaily.prefix(daysToShow))
        let previousSlice = Array(previousDaily.prefix(daysToShow))

        if !currentSlice.isEmpty || !previousSlice.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("vs Last Week (same days)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let chartData = buildComparisonData(
                    current: currentSlice,
                    previous: previousSlice
                )

                Chart(chartData) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Minutes", item.minutes),
                        stacking: .unstacked
                    )
                    .foregroundStyle(by: .value("Week", item.week))
                    .cornerRadius(4)
                    .position(by: .value("Week", item.week))
                }
                .chartForegroundStyleScale([
                    "This week": typeInfo.color,
                    "Last week": typeInfo.color.opacity(0.3)
                ])
                .chartLegend(position: .top, alignment: .trailing) {
                    HStack(spacing: 12) {
                        legendDot(label: "This week", color: typeInfo.color)
                        legendDot(label: "Last week", color: typeInfo.color.opacity(0.3))
                    }
                    .font(.caption2)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))")
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let day = value.as(String.self) {
                                Text(day)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 140)
            }
        }
    }

    private func legendDot(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Exercise Breakdown

    @ViewBuilder
    private var exerciseBreakdown: some View {
        if !relevantExercises.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(relevantExercises) { exercise in
                    exerciseBreakdownRow(exercise)
                }
            }
        }
    }

    private var relevantExercises: [Exercise] {
        exercises.filter {
            $0.appleWorkoutType == typeInfo.typeID
        }
    }

    private func exerciseBreakdownRow(_ exercise: Exercise) -> some View {
        let scheduled = scheduledExercises.first {
            $0.exercise?.id == exercise.id
        }
        let sets = scheduled?.sets ?? exercise.defaultSets
        let detail: String
        if exercise.isTimeBased {
            let dur = scheduled?.durationSeconds ?? exercise.defaultDurationSeconds
            detail = "\(sets) sets \u{00D7} \(formatDuration(dur))"
        } else {
            let reps = scheduled?.reps ?? exercise.defaultReps
            detail = "\(sets) sets \u{00D7} \(reps) reps"
        }

        return HStack(spacing: 4) {
            Text("\u{2022}")
                .foregroundStyle(typeInfo.color)
            Text("\(exercise.name) \u{2014} \(detail)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let m = seconds / 60
            let s = seconds % 60
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        }
        return "\(seconds)s"
    }

    // MARK: - Comparison Data Builder

    private struct ComparisonEntry: Identifiable {
        let id = UUID()
        let day: String
        let week: String
        let minutes: Double
    }

    private func buildComparisonData(
        current: [DailyWorkoutEntry],
        previous: [DailyWorkoutEntry]
    ) -> [ComparisonEntry] {
        var data: [ComparisonEntry] = []

        for entry in current {
            data.append(ComparisonEntry(
                day: entry.dayAbbreviation,
                week: "This week",
                minutes: entry.durationMinutes
            ))
        }

        for entry in previous {
            data.append(ComparisonEntry(
                day: entry.dayAbbreviation,
                week: "Last week",
                minutes: entry.durationMinutes
            ))
        }

        return data
    }
}
