import SwiftUI
import WidgetKit

private enum WidgetProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case openai
    case cursor
    case elevenlabs

    var id: Self { self }

    init(preferenceValue: String?) {
        switch preferenceValue?.lowercased() {
        case "openai": self = .openai
        case "cursor": self = .cursor
        case "elevenlabs": self = .elevenlabs
        default: self = .claude
        }
    }

    var name: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "Codex"
        case .cursor: return "Cursor"
        case .elevenlabs: return "ElevenLabs"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: return "sparkles"
        case .openai: return "circle.hexagongrid"
        case .cursor: return "cursorarrow.rays"
        case .elevenlabs: return "waveform"
        }
    }
}

private enum WidgetDetailStyle: String {
    case bars
    case capsule
    case orbit

    init(preferenceValue: String?) {
        self = WidgetDetailStyle(rawValue: preferenceValue ?? "") ?? .bars
    }
}

private struct WidgetUsageMetric: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let shortLabel: String?
    let percentUsed: Double?
    let count: Int?
    let valueText: String?
    let resetsAt: Date?
    let resetInterval: TimeInterval?

    var progress: Double? {
        percentUsed.map { min(max($0 / 100, 0), 1) }
    }

    var displayValue: String {
        if let valueText {
            return valueText
        }
        if let count {
            return count.formatted(.number.grouping(.automatic))
        }
        if let percentUsed {
            return "\(Int(round(percentUsed)))%"
        }
        return "—"
    }

    var compactLabel: String {
        shortLabel ?? label
    }

    static func percentage(
        id: String,
        label: String,
        shortLabel: String,
        value: Double,
        resetHours: Double? = nil,
        intervalHours: Double? = nil
    ) -> Self {
        Self(
            id: id,
            label: label,
            shortLabel: shortLabel,
            percentUsed: value,
            count: nil,
            valueText: nil,
            resetsAt: resetHours.map { Date().addingTimeInterval($0 * 3_600) },
            resetInterval: (intervalHours ?? resetHours).map { $0 * 3_600 }
        )
    }

    static func count(id: String, label: String, shortLabel: String, value: Int) -> Self {
        Self(
            id: id,
            label: label,
            shortLabel: shortLabel,
            percentUsed: nil,
            count: value,
            valueText: nil,
            resetsAt: nil,
            resetInterval: nil
        )
    }
}

private struct WidgetSnapshotProvider: Codable, Equatable {
    let updatedAt: Date
    let metrics: [WidgetUsageMetric]
}

private struct WidgetSnapshotPreferences: Codable, Equatable {
    let preferredProvider: String
    let detailStyle: String
}

private struct WidgetUsageSnapshot: Codable, Equatable {
    let version: Int
    let generatedAt: Date
    let providers: [String: WidgetSnapshotProvider]
    let preferences: WidgetSnapshotPreferences?

    var preferredProvider: WidgetProvider {
        WidgetProvider(preferenceValue: preferences?.preferredProvider)
    }

    var detailStyle: WidgetDetailStyle {
        WidgetDetailStyle(preferenceValue: preferences?.detailStyle)
    }

    func data(for provider: WidgetProvider) -> WidgetSnapshotProvider? {
        providers[provider.rawValue]
    }

