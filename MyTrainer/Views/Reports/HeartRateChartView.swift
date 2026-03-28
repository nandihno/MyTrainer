import SwiftUI
import Charts

struct HeartRateChartEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let label: String?
    let tint: Color

    init(timestamp: Date, label: String? = nil, tint: Color = .orange) {
        self.timestamp = timestamp
        self.label = label
        self.tint = tint
    }
}

struct HeartRateChartView: View {
    struct Configuration {
        var smoothingWindow: Int = 5
        var aggregationInterval: TimeInterval = 60
        var paddingRatio: Double = 0.10
        var visibleUpperCap: Double = 190
        var minimumUpperBound: Double = 100
        var minimumVisibleSpan: Double = 24
        var lowerBoundFloor: Double = 35
    }

    private let model: HeartRateChartModel
    private let events: [HeartRateChartEvent]

    init(
        points: [HeartRatePoint],
        events: [HeartRateChartEvent] = [],
        configuration: Configuration = Configuration()
    ) {
        let model = HeartRateChartModel(points: points, configuration: configuration)
        self.model = model
        self.events = events
            .sorted { $0.timestamp < $1.timestamp }
            .filter { model.xDomain.contains($0.timestamp) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(model.zoneBands) { band in
                    RectangleMark(
                        xStart: .value("Start", model.xDomain.lowerBound),
                        xEnd: .value("End", model.xDomain.upperBound),
                        yStart: .value("Zone Start", band.range.lowerBound),
                        yEnd: .value("Zone End", band.range.upperBound)
                    )
                    .foregroundStyle(band.color)
                }

                ForEach(events) { event in
                    RuleMark(x: .value("Event", event.timestamp))
                        .foregroundStyle(event.tint.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 4]))
                        .annotation(position: .top, spacing: 6) {
                            if let label = event.label, !label.isEmpty {
                                Text(label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(event.tint)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.thinMaterial, in: Capsule())
                            }
                        }
                }

