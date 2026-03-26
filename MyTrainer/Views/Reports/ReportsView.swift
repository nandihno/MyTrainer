import SwiftUI
import HealthKit
import Charts

struct ReportsView: View {
    @State private var healthKitManager = HealthKitManager()
    @State private var todayData: DayReportData?
    @State private var lastWeekData: DayReportData?
    @State private var isLoading = true
    @State private var authDenied = false

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }

    private var lastWeekDayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: healthKitManager.sameDayLastWeek())
    }

    var body: some View {
        NavigationStack {
            Group {
                if authDenied {
                    authDeniedView
                } else if isLoading {
                    ProgressView("Loading health data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    reportContent
                }
            }
            .background(Color(.appBackground))
            .navigationTitle("Reports")
            .task {
                do {
                    try await healthKitManager.requestAuthorization()
                } catch {
                    authDenied = true
                    return
                }
                await loadData()
            }
        }
    }

    // MARK: - Main Content

    private var reportContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                dateHeader

                // Section 1: Activity Charts
                activitySection

                // Section 2: Today's Totals
                summarySection

                // Section 3: Heart Rate Detail
                heartRateSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        VStack(spacing: 2) {
            Text(todayLabel)
                .font(.subheadline.bold())
            Text("vs \(lastWeekDayLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        VStack(spacing: 16) {
            sectionHeader(title: "Activity", icon: "flame.fill")

            // Exercise Amount Chart — cyan
            chartCard(title: "Exercise", todayColor: .cyan, lastWeekColor: .cyan.opacity(0.3)) {
                hourlyBarChart(
                    todayEntries: todayData?.hourlyExerciseMinutes ?? [],
                    lastWeekEntries: lastWeekData?.hourlyExerciseMinutes ?? [],
                    unit: "min",
                    todayColor: .cyan,
                    lastWeekColor: .cyan.opacity(0.3)
                )
            }

            // Calories Chart — yellow
            chartCard(title: "Active Calories", todayColor: .yellow, lastWeekColor: .yellow.opacity(0.3)) {
                hourlyBarChart(
                    todayEntries: todayData?.hourlyCalories ?? [],
                    lastWeekEntries: lastWeekData?.hourlyCalories ?? [],
                    unit: "kcal",
                    todayColor: .yellow,
                    lastWeekColor: .yellow.opacity(0.3)
                )
            }

            // Steps Chart — orange
            chartCard(title: "Steps", todayColor: .orange, lastWeekColor: .orange.opacity(0.3)) {
                hourlyBarChart(
                    todayEntries: todayData?.hourlySteps ?? [],
                    lastWeekEntries: lastWeekData?.hourlySteps ?? [],
                    unit: "steps",
                    todayColor: .orange,
                    lastWeekColor: .orange.opacity(0.3)
                )
            }

            // Workout Heart Rate Avg
            workoutHeartRateCard
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(spacing: 12) {
            sectionHeader(title: "Today's Summary", icon: "chart.bar.fill")

            HStack(spacing: 12) {
                summaryTile(
                    title: "Distance",
                    icon: "figure.walk.motion",
                    todayValue: todayData?.totalDistanceKm ?? 0,
                    lastWeekValue: lastWeekData?.totalDistanceKm ?? 0,
                    formatter: { String(format: "%.1f km", $0) }
                )

                summaryTile(
                    title: "Core",
                    icon: "figure.core.training",
                    todayValue: todayData?.coreTrainingMinutes ?? 0,
                    lastWeekValue: lastWeekData?.coreTrainingMinutes ?? 0,
                    formatter: { "\(Int($0)) min" }
                )

                summaryTile(
                    title: "Strength",
                    icon: "dumbbell.fill",
                    todayValue: todayData?.strengthTrainingMinutes ?? 0,
                    lastWeekValue: lastWeekData?.strengthTrainingMinutes ?? 0,
                    formatter: { "\(Int($0)) min" }
                )
            }
        }
    }

    // MARK: - Heart Rate Section (Apple Health style, today only)

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Heart Rate")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                Text("Today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            // Big BPM
            let stats = todayData?.heartRateStats ?? HeartRateStats(average: nil, lowest: nil, highest: nil)
            if let avg = stats.average {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(avg))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("BPM")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)
            } else {
                Text("--")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }

            // Min / Avg / Max pills
            HStack(spacing: 10) {
                hrPill(label: "Min", value: stats.lowest, color: .blue)
                hrPill(label: "Avg", value: stats.average, color: .orange)
                hrPill(label: "Max", value: stats.highest, color: .red)
            }
            .padding(.bottom, 16)

            // Line graph
            let todayPoints = todayData?.heartRateTimeline ?? []
            if todayPoints.isEmpty {
                Text("No heart rate data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                heartRateLineGraph(points: todayPoints)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func hrPill(label: String, value: Double?, color: Color) -> some View {
        VStack(spacing: 4) {
            if let val = value {
                Text("\(Int(val))")
                    .font(.title2.bold())
                    .foregroundStyle(color)
            } else {
                Text("--")
                    .font(.title2.bold())
                    .foregroundStyle(color.opacity(0.5))
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.12))
        )
    }

    // MARK: - Reusable Components

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
            Spacer()
        }
        .padding(.top, 4)
    }

    private func chartCard<Content: View>(title: String, todayColor: Color, lastWeekColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                HStack(spacing: 12) {
                    legendDot(label: "Today", color: todayColor)
                    legendDot(label: "Last week", color: lastWeekColor)
                }
            }

            content()
        }
        .padding(16)
        .background(cardBackground)
    }

    private func legendDot(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Hourly Bar Chart

    private func hourlyBarChart(todayEntries: [HourlyEntry], lastWeekEntries: [HourlyEntry], unit: String, todayColor: Color, lastWeekColor: Color) -> some View {
        let combined = buildHourlyChartData(today: todayEntries, lastWeek: lastWeekEntries)

        return Chart(combined) { item in
            BarMark(
                x: .value("Hour", item.sortOrder),
                y: .value(unit, item.value)
            )
            .foregroundStyle(item.series == "Today" ? todayColor : lastWeekColor)
            .position(by: .value("Series", item.series))
            .cornerRadius(3)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.2))
            }
        }
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: 21, by: 3))) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(hourStringFull(hour))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 160)
    }

    // MARK: - Workout Heart Rate Card

    private var workoutHeartRateCard: some View {
        let todayHR = todayData?.workoutHeartRateAvg
        let lastWeekHR = lastWeekData?.workoutHeartRateAvg

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Avg HR During Workouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    if let hr = todayHR {
                        Text("\(Int(hr))")
                            .font(.title.bold())
                        Text("bpm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("--")
                            .font(.title.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Last week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let prevHR = lastWeekHR {
                    HStack(spacing: 4) {
                        Text("\(Int(prevHR))")
                            .font(.headline)
                        Text("bpm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let currentHR = todayHR {
                        changeIndicator(current: currentHR, previous: prevHR)
                    }
                } else {
                    Text("--")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Summary Tile

    private func summaryTile(title: String, icon: String, todayValue: Double, lastWeekValue: Double, formatter: (Double) -> String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(formatter(todayValue))
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Divider()
                .frame(width: 40)

            VStack(spacing: 2) {
                Text(formatter(lastWeekValue))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                changeIndicator(current: todayValue, previous: lastWeekValue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(cardBackground)
    }

    // MARK: - Heart Rate Line Graph (today only)

    private func heartRateLineGraph(points: [HeartRatePoint]) -> some View {
        let dayStart = Calendar.current.startOfDay(for: Date())

        let chartPoints = points.map { point in
            HRChartPoint(
                minutesSinceMidnight: point.timestamp.timeIntervalSince(dayStart) / 60.0,
                bpm: point.bpm
            )
        }

        return Chart(chartPoints) { point in
            LineMark(
                x: .value("Time", point.minutesSinceMidnight),
                y: .value("BPM", point.bpm)
            )
            .foregroundStyle(Color.red)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Time", point.minutesSinceMidnight),
                y: .value("BPM", point.bpm)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.red.opacity(0.2), Color.red.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
            }
        }
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0.0, through: 1260.0, by: 180.0))) { value in
                AxisValueLabel {
                    if let mins = value.as(Double.self) {
                        let hour = Int(mins) / 60
                        Text(hourStringFull(hour))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
            }
        }
        .frame(height: 160)
    }

    // MARK: - Change Indicator

    @ViewBuilder
    private func changeIndicator(current: Double, previous: Double) -> some View {
        if let change = healthKitManager.percentageChange(current: current, previous: previous) {
            HStack(spacing: 2) {
                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text("\(Int(abs(change)))%")
                    .font(.caption2.bold())
            }
            .foregroundStyle(change >= 0 ? .green : .red)
        } else if previous == 0 && current > 0 {
            Text("New")
                .font(.caption2.bold())
                .foregroundStyle(.green)
        }
    }

    // MARK: - Styling

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.cardBackground))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
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

    // MARK: - Data Helpers

    private func loadData() async {
        isLoading = true
        async let today = healthKitManager.fetchDayReport(for: Date())
        async let lastWeek = healthKitManager.fetchDayReport(for: healthKitManager.sameDayLastWeek())
        todayData = await today
        lastWeekData = await lastWeek
        isLoading = false
    }

    /// Short format for x-axis: "12 am", "3 am", "6 am", "9 am", "12 pm", "3 pm", "6 pm", "9 pm"
    private func hourStringFull(_ hour: Int) -> String {
        if hour == 0 { return "12 am" }
        if hour < 12 { return "\(hour) am" }
        if hour == 12 { return "12 pm" }
        return "\(hour - 12) pm"
    }

    private func buildHourlyChartData(today: [HourlyEntry], lastWeek: [HourlyEntry]) -> [HourlyChartItem] {
        var items: [HourlyChartItem] = []
        guard !today.isEmpty || !lastWeek.isEmpty else { return items }

        let maxHour = max(
            today.map(\.hour).max() ?? 0,
            lastWeek.map(\.hour).max() ?? 0
        )

        let todayMap = Dictionary(uniqueKeysWithValues: today.map { ($0.hour, $0.value) })
        let lastWeekMap = Dictionary(uniqueKeysWithValues: lastWeek.map { ($0.hour, $0.value) })

        for h in 0...maxHour {
            items.append(HourlyChartItem(sortOrder: h, value: todayMap[h] ?? 0, series: "Today"))
            items.append(HourlyChartItem(sortOrder: h, value: lastWeekMap[h] ?? 0, series: "Last week"))
        }
        return items
    }
}

// MARK: - Chart Data Types

private struct HourlyChartItem: Identifiable {
    let id = UUID()
    let sortOrder: Int
    let value: Double
    let series: String
}

private struct HRChartPoint: Identifiable {
    let id = UUID()
    let minutesSinceMidnight: Double
    let bpm: Double
}