    static var preview: Self {
        let now = Date()
        return Self(
            version: 2,
            generatedAt: now,
            providers: [
                WidgetProvider.claude.rawValue: WidgetSnapshotProvider(
                    updatedAt: now,
                    metrics: [
                        .percentage(
                            id: "five_hour",
                            label: "5-Hour Window",
                            shortLabel: "5h",
                            value: 19,
                            resetHours: 1.65,
                            intervalHours: 5
                        ),
                        .percentage(
                            id: "limit.fable",
                            label: "Fable (7 day)",
                            shortLabel: "Fab",
                            value: 46,
                            resetHours: 82,
                            intervalHours: 168
                        ),
                        .percentage(
                            id: "seven_day",
                            label: "7-Day Window",
                            shortLabel: "7d",
                            value: 29,
                            resetHours: 130,
                            intervalHours: 168
                        ),
                        .percentage(
                            id: "extra_usage",
                            label: "Extra Usage",
                            shortLabel: "Ex",
                            value: 88
                        )
                    ]
                ),
                WidgetProvider.openai.rawValue: WidgetSnapshotProvider(
                    updatedAt: now,
                    metrics: [
                        .percentage(
                            id: "primary",
                            label: "7-Day Window",
                            shortLabel: "7d",
                            value: 23,
                            resetHours: 92,
                            intervalHours: 168
                        ),
                        .count(
                            id: "reset_credits",
                            label: "Reset Credits",
                            shortLabel: "R",
                            value: 2
                        )
                    ]
                ),
                WidgetProvider.cursor.rawValue: WidgetSnapshotProvider(
                    updatedAt: now,
                    metrics: [
                        .percentage(
                            id: "models",
                            label: "First-Party Models",
                            shortLabel: "M",
                            value: 12,
                            resetHours: 240,
                            intervalHours: 720
                        ),
                        .percentage(
                            id: "api",
                            label: "API",
                            shortLabel: "API",
                            value: 6,
                            resetHours: 240,
                            intervalHours: 720
                        )
                    ]
                ),
                WidgetProvider.elevenlabs.rawValue: WidgetSnapshotProvider(
                    updatedAt: now,
                    metrics: [
                        .percentage(
                            id: "credits",
                            label: "Credits Used",
                            shortLabel: "Used",
                            value: 41,
                            resetHours: 260,
                            intervalHours: 720
                        ),
                        .count(
                            id: "remaining",
                            label: "Credits Remaining",
                            shortLabel: "Left",
                            value: 159_602
                        )
                    ]
                )
            ],
            preferences: WidgetSnapshotPreferences(
                preferredProvider: WidgetProvider.claude.rawValue,
                detailStyle: WidgetDetailStyle.orbit.rawValue
            )
        )
    }

    static var empty: Self {
        Self(
            version: 2,
            generatedAt: Date(),
            providers: [:],
            preferences: WidgetSnapshotPreferences(
                preferredProvider: WidgetProvider.claude.rawValue,
                detailStyle: WidgetDetailStyle.bars.rawValue
            )
        )
    }
}

private struct UsageWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetUsageSnapshot
}

private struct UsageWidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageWidgetEntry {
        UsageWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (UsageWidgetEntry) -> Void
    ) {
        let snapshot = loadSnapshot() ?? (context.isPreview ? .preview : .empty)
        completion(UsageWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<UsageWidgetEntry>) -> Void
    ) {
        let now = Date()
        let entry = UsageWidgetEntry(date: now, snapshot: loadSnapshot() ?? .empty)
        completion(Timeline(
            entries: [entry],
            policy: .after(now.addingTimeInterval(15 * 60))
        ))
    }

    private func loadSnapshot() -> WidgetUsageSnapshot? {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentUsageBar", isDirectory: true)
        let url = directory.appendingPathComponent("usage-snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetUsageSnapshot.self, from: data)
    }
}

private enum WidgetMetricSelection {
    static func topMetrics(
        for provider: WidgetProvider,
        in data: WidgetSnapshotProvider?
    ) -> [WidgetUsageMetric] {
        guard let metrics = data?.metrics else { return [] }
        let preferredIDs: [String]
        switch provider {
        case .claude:
            let modelMetric = metrics.first(where: { $0.id.hasPrefix("limit.") })
            let primary = metrics.first(where: { $0.id == "five_hour" })
            let fallback = metrics.first(where: { $0.id == "seven_day" })
            return [primary, modelMetric ?? fallback].compactMap { $0 }
        case .openai:
            preferredIDs = ["primary", "reset_credits", "secondary"]
        case .cursor:
            preferredIDs = ["models", "api", "total"]
        case .elevenlabs:
            preferredIDs = ["credits", "remaining"]
        }
        let preferred = preferredIDs.compactMap { id in
            metrics.first(where: { $0.id == id })
        }
        return Array((preferred + metrics.filter { metric in
            !preferred.contains(where: { $0.id == metric.id })
        }).prefix(2))
    }
}

private struct WidgetHeader: View {
    let provider: WidgetProvider
    var caption: String?
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            Image(systemName: provider.systemImage)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(provider.name)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let caption {
                Text(caption.uppercased())
                    .font(.system(size: compact ? 7 : 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.4)
                    .lineLimit(1)
            }
        }
    }
}