                ForEach(model.displayPoints) { point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        yStart: .value("Baseline", model.yDomain.lowerBound),
                        yEnd: .value("Heart Rate", point.displayBPM)
                    )
                    .foregroundStyle(model.fillGradient)
                    .interpolationMethod(.monotone)
                }

                ForEach(model.displayPoints) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Heart Rate", point.displayBPM)
                    )
                    .foregroundStyle(model.lineGradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                ForEach(model.clippedPeaks) { peak in
                    PointMark(
                        x: .value("Peak Time", peak.timestamp),
                        y: .value("Peak Marker", peak.markerBPM)
                    )
                    .foregroundStyle(.red)
                    .symbolSize(44)
                    .annotation(position: .top, spacing: 6) {
                        VStack(spacing: 2) {
                            Text("\(Int(peak.actualBPM)) BPM")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.red)
                            Text("Peak")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .chartXScale(domain: model.xDomain)
            .chartYScale(domain: model.yDomain)
            .chartXAxis {
                if model.isSingleDay {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                            .foregroundStyle(.secondary.opacity(0.35))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.8))
                            .foregroundStyle(.secondary.opacity(0.35))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: model.yAxisValues) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [3, 5]))
                        .foregroundStyle(.secondary.opacity(0.18))
                    AxisValueLabel {
                        if let bpm = value.as(Double.self) {
                            Text("\(Int(bpm))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.red.opacity(0.015))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .frame(height: 220)

            if let clipNote = model.clippedPeakNote {
                Text(clipNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

private struct HeartRateChartModel {
    let displayPoints: [DisplayPoint]
    let clippedPeaks: [ClippedPeak]
    let zoneBands: [ZoneBand]
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    let yAxisValues: [Double]
    let isSingleDay: Bool
    let clipThreshold: Double
    let lineGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.36, blue: 0.43), Color.red],
        startPoint: .leading,
        endPoint: .trailing
    )
    let fillGradient = LinearGradient(
        colors: [
            Color.red.opacity(0.30),
            Color(red: 1.0, green: 0.56, blue: 0.62).opacity(0.12),
            .clear
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var clippedPeakNote: String? {
        guard !clippedPeaks.isEmpty else { return nil }
        return "Peaks above \(Int(clipThreshold)) BPM are capped in the plot and labeled with the true value."
    }

    init(points: [HeartRatePoint], configuration: HeartRateChartView.Configuration) {
        let sortedPoints = Self.coalescedPoints(
            from: points.sorted { $0.timestamp < $1.timestamp },
            aggregationInterval: configuration.aggregationInterval
        )
        let smoothedValues = Self.movingAverage(
            values: sortedPoints.map(\.bpm),
            window: Self.normalizedWindow(configuration.smoothingWindow)
        )

        let rawValues = sortedPoints.map(\.bpm)
        let rawMin = rawValues.min() ?? configuration.lowerBoundFloor
        let rawMax = rawValues.max() ?? configuration.minimumUpperBound
        let robustUpper = Self.robustUpperBound(for: rawValues)
        let nonOutlierMax = zip(rawValues, smoothedValues)
            .filter { $0.0 <= robustUpper }
            .map { max($0.0, $0.1) }
            .max() ?? rawMax

        let smoothedMin = smoothedValues.min() ?? rawMin
        let lowerCandidate = min(rawMin, smoothedMin)
        let upperCandidate = max(
            nonOutlierMax,
            lowerCandidate + configuration.minimumVisibleSpan,
            configuration.minimumUpperBound
        )

        let baseSpan = max(upperCandidate - lowerCandidate, configuration.minimumVisibleSpan)
        let padding = max(baseSpan * configuration.paddingRatio, 4)
        let lowerBound = Self.roundDown(max(configuration.lowerBoundFloor, lowerCandidate - padding), step: 5)
        let preferredUpperBound = max(
            upperCandidate + padding,
            rawMax + min(padding * 0.35, 6)
        )
        let cappedUpper = min(configuration.visibleUpperCap, preferredUpperBound)
        let upperBound = max(
            Self.roundUp(cappedUpper, step: 5),
            lowerBound + configuration.minimumVisibleSpan
        )
        self.clipThreshold = upperBound

        let markerBPM = max(lowerBound, upperBound - max((upperBound - lowerBound) * 0.05, 3))
        self.displayPoints = zip(sortedPoints, smoothedValues).map { point, smoothed in
            DisplayPoint(
                timestamp: point.timestamp,
                rawBPM: point.bpm,
                smoothedBPM: smoothed,
                displayBPM: min(smoothed, upperBound)
            )
        }
        self.clippedPeaks = Self.extractClippedPeaks(from: displayPoints, upperBound: upperBound, markerBPM: markerBPM)
        self.yDomain = lowerBound...upperBound
        self.yAxisValues = Self.axisValues(for: yDomain)
        self.zoneBands = HeartRateZone.allCases.compactMap { zone in
            let lower = max(zone.range.lowerBound, lowerBound)
            let upper = min(zone.range.upperBound, upperBound)
            guard lower < upper else { return nil }
            return ZoneBand(range: lower...upper, color: zone.backgroundColor)
        }

        let calendar = Calendar.autoupdatingCurrent
        if let first = sortedPoints.first?.timestamp, let last = sortedPoints.last?.timestamp {
            self.isSingleDay = sortedPoints.allSatisfy { calendar.isDate($0.timestamp, inSameDayAs: first) }
            if isSingleDay {
                let start = calendar.startOfDay(for: first)
                let minimumEnd = calendar.date(byAdding: .hour, value: 1, to: start) ?? last
                let end = max(last, minimumEnd)
                self.xDomain = start...end
            } else {
                let minimumEnd = calendar.date(byAdding: .minute, value: 30, to: first) ?? last
                self.xDomain = first...max(last, minimumEnd)
            }
        } else {
            let now = Date()
            self.isSingleDay = true
            self.xDomain = now...now.addingTimeInterval(3600)
        }
    }

    private static func normalizedWindow(_ window: Int) -> Int {
        let clamped = min(max(window, 3), 5)
        return clamped.isMultiple(of: 2) ? clamped + 1 : clamped
    }

    private static func movingAverage(values: [Double], window: Int) -> [Double] {
        guard !values.isEmpty else { return [] }
        let radius = window / 2
        var prefixSums = Array(repeating: 0.0, count: values.count + 1)
        for index in values.indices {
            prefixSums[index + 1] = prefixSums[index] + values[index]
        }

        return values.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            let total = prefixSums[upper + 1] - prefixSums[lower]
            return total / Double(upper - lower + 1)
        }
    }

    private static func coalescedPoints(
        from points: [HeartRatePoint],
        aggregationInterval: TimeInterval
    ) -> [HeartRatePoint] {
        guard !points.isEmpty, aggregationInterval > 0 else { return points }

        struct Bucket {
            var totalBPM: Double = 0
            var count: Int = 0
            var midpointTimestamp: Date
        }

        let referenceTime = points[0].timestamp.timeIntervalSinceReferenceDate
        var buckets: [Int: Bucket] = [:]

        for point in points {
            let bucketIndex = Int((point.timestamp.timeIntervalSinceReferenceDate - referenceTime) / aggregationInterval)
            let current = buckets[bucketIndex] ?? Bucket(midpointTimestamp: point.timestamp)
            let updatedCount = current.count + 1
            let blendedTimestamp = current.midpointTimestamp.addingTimeInterval(
                point.timestamp.timeIntervalSince(current.midpointTimestamp) / Double(updatedCount)
            )

            buckets[bucketIndex] = Bucket(
                totalBPM: current.totalBPM + point.bpm,
                count: updatedCount,
                midpointTimestamp: blendedTimestamp
            )
        }

        return buckets
            .sorted { $0.key < $1.key }
            .map { _, bucket in
                HeartRatePoint(
                    timestamp: bucket.midpointTimestamp,
                    bpm: bucket.totalBPM / Double(bucket.count)
                )
            }
    }

    private static func robustUpperBound(for values: [Double]) -> Double {
        guard values.count >= 4 else { return values.max() ?? 0 }
        let sorted = values.sorted()
        let q1 = percentile(sorted, p: 0.25)
        let q3 = percentile(sorted, p: 0.75)
        let iqr = q3 - q1
        return q3 + max(18, iqr * 1.5)
    }

    private static func percentile(_ sorted: [Double], p: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = (Double(sorted.count - 1) * p).clamped(to: 0...Double(sorted.count - 1))
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        if lowerIndex == upperIndex { return sorted[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return sorted[lowerIndex] + ((sorted[upperIndex] - sorted[lowerIndex]) * fraction)
    }

    private static func roundDown(_ value: Double, step: Double) -> Double {
        (floor(value / step) * step)
    }

    private static func roundUp(_ value: Double, step: Double) -> Double {
        (ceil(value / step) * step)
    }

    private static func axisValues(for domain: ClosedRange<Double>) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        let roughStep = span / 4
        let step: Double
        switch roughStep {
        case ..<5: step = 5
        case ..<10: step = 10
        case ..<20: step = 20
        case ..<30: step = 25
        default: step = 40
        }

        var values: [Double] = []
        var current = roundDown(domain.lowerBound, step: step)
        while current <= domain.upperBound + 0.5 {
            if current >= domain.lowerBound - 0.5 {
                values.append(current)
            }
            current += step
        }
        return values.isEmpty ? [domain.lowerBound, domain.upperBound] : values
    }

    private static func extractClippedPeaks(
        from points: [DisplayPoint],
        upperBound: Double,
        markerBPM: Double
    ) -> [ClippedPeak] {
        guard !points.isEmpty else { return [] }

        var peaks: [ClippedPeak] = []
        var currentPeak: DisplayPoint?
        var previousTimestamp: Date?
        let mergeGap: TimeInterval = 8 * 60

        for point in points where point.rawBPM > upperBound {
            defer { previousTimestamp = point.timestamp }

            if let previousTimestamp, point.timestamp.timeIntervalSince(previousTimestamp) > mergeGap {
                if let currentPeak {
                    peaks.append(ClippedPeak(timestamp: currentPeak.timestamp, actualBPM: currentPeak.rawBPM, markerBPM: markerBPM))
                }
                currentPeak = point
                continue
            }

            if let existingPeak = currentPeak {
                if point.rawBPM > existingPeak.rawBPM {
                    currentPeak = point
                }
            } else {
                currentPeak = point
            }
        }

        if let currentPeak {
            peaks.append(ClippedPeak(timestamp: currentPeak.timestamp, actualBPM: currentPeak.rawBPM, markerBPM: markerBPM))
        }

        return peaks
    }
}

private struct DisplayPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let rawBPM: Double
    let smoothedBPM: Double
    let displayBPM: Double
}

private struct ClippedPeak: Identifiable {
    let id = UUID()
    let timestamp: Date
    let actualBPM: Double
    let markerBPM: Double
}

private struct ZoneBand: Identifiable {
    let id = UUID()
    let range: ClosedRange<Double>
    let color: Color
}

private enum HeartRateZone: CaseIterable {
    case rest
    case light
    case moderate
    case high

    var range: ClosedRange<Double> {
        switch self {
        case .rest:
            return 40...60
        case .light:
            return 60...100
        case .moderate:
            return 100...140
        case .high:
            return 140...220
        }
    }

    var backgroundColor: Color {
        switch self {
        case .rest:
            return .blue.opacity(0.08)
        case .light:
            return .green.opacity(0.08)
        case .moderate:
            return .orange.opacity(0.09)
        case .high:
            return .red.opacity(0.08)
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

#Preview("Heart Rate Chart") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Heart Rate")
                .font(.headline)
                .foregroundStyle(.red)

            HeartRateChartView(
                points: HeartRateChartSampleData.points,
                events: HeartRateChartSampleData.events
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

private enum HeartRateChartSampleData {
    static let points: [HeartRatePoint] = {
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: Date())

        return stride(from: 0, through: 720, by: 10).map { minute in
            let timestamp = calendar.date(byAdding: .minute, value: minute, to: dayStart) ?? dayStart
            let baseline = 52 + (sin(Double(minute) / 80) * 4)
            let workoutLift: Double
            switch minute {
            case 360...430:
                workoutLift = 32 + (sin(Double(minute) / 14) * 10)
            case 431...470:
                workoutLift = 18 + (sin(Double(minute) / 18) * 6)
            default:
                workoutLift = 0
            }
            let spike = minute == 398 ? 178.0 : baseline + workoutLift
            return HeartRatePoint(timestamp: timestamp, bpm: spike)
        }
    }()

    static let events: [HeartRateChartEvent] = {
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: Date())

        return [
            HeartRateChartEvent(
                timestamp: calendar.date(byAdding: .minute, value: 360, to: dayStart) ?? dayStart,
                label: "Workout Start",
                tint: .orange
            ),
            HeartRateChartEvent(
                timestamp: calendar.date(byAdding: .minute, value: 420, to: dayStart) ?? dayStart,
                label: "Cooldown",
                tint: .blue
            )
        ]
    }()
}
