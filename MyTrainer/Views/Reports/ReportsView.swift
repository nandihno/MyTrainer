import SwiftUI
import HealthKit
import Charts

// MARK: - VO2 Trend

enum VO2Trend {
    case improving(Double)   // positive delta
    case declining(Double)   // negative delta
    case stable

    var description: String {
        switch self {
        case .improving: "Improving"
        case .declining: "Declining"
        case .stable:    "Stable"
        }
    }

    var detail: String {
        switch self {
        case .improving(let d): return String(format: "+%.1f over 2 months", d)
        case .declining(let d): return String(format: "%.1f over 2 months", d)
        case .stable:           return "No significant change"
        }
    }

    var icon: String {
        switch self {
        case .improving: "arrow.up.right"
        case .declining: "arrow.down.right"
        case .stable:    "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .improving: Color.accentColor
        case .declining: .red
        case .stable:    .orange
        }
    }
}

private func computeVO2Trend(_ history: [VO2MaxPoint]) -> VO2Trend? {
    guard history.count >= 4 else { return nil }
    // Compare average of the first third vs the last third for robustness
    let slice = max(1, history.count / 3)
    let earlyAvg = history.prefix(slice).map(\.value).reduce(0, +) / Double(slice)
    let recentAvg = history.suffix(slice).map(\.value).reduce(0, +) / Double(slice)
    let delta = recentAvg - earlyAvg
    if abs(delta) < 0.5 { return .stable }
    return delta > 0 ? .improving(delta) : .declining(delta)
}

// MARK: - VO2 Rating

enum VO2Rating {
    case low, good, excellent

    var label: String {
        switch self {
        case .low: "Low"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }

    var color: Color {
        switch self {
        case .low: .red
        case .good: .orange
        case .excellent: Color.accentColor
        }
    }

    var icon: String {
        switch self {
        case .low: "arrow.down.circle.fill"
        case .good: "checkmark.circle.fill"
        case .excellent: "star.circle.fill"
        }
    }
}

private func vo2Rating(value: Double, age: Int, sex: String) -> VO2Rating {
    let isMale = sex == "Male"
    let bounds: (Double, Double)
    switch age {
    case 20..<30: bounds = isMale ? (45, 53) : (38, 44)
    case 30..<40: bounds = isMale ? (41, 50) : (35, 42)
    case 40..<50: bounds = isMale ? (37, 45) : (32, 40)
    case 50..<60: bounds = isMale ? (33, 43) : (29, 37)
    case 60..<70: bounds = isMale ? (31, 41) : (26, 33)
    default:      bounds = isMale ? (24, 32) : (18, 28)
    }
    if value >= bounds.1 { return .excellent }
    if value >= bounds.0 { return .good }
    return .low
}

// MARK: - View

struct ReportsView: View {
    @State private var healthKitManager = HealthKitManager()
    @State private var todayData: DayReportData?
    @State private var lastWeekData: DayReportData?
    @State private var isLoading = true
    @State private var authDenied = false

    // VO2 Max
    @State private var currentVO2Max: Double? = nil
    @State private var vo2History: [VO2MaxPoint] = []

    // Week to Date
    @State private var weekToDateData: WeekToDateData? = nil

    // Settings
    @AppStorage("userAge") private var userAge: Int = 30
    @AppStorage("userSex") private var userSex: String = "Male"
    @State private var showSettings = false

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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
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

                // Section 1: VO2 Max
                vo2Section

                // Section 2: Heart Rate
                heartRateSection

                // Section 3: Today's Totals
                summarySection

                // Section 4: Week to Date
                weekSummarySection

                // Section 5: Activity Charts
                activitySection
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

    // MARK: - VO2 Max Section