private struct MetricBar: View {
    let metric: WidgetUsageMetric
    var compact = false
    var showReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            HStack(spacing: 4) {
                Text(metric.label)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(metric.displayValue)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(compact ? .system(size: 9, weight: .medium) : .caption.weight(.medium))

            if let progress = metric.progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.12))
                        Capsule()
                            .fill(usageColor(progress))
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: compact ? 3 : 4)
            } else {
                Capsule()
                    .stroke(.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(height: compact ? 3 : 4)
            }

            if showReset, let resetsAt = metric.resetsAt {
                Text(resetsAt, style: .relative)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MetricCapsule: View {
    let metrics: [WidgetUsageMetric]
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(normalizedMetrics.enumerated()), id: \.offset) { index, metric in
                VStack(spacing: compact ? 3 : 5) {
                    HStack(spacing: 3) {
                        Text(metric?.compactLabel ?? "—")
                            .foregroundStyle(.secondary)
                        Text(metric?.displayValue ?? "—")
                            .monospacedDigit()
                    }
                    .font(.system(size: compact ? 8 : 10, weight: .semibold))
                    .lineLimit(1)

                    if let progress = metric?.progress {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.primary.opacity(0.11))
                                Capsule()
                                    .fill(usageColor(progress))
                                    .frame(width: proxy.size.width * progress)
                            }
                        }
                        .frame(height: compact ? 3 : 4)
                    } else {
                        Capsule()
                            .stroke(
                                .primary.opacity(0.18),
                                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                            )
                            .frame(height: compact ? 3 : 4)
                    }
                }
                .padding(.horizontal, compact ? 5 : 8)
                .frame(maxWidth: .infinity)

                if index == 0 {
                    Rectangle()
                        .fill(.primary.opacity(0.12))
                        .frame(width: 1, height: compact ? 22 : 30)
                }
            }
        }
        .padding(.vertical, compact ? 5 : 7)
        .background(.primary.opacity(0.055), in: Capsule())
        .overlay(Capsule().stroke(.primary.opacity(0.09), lineWidth: 1))
    }

    private var normalizedMetrics: [WidgetUsageMetric?] {
        let values = Array(metrics.prefix(2)).map(Optional.some)
        return values + Array(repeating: nil, count: max(0, 2 - values.count))
    }
}

private struct OrbitGraphic: View {
    let metrics: [WidgetUsageMetric]
    var diameter: CGFloat
    var lineWidth: CGFloat = 7

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let percentageMetrics = metrics.filter { $0.progress != nil }
            let primary = percentageMetrics.first
            let centerDiameter = diameter * (percentageMetrics.count > 1 ? 0.48 : 0.55)
            ZStack {
                if percentageMetrics.count > 1 {
                    ring(
                        progress: percentageMetrics[1].progress ?? 0,
                        color: .orange,
                        diameter: diameter
                    )
                    ring(
                        progress: percentageMetrics[0].progress ?? 0,
                        color: .blue,
                        diameter: diameter * 0.74
                    )
                } else if let primary {
                    ring(
                        progress: primary.progress ?? 0,
                        color: .blue,
                        diameter: diameter
                    )
                } else {
                    Circle()
                        .stroke(.primary.opacity(0.10), lineWidth: lineWidth)
                        .frame(width: diameter, height: diameter)
                }

                ZStack {
                    Circle()
                        .fill(.primary.opacity(0.08))

                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(
                                    height: proxy.size.height
                                        * countdownProgress(for: primary, now: context.date)
                                )
                        }
                    }
                    .clipShape(Circle())

