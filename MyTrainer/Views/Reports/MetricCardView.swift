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
                dailyChart
                weekComparisonChart
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

            changeLabel
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
    private var changeLabel: some View {
        if let change = healthKitManager.percentageChange(
            current: currentMinutes,
            previous: previousMinutes
        ) {
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
        } else if previousMinutes == 0 {
            Text("No prev. data")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

    // MARK: - Week Comparison

    @ViewBuilder
    private var weekComparisonChart: some View {
        let thisWeekTotal = currentMinutes
        let lastWeekTotal = previousMinutes

        if thisWeekTotal > 0 || lastWeekTotal > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Week Comparison")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let maxVal = max(thisWeekTotal, lastWeekTotal, 1)

                VStack(spacing: 8) {
                    comparisonBar(
                        label: "This week",
                        value: thisWeekTotal,
                        maxValue: maxVal,
                        color: typeInfo.color
                    )
                    comparisonBar(
                        label: "Last week",
                        value: lastWeekTotal,
                        maxValue: maxVal,
                        color: typeInfo.color.opacity(0.35)
                    )
                }
            }
        }
    }

    private func comparisonBar(label: String, value: Double, maxValue: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: max(value > 0 ? 4 : 0, geo.size.width * (value / maxValue)))
            }
            .frame(height: 16)

            Text("\(Int(value))m")
                .font(.caption2.bold())
                .foregroundStyle(.primary)
                .frame(width: 36, alignment: .leading)
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
}