    private var vo2Section: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lungs.fill")
                    .foregroundStyle(Color.accentColor)
                Text("VO2 Max")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text("\(userAge) · \(userSex)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            if let vo2 = currentVO2Max {
                let rating = vo2Rating(value: vo2, age: userAge, sex: userSex)

                // Current reading + rating
                HStack(alignment: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", vo2))
                                .font(.system(size: 48, weight: .heavy, design: .rounded))
                                .foregroundStyle(rating.color)
                            Text("ml/kg/min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                        }

                        // Rating badge
                        HStack(spacing: 5) {
                            Image(systemName: rating.icon)
                            Text(rating.label)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                        }
                        .foregroundStyle(rating.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(rating.color.opacity(0.15))
                        )
                    }

                    Spacer()

                    // Age-sex context
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("For your age & sex")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        let (lo, hi) = vo2Range(age: userAge, sex: userSex)
                        Text("Good: \(Int(lo))–\(Int(hi))+")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 16)

                // 2-month trend chart
                if vo2History.count > 1 {
                    let trend = computeVO2Trend(vo2History)
                    HStack(alignment: .center, spacing: 8) {
                        Text("2-Month Trend")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let trend {
                            HStack(spacing: 4) {
                                Image(systemName: trend.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(trend.description)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(trend.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(trend.color.opacity(0.15)))

                            Text(trend.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 6)

                    vo2TrendChart(trendColor: trend?.color ?? Color.accentColor)
                } else {
                    Text("Not enough data for trend — keep wearing your Apple Watch during workouts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "lungs")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No VO2 Max data")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text("Wear your Apple Watch during outdoor runs or walks to generate readings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func vo2TrendChart(trendColor: Color) -> some View {
        let minVal = (vo2History.map(\.value).min() ?? 0) - 2
        let maxVal = (vo2History.map(\.value).max() ?? 60) + 2

        return Chart {
            ForEach(vo2History) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("VO2", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [trendColor.opacity(0.3), trendColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            ForEach(vo2History) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("VO2", point.value)
                )
                .foregroundStyle(trendColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.catmullRom)
            }
            // Highlight the most recent point
            if let latest = vo2History.last {
                PointMark(
                    x: .value("Date", latest.date),
                    y: .value("VO2", latest.value)
                )
                .foregroundStyle(trendColor)
                .symbolSize(60)
                .annotation(position: .top, spacing: 4) {
                    Text(String(format: "%.1f", latest.value))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(trendColor)
                }
            }
        }
        .chartYScale(domain: minVal...maxVal)
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0f", v))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.12))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.caption2)
            }
        }
        .frame(height: 180)
        .clipped()
    }

    /// Returns the (good lower, excellent upper) bounds for a given age/sex.
    private func vo2Range(age: Int, sex: String) -> (Double, Double) {
        let isMale = sex == "Male"
        switch age {
        case 20..<30: return isMale ? (45, 53) : (38, 44)
        case 30..<40: return isMale ? (41, 50) : (35, 42)
        case 40..<50: return isMale ? (37, 45) : (32, 40)
        case 50..<60: return isMale ? (33, 43) : (29, 37)
        case 60..<70: return isMale ? (31, 41) : (26, 33)
        default:      return isMale ? (24, 32) : (18, 28)
        }
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        VStack(spacing: 16) {
            sectionHeader(title: "Activity", icon: "flame.fill")

            // Exercise Amount Chart — cyan
            chartCard(title: "Exercise", todayColor: .cyan, lastWeekColor: .cyan.opacity(0.3)) {
                hourlyLineChart(
                    todayEntries: todayData?.hourlyExerciseMinutes ?? [],
                    lastWeekEntries: lastWeekData?.hourlyExerciseMinutes ?? [],
                    unit: "min",
                    todayColor: .cyan,
                    lastWeekColor: .cyan.opacity(0.3)
                )
            }

            // Calories Chart — yellow
            chartCard(title: "Active Calories", todayColor: .yellow, lastWeekColor: .yellow.opacity(0.3)) {
                hourlyLineChart(
                    todayEntries: todayData?.hourlyCalories ?? [],
                    lastWeekEntries: lastWeekData?.hourlyCalories ?? [],
                    unit: "kcal",
                    todayColor: .yellow,
                    lastWeekColor: .yellow.opacity(0.3)
                )
            }

            // Steps Chart — orange
            chartCard(title: "Steps", todayColor: .orange, lastWeekColor: .orange.opacity(0.3)) {
                hourlyLineChart(
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

    // MARK: - Week to Date Section

    private var weekSummarySection: some View {
        VStack(spacing: 12) {
            // Header with date range
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Week to Date")
                    .font(.title3.bold())
                Spacer()
                if let data = weekToDateData {
                    Text(weekRangeLabel(from: data.weekStart))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)

            HStack(spacing: 12) {
                weekTile(
                    title: "Distance",
                    icon: "figure.walk.motion",
                    value: weekToDateData?.totalDistanceKm ?? 0,
                    formatter: { String(format: "%.1f km", $0) }
                )
                weekTile(
                    title: "Core",
                    icon: "figure.core.training",
                    value: weekToDateData?.coreTrainingMinutes ?? 0,
                    formatter: { "\(Int($0)) min" }
                )
                weekTile(
                    title: "Strength",
                    icon: "dumbbell.fill",
                    value: weekToDateData?.strengthTrainingMinutes ?? 0,
                    formatter: { "\(Int($0)) min" }
                )
            }
        }
    }

    private func weekTile(title: String, icon: String, value: Double, formatter: (Double) -> String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(formatter(value))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("Mon – Today")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(cardBackground)
    }

    private func weekRangeLabel(from monday: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let today = Date()
        return "\(formatter.string(from: monday)) – \(formatter.string(from: today))"
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
                HeartRateChartView(points: todayPoints)
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
                    legendLine(label: "Today", color: todayColor)
                    legendLine(label: "Last week", color: lastWeekColor, dashed: true)
                }
            }

            content()
        }
        .padding(16)
        .background(cardBackground)
    }

    private func legendLine(label: String, color: Color, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color)
                            .frame(width: 5, height: 2)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 18, height: 2.5)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Hourly Line Chart

    private func hourlyLineChart(todayEntries: [HourlyEntry], lastWeekEntries: [HourlyEntry], unit: String, todayColor: Color, lastWeekColor: Color) -> some View {
        let combined = buildHourlyChartData(today: todayEntries, lastWeek: lastWeekEntries)
        let todayPoints = combined.filter { $0.series == "Today" }
        let lastWeekPoints = combined.filter { $0.series == "Last week" }

        return Chart {
            // Last week — dashed muted line with very subtle fill (drawn behind)
            ForEach(lastWeekPoints) { item in
                AreaMark(
                    x: .value("Hour", item.sortOrder),
                    y: .value(unit, item.value)
                )
                .foregroundStyle(lastWeekColor.opacity(0.10))
                .interpolationMethod(.catmullRom)
            }
            ForEach(lastWeekPoints) { item in
                LineMark(
                    x: .value("Hour", item.sortOrder),
                    y: .value(unit, item.value),
                    series: .value("Series", "Last week")
                )
                .foregroundStyle(lastWeekColor.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .interpolationMethod(.catmullRom)
            }

            // Today — bold solid line with gradient area on top
            ForEach(todayPoints) { item in
                AreaMark(
                    x: .value("Hour", item.sortOrder),
                    y: .value(unit, item.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [todayColor.opacity(0.35), todayColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            ForEach(todayPoints) { item in
                LineMark(
                    x: .value("Hour", item.sortOrder),
                    y: .value(unit, item.value),
                    series: .value("Series", "Today")
                )
                .foregroundStyle(todayColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
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
                    .foregroundStyle(Color.secondary.opacity(0.12))
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
        .frame(minHeight: 160, maxHeight: 200)
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
                .foregroundStyle(Color.accentColor)

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
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.cardBackground))
            .shadow(color: Color.accentColor.opacity(0.07), radius: 8, y: 3)
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
        async let vo2Current = healthKitManager.fetchCurrentVO2Max()
        async let vo2Trend = healthKitManager.fetchVO2MaxHistory(months: 2)
        async let weekToDate = healthKitManager.fetchWeekToDate()
        todayData = await today
        lastWeekData = await lastWeek
        currentVO2Max = await vo2Current
        vo2History = await vo2Trend
        weekToDateData = await weekToDate
        isLoading = false
        print(reportSummary)
    }

    // MARK: - Report Summary (debug + AI agent context)

    /// Structured plain-text snapshot of the user's health data for the current day.
    /// Suitable for logging and for passing as context to an AI agent.
    var reportSummary: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMM d, yyyy"
        let dateStr = dateFormatter.string(from: Date())

        // ---- VO2 Max ----
        let vo2Line: String
        if let vo2 = currentVO2Max {
            let rating = vo2Rating(value: vo2, age: userAge, sex: userSex)
            let (lo, hi) = vo2Range(age: userAge, sex: userSex)
            let trendLine: String
            if let trend = computeVO2Trend(vo2History) {
                trendLine = "\(trend.description) (\(trend.detail))"
            } else {
                trendLine = vo2History.count < 4 ? "Insufficient data for trend" : "Stable"
            }
            vo2Line = """
            VO2 Max: \(String(format: "%.1f", vo2)) ml/kg/min
            VO2 Rating: \(rating.label) (for age \(userAge), \(userSex) | Good range: \(Int(lo))–\(Int(hi))+)
            VO2 Trend: \(trendLine)
            """
        } else {
            vo2Line = "VO2 Max: No data available"
        }

        // ---- Heart Rate ----
        let hr = todayData?.heartRateStats ?? HeartRateStats(average: nil, lowest: nil, highest: nil)
        let hrAvg  = hr.average.map  { "\(Int($0)) BPM" } ?? "N/A"
        let hrMin  = hr.lowest.map   { "\(Int($0)) BPM" } ?? "N/A"
        let hrMax  = hr.highest.map  { "\(Int($0)) BPM" } ?? "N/A"
        let hrWorkout = todayData?.workoutHeartRateAvg.map { "\(Int($0)) BPM" } ?? "N/A"
        let heartRateLine = """
        Heart Rate Avg: \(hrAvg)
        Heart Rate Min: \(hrMin)
        Heart Rate Max: \(hrMax)
        Avg HR During Workouts: \(hrWorkout)
        """

        // ---- Today's Summary ----
        let distance  = todayData?.totalDistanceKm ?? 0
        let core      = todayData?.coreTrainingMinutes ?? 0
        let strength  = todayData?.strengthTrainingMinutes ?? 0
        let todaySummaryLine = """
        Distance: \(String(format: "%.1f", distance)) km
        Core Training: \(Int(core)) min
        Strength Training: \(Int(strength)) min
        """

        // ---- Activity Totals ----
        let totalExerciseMin = todayData?.hourlyExerciseMinutes.reduce(0) { $0 + $1.value } ?? 0
        let totalCalories    = todayData?.hourlyCalories.reduce(0)        { $0 + $1.value } ?? 0
        let totalSteps       = todayData?.hourlySteps.reduce(0)           { $0 + $1.value } ?? 0
        let activityLine = """
        Total Exercise Minutes: \(Int(totalExerciseMin)) min
        Active Calories: \(Int(totalCalories)) kcal
        Steps: \(Int(totalSteps))
        """

        return """
        ==========================================
        MyTrainer Daily Health Report
        Date: \(dateStr)
        User: Age \(userAge), \(userSex)
        ==========================================

        [VO2 Max]
        \(vo2Line)

        [Heart Rate]
        \(heartRateLine)

        [Today's Summary]
        \(todaySummaryLine)

        [Activity Totals]
        \(activityLine)
        ==========================================
        """
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