                    Text(remainingTime(for: primary, now: context.date))
                        .font(.system(size: diameter * 0.105, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.62)
                        .lineLimit(1)
                        .frame(width: centerDiameter * 0.82)
                }
                .frame(width: centerDiameter, height: centerDiameter)
            }
            .frame(width: diameter, height: diameter)
        }
    }

    private func ring(progress: Double, color: Color, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func countdownProgress(
        for metric: WidgetUsageMetric?,
        now: Date
    ) -> Double {
        guard let resetDate = metric?.resetsAt,
              let interval = metric?.resetInterval,
              interval > 0 else {
            return 0
        }
        return min(max(resetDate.timeIntervalSince(now) / interval, 0), 1)
    }

    private func remainingTime(for metric: WidgetUsageMetric?, now: Date) -> String {
        guard let resetDate = metric?.resetsAt else { return "—" }
        let totalMinutes = max(0, Int(ceil(resetDate.timeIntervalSince(now) / 60)))
        if totalMinutes >= 24 * 60 {
            let days = totalMinutes / (24 * 60)
            let hours = (totalMinutes % (24 * 60)) / 60
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(totalMinutes)m"
    }
}

private struct OrbitLegend: View {
    let metrics: [WidgetUsageMetric]
    var compact = false
    var horizontal = false

    var body: some View {
        Group {
            if horizontal {
                HStack(alignment: .top, spacing: compact ? 6 : 10) {
                    legendItems
                }
            } else {
                VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                    legendItems
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: horizontal ? .center : .leading)
    }

    @ViewBuilder
    private var legendItems: some View {
        ForEach(Array(metrics.prefix(2).enumerated()), id: \.element.id) { index, metric in
            HStack(alignment: .center, spacing: compact ? 4 : 6) {
                legendMark(for: metric, index: index)
                VStack(alignment: .leading, spacing: 0) {
                    Text(metric.compactLabel)
                        .foregroundStyle(.secondary)
                    Text(metric.displayValue)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                }
                .font(.system(size: compact ? 8 : 10))
                .lineLimit(1)
            }
            .frame(maxWidth: horizontal ? .infinity : nil, alignment: .leading)
        }
    }

    @ViewBuilder
    private func legendMark(for metric: WidgetUsageMetric, index: Int) -> some View {
        if metric.progress == nil {
            Image(systemName: "arrow.counterclockwise.circle")
                .font(.system(size: compact ? 7 : 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 7 : 9)
        } else {
            Circle()
                .fill(index == 0 ? Color.blue : Color.orange)
                .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
        }
    }
}

private struct DetailVisualization: View {
    let style: WidgetDetailStyle
    let metrics: [WidgetUsageMetric]
    var compact = false

    @ViewBuilder
    var body: some View {
        switch style {
        case .bars:
            VStack(spacing: compact ? 6 : 8) {
                ForEach(metrics.prefix(2)) { metric in
                    MetricBar(metric: metric, compact: compact)
                }
            }
        case .capsule:
            MetricCapsule(metrics: metrics, compact: compact)
        case .orbit:
            HStack(spacing: compact ? 7 : 12) {
                OrbitGraphic(
                    metrics: metrics,
                    diameter: compact ? 62 : 76,
                    lineWidth: compact ? 5 : 6
                )
                OrbitLegend(metrics: metrics, compact: compact)
            }
        }
    }
}

private struct NoProviderData: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("No usage data", systemImage: "arrow.triangle.2.circlepath")
                .font(compact ? .system(size: 9, weight: .medium) : .caption.weight(.medium))
            Text("Open Agent Usage Bar to connect or refresh.")
                .font(compact ? .system(size: 8) : .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 1 : 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct PreferredProviderDetailsView: View {
    let entry: UsageWidgetEntry

    var body: some View {
        let provider = entry.snapshot.preferredProvider
        let data = entry.snapshot.data(for: provider)
        let topMetrics = WidgetMetricSelection.topMetrics(for: provider, in: data)
        let topIDs = Set(topMetrics.map(\.id))
        let remaining = data?.metrics.filter { !topIDs.contains($0.id) } ?? []

        Group {
            if data == nil {
                NoProviderData()
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 8) {
                        Group {
                            if entry.snapshot.detailStyle == .orbit {
                                ZStack {
                                    OrbitGraphic(
                                        metrics: topMetrics,
                                        diameter: min(proxy.size.height * 0.82, 122),
                                        lineWidth: 7
                                    )
                                    .offset(y: -6)

                                    OrbitLegend(
                                        metrics: topMetrics,
                                        compact: true,
                                        horizontal: true
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .bottom
                                    )
                                }
                            } else {
                                DetailVisualization(
                                    style: entry.snapshot.detailStyle,
                                    metrics: topMetrics
                                )
                            }
                        }
                        .frame(width: proxy.size.width * 0.68)
                        .frame(maxHeight: .infinity, alignment: .center)

                        VStack(spacing: 7) {
                            ForEach(remaining.prefix(2)) { metric in
                                AdditionalMetricCard(metric: metric)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .widgetSurface(padding: 8)
        .accessibilityLabel("\(provider.name) details")
        .accessibilityElement(children: .contain)
    }
}

private struct AdditionalMetricCard: View {
    let metric: WidgetUsageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.compactLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(metric.displayValue)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.62)
                .lineLimit(1)

            if let progress = metric.progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.11))
                        Capsule()
                            .fill(usageColor(progress))
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PreferredProviderSnapshotView: View {
    let entry: UsageWidgetEntry

    var body: some View {
        let provider = entry.snapshot.preferredProvider
        let data = entry.snapshot.data(for: provider)
        let metrics = WidgetMetricSelection.topMetrics(for: provider, in: data)

        Group {
            if data == nil {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(provider: provider, compact: true)
                    NoProviderData(compact: true)
                }
            } else if entry.snapshot.detailStyle == .orbit {
                ZStack {
                    WidgetHeader(provider: provider, compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    OrbitGraphic(metrics: metrics, diameter: 112, lineWidth: 7)

                    HStack(spacing: 4) {
                        ForEach(metrics.prefix(2)) { metric in
                            Text("\(metric.compactLabel) \(metric.displayValue)")
                                .font(.system(size: 8, weight: .semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(provider: provider, compact: true)
                    Spacer(minLength: 0)
                    DetailVisualization(
                        style: entry.snapshot.detailStyle,
                        metrics: metrics,
                        compact: true
                    )
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetSurface(padding: 8)
    }
}

private struct ProviderDetailGridView: View {
    let entry: UsageWidgetEntry

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(WidgetProvider.allCases) { provider in
                ProviderDetailCard(
                    provider: provider,
                    data: entry.snapshot.data(for: provider),
                    style: entry.snapshot.detailStyle
                )
            }
        }
        .widgetSurface(padding: 10)
    }
}

private struct ProviderDetailCard: View {
    let provider: WidgetProvider
    let data: WidgetSnapshotProvider?
    let style: WidgetDetailStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(provider: provider, compact: true)
            if data == nil {
                NoProviderData(compact: true)
            } else if style == .orbit {
                OrbitGraphic(
                    metrics: WidgetMetricSelection.topMetrics(for: provider, in: data),
                    diameter: 88,
                    lineWidth: 6
                )
                .frame(maxWidth: .infinity)
                OrbitLegend(
                    metrics: WidgetMetricSelection.topMetrics(for: provider, in: data),
                    compact: true,
                    horizontal: true
                )
            } else {
                DetailVisualization(
                    style: style,
                    metrics: WidgetMetricSelection.topMetrics(for: provider, in: data),
                    compact: true
                )
                Spacer(minLength: 0)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OverviewGridView: View {
    let entry: UsageWidgetEntry

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 7),
                GridItem(.flexible(), spacing: 7)
            ],
            spacing: 7
        ) {
            ForEach(WidgetProvider.allCases) { provider in
                OverviewCard(
                    provider: provider,
                    data: entry.snapshot.data(for: provider),
                    isPreferred: provider == entry.snapshot.preferredProvider
                )
            }
        }
        .widgetSurface(padding: 12)
    }
}

private struct OverviewCard: View {
    let provider: WidgetProvider
    let data: WidgetSnapshotProvider?
    let isPreferred: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(provider: provider, compact: true)
            if let data {
                MetricCapsule(
                    metrics: WidgetMetricSelection.topMetrics(for: provider, in: data),
                    compact: true
                )
            } else {
                Text("Connect")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .background(
            isPreferred ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    isPreferred ? Color.accentColor.opacity(0.70) : Color.primary.opacity(0.08),
                    lineWidth: isPreferred ? 1.2 : 1
                )
        )
    }
}

private struct WidgetSurfaceModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "agentusagebar://overview"))
    }
}

private extension View {
    func widgetSurface(padding: CGFloat = 14) -> some View {
        modifier(WidgetSurfaceModifier(padding: padding))
    }
}

private func usageColor(_ progress: Double) -> Color {
    if progress >= 0.9 { return .red }
    if progress >= 0.7 { return .orange }
    return .green
}

private struct PreferredProviderDetailsWidget: Widget {
    let kind = "com.local.AgentUsageBar.Widget.ProviderDetails"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageWidgetTimelineProvider()) { entry in
            PreferredProviderDetailsView(entry: entry)
        }
        .configurationDisplayName("Provider Details")
        .description("Your preferred provider’s visualization and additional usage stats.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct PreferredProviderSnapshotWidget: Widget {
    let kind = "com.local.AgentUsageBar.Widget.ProviderSnapshot"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageWidgetTimelineProvider()) { entry in
            PreferredProviderSnapshotView(entry: entry)
        }
        .configurationDisplayName("Provider Snapshot")
        .description("The top two stats for your preferred provider.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct ProviderDetailGridWidget: Widget {
    let kind = "com.local.AgentUsageBar.Widget.ProviderGrid"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageWidgetTimelineProvider()) { entry in
            ProviderDetailGridView(entry: entry)
        }
        .configurationDisplayName("Provider Detail Grid")
        .description("A 2×2 grid using each provider’s detail visualization.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

private struct OverviewGridWidget: Widget {
    let kind = "com.local.AgentUsageBar.Widget.Overview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageWidgetTimelineProvider()) { entry in
            OverviewGridView(entry: entry)
        }
        .configurationDisplayName("Usage Overview")
        .description("The compact overview from the Agent Usage Bar menu.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct AgentUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        PreferredProviderDetailsWidget()
        PreferredProviderSnapshotWidget()
        ProviderDetailGridWidget()
        OverviewGridWidget()
    }
}
