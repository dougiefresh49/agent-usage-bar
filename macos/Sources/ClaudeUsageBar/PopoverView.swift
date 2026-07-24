import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var connectedService: ConnectedUsageService
    @AppStorage("setupComplete") private var setupComplete = false
    @AppStorage(UsagePresentationDefaults.detailStyleKey)
    private var detailStyleRaw = UsagePresentationDefaults.detailStyle.rawValue
    @AppStorage(UsagePresentationDefaults.textSizeKey)
    private var usageTextSizeRaw = UsagePresentationDefaults.textSize.rawValue
    @State private var selectedProvider: UsageProvider = .claude
    @State private var detailContentHeight: CGFloat = 0

    private static let maxDetailHeight: CGFloat = 460

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !setupComplete && !service.isAuthenticated {
                SetupView(
                    service: service,
                    notificationService: notificationService,
                    connectedService: connectedService,
                    onComplete: { setupComplete = true }
                )
            } else {
                HStack {
                    Text("AI Usage")
                        .usageFont(.pageTitle)
                    Spacer()
                    Text("Overview")
                        .usageFont(.sectionEyebrow)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                ProviderOverview(
                    service: service,
                    connectedService: connectedService,
                    selectedProvider: $selectedProvider,
                    textSize: usageTextSize
                )

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch selectedProvider {
                        case .claude:
                            claudeView
                        case .openAI:
                            OpenAIUsageView(
                                service: connectedService,
                                style: detailStyle,
                                metrics: presentationMetrics(for: .openAI)
                            )
                        case .cursor:
                            CursorUsageView(
                                service: connectedService,
                                style: detailStyle,
                                metrics: presentationMetrics(for: .cursor)
                            )
                        case .elevenLabs:
                            ElevenLabsUsageView(
                                service: connectedService,
                                style: detailStyle,
                                metrics: presentationMetrics(for: .elevenLabs)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: DetailContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                }
                .scrollIndicators(.automatic)
                .onPreferenceChange(DetailContentHeightKey.self) { detailContentHeight = $0 }
                // MenuBarExtra's window measures content at its minimum size, and a
                // ScrollView's minimum height is 0 — an explicit height keeps it from
                // collapsing while still scrolling once content exceeds the cap.
                .frame(height: min(max(detailContentHeight, 1), Self.maxDetailHeight))

                footer
            }
        }
        .padding()
        .frame(width: 390)
        .frame(maxHeight: 720)
        .environment(\.usageTextSize, usageTextSize)
        .dynamicTypeSize(usageTextSize.dynamicTypeSize)
        .onChange(of: connectedService.isElevenLabsConfigured) { _, isConfigured in
            if !isConfigured && selectedProvider == .elevenLabs {
                selectedProvider = .claude
            }
        }
    }

    @ViewBuilder
    private var claudeView: some View {
        ProviderHeader(name: "Claude", systemImage: "sparkles")

        if service.isAuthenticated {
            let metrics = presentationMetrics(for: .claude)
            let summaryMetrics = UsagePresentationMetrics.detailPair(
                for: .claude,
                available: metrics
            )
            DetailUsageVisualization(
                style: detailStyle,
                metrics: summaryMetrics
            )

            ForEach(remainingMetrics(metrics, excluding: summaryMetrics)) { metric in
                if metric.id != UsagePresentationMetrics.claudeExtraID {
                    UsageMetricRow(metric: metric)
                }
            }

            if let extra = service.usage?.extraUsage,
               extra.usedCredits != nil || extra.monthlyLimit != nil {
                ExtraUsageRow(extra: extra)
            }

            DisclosureGroup("Usage history") {
                UsageChartView(historyService: historyService)
                    .padding(.top, 4)
            }
            .usageFont(.supporting)
        } else {
            if service.isAwaitingCode {
                CodeEntryView(service: service)
            } else {
                Text("Connect Claude to view account limits.")
                    .usageFont(.supporting)
                    .foregroundStyle(.secondary)

                Button("Sign in with Claude") {
                    service.startOAuthFlow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        if let error = service.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .usageFont(.supporting)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            if let updaterError = appUpdater.lastError {
                Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                if let latestUpdated {
                    Text("Updated \(latestUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                settingsButton
                Spacer()
                Button("Refresh") {
                    Task {
                        async let claude: Void = service.isAuthenticated
                            ? service.fetchUsage()
                            : ()
                        async let connected: Void = connectedService.fetchAll()
                        _ = await (claude, connected)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                if appUpdater.isConfigured {
                    Button("Check for Updates…") {
                        appUpdater.checkForUpdates()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(!appUpdater.canCheckForUpdates)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var latestUpdated: Date? {
        [
            service.lastUpdated,
            connectedService.openAILastUpdated,
            connectedService.cursorLastUpdated,
            connectedService.elevenLabsLastUpdated
        ]
        .compactMap { $0 }
        .max()
    }

    private var detailStyle: DetailVisualizationStyle {
        DetailVisualizationStyle(rawValue: detailStyleRaw)
            ?? UsagePresentationDefaults.detailStyle
    }

    private var usageTextSize: UsageTextSize {
        UsageTextSize(rawValue: usageTextSizeRaw)
            ?? UsagePresentationDefaults.textSize
    }

    private func presentationMetrics(
        for provider: UsageProvider
    ) -> [UsagePresentationMetric] {
        UsagePresentationMetrics.metrics(
            for: provider,
            claude: service,
            connectedService: connectedService
        )
    }

    private func remainingMetrics(
        _ metrics: [UsagePresentationMetric],
        excluding summary: [UsagePresentationMetric]
    ) -> [UsagePresentationMetric] {
        let summaryIDs = Set(summary.map(\.id))
        return metrics.filter { !summaryIDs.contains($0.id) }
    }

    private var settingsButton: some View {
        SettingsLink {
            Text("Settings…")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}

private struct DetailContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProviderSummary {
    let provider: UsageProvider
    let isConfigured: Bool
    let metrics: [UsagePresentationMetric]
    let error: String?
}

private struct ProviderOverview: View {
    @ObservedObject var service: UsageService
    @ObservedObject var connectedService: ConnectedUsageService
    @Binding var selectedProvider: UsageProvider
    let textSize: UsageTextSize

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0), spacing: 7),
                count: overviewColumnCount
            ),
            spacing: 7
        ) {
            ForEach(summaries, id: \.provider) { summary in
                ProviderSummaryCard(
                    summary: summary,
                    isSelected: selectedProvider == summary.provider
                ) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedProvider = summary.provider
                    }
                }
            }
        }
    }

    private var summaries: [ProviderSummary] {
        var values = [
            ProviderSummary(
                provider: .claude,
                isConfigured: service.isAuthenticated,
                metrics: summaryMetrics(for: .claude),
                error: service.lastError
            ),
            ProviderSummary(
                provider: .openAI,
                isConfigured: connectedService.isOpenAIConfigured,
                metrics: summaryMetrics(for: .openAI),
                error: connectedService.openAIError
            ),
            ProviderSummary(
                provider: .cursor,
                isConfigured: connectedService.isCursorConfigured,
                metrics: summaryMetrics(for: .cursor),
                error: connectedService.cursorError
            )
        ]
        if connectedService.isElevenLabsConfigured {
            values.append(
                ProviderSummary(
                    provider: .elevenLabs,
                    isConfigured: true,
                    metrics: summaryMetrics(for: .elevenLabs),
                    error: connectedService.elevenLabsError
                )
            )
        }
        return values
    }

    private var overviewColumnCount: Int {
        if textSize == .large || summaries.count == 4 {
            return 2
        }
        return textSize.overviewColumnCount
    }

    private func summaryMetrics(
        for provider: UsageProvider
    ) -> [UsagePresentationMetric] {
        let available = UsagePresentationMetrics.metrics(
            for: provider,
            claude: service,
            connectedService: connectedService
        )
        return UsagePresentationMetrics.detailPair(
            for: provider,
            available: available
        )
    }
}

private struct ProviderSummaryCard: View {
    let summary: ProviderSummary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: summary.provider.systemImage)
                        .usageFont(.overviewTitle)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(summary.provider.shortName)
                        .usageFont(.overviewTitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                if !summary.isConfigured {
                    statusLabel("Connect", color: .secondary)
                } else if summary.metrics.allSatisfy({ !$0.hasDisplayValue }) {
                    if summary.error != nil {
                        statusLabel("Check account", color: .red)
                    } else {
                        statusLabel("Loading…", color: .secondary)
                    }
                } else {
                    CompactMetricCapsule(metrics: summary.metrics)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.09),
                        lineWidth: isSelected ? 1.25 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summaryAccessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func statusLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .usageFont(.overviewMetric)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(height: 27, alignment: .center)
    }

    private var summaryAccessibilityLabel: String {
        let values = summary.metrics
            .map { "\($0.label) \($0.accessibilityValue)" }
            .joined(separator: ", ")
        return values.isEmpty
            ? "\(summary.provider.shortName) usage details"
            : "\(summary.provider.shortName), \(values)"
    }
}

private struct CompactMetricCapsule: View {
    let metrics: [UsagePresentationMetric]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(normalizedMetrics.enumerated()), id: \.offset) { index, metric in
                CompactMetricCell(metric: metric)
                if index == 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: 22)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(minHeight: 30)
        .background(Color.primary.opacity(0.055), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var normalizedMetrics: [UsagePresentationMetric?] {
        let values = Array(metrics.prefix(2)).map(Optional.some)
        return values + Array(repeating: nil, count: max(0, 2 - values.count))
    }
}

private struct CompactMetricCell: View {
    let metric: UsagePresentationMetric?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(compactText)
                .usageFont(.overviewMetric)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)

            if let progress = metric?.normalizedProgress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                        Capsule()
                            .fill(colorForPct(progress))
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 3)
            } else {
                Capsule()
                    .stroke(
                        Color.primary.opacity(0.16),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity)
    }

    private var compactText: String {
        guard let metric else { return "—" }
        return "\(metric.shortLabel) \(metric.valueText)"
    }
}

private struct DetailUsageVisualization: View {
    let style: DetailVisualizationStyle
    let metrics: [UsagePresentationMetric]

    @ViewBuilder
    var body: some View {
        switch style {
        case .bars:
            ForEach(metrics) { metric in
                UsageMetricRow(metric: metric)
            }
        case .capsule:
            DetailMetricCapsule(metrics: metrics)
        case .orbit:
            UsageOrbitView(metrics: metrics)
        }
    }
}

private struct UsageMetricRow: View {
    let metric: UsagePresentationMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metric.label)
                    .usageFont(.metric)
                Spacer()
                Text(metric.valueText)
                    .usageFont(.metric)
                    .monospacedDigit()
            }

            if let progress = metric.normalizedProgress {
                ProgressView(value: progress, total: 1)
                    .tint(colorForPct(progress))
            }

            if let resetDate = metric.resetDate {
                Text("Resets \(resetDate, style: .relative)")
                    .usageFont(.supporting)
                    .foregroundStyle(.secondary)
            } else if metric.count != nil {
                Text("Available")
                    .usageFont(.supporting)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(metric.accessibilityValue)
    }
}

private struct DetailMetricCapsule: View {
    let metrics: [UsagePresentationMetric]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(normalizedMetrics.enumerated()), id: \.offset) { index, metric in
                DetailMetricCapsuleCell(metric: metric)
                if index == 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 1, height: 34)
                }
            }
        }
        .padding(.vertical, 7)
        .frame(minHeight: 52)
        .background(Color.primary.opacity(0.045), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }

    private var normalizedMetrics: [UsagePresentationMetric?] {
        let values = Array(metrics.prefix(2)).map(Optional.some)
        return values + Array(repeating: nil, count: max(0, 2 - values.count))
    }
}

private struct DetailMetricCapsuleCell: View {
    let metric: UsagePresentationMetric?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(metric?.label ?? "Unavailable")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(metric?.valueText ?? "—")
                    .monospacedDigit()
            }
            .usageFont(.legend)

            if let progress = metric?.normalizedProgress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                        Capsule()
                            .fill(colorForPct(progress))
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 4)
            } else {
                Capsule()
                    .stroke(
                        Color.primary.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }
}

private struct UsageOrbitView: View {
    let metrics: [UsagePresentationMetric]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 16) {
                orbit(now: context.date)
                legend
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
        }
    }

    private func orbit(now: Date) -> some View {
        let percentages = percentageMetrics
        let countdownMetric = percentages.first
        let countdown = UsagePresentationMetrics.countdownProgress(
            resetDate: countdownMetric?.resetDate,
            interval: countdownMetric?.resetInterval,
            now: now
        ) ?? 0
        let time = UsagePresentationMetrics.compactRemainingTime(
            until: countdownMetric?.resetDate,
            now: now
        ) ?? "—"

        return ZStack {
            if percentages.count > 1 {
                orbitRing(
                    metric: percentages[1],
                    color: .orange,
                    diameter: 112
                )
                orbitRing(
                    metric: percentages[0],
                    color: .blue,
                    diameter: 84
                )
            } else if let metric = percentages.first {
                orbitRing(
                    metric: metric,
                    color: .blue,
                    diameter: 106
                )
            }

            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))

                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: proxy.size.height * countdown)
                    }
                }
                .clipShape(Circle())

                Text(time)
                    .usageFont(.orbitTime)
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
            }
            .frame(width: 58, height: 58)
        }
        .frame(width: 120, height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(orbitAccessibilityLabel(time: time, countdown: countdown))
    }

    private func orbitRing(
        metric: UsagePresentationMetric,
        color: Color,
        diameter: CGFloat
    ) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 8)
            Circle()
                .trim(from: 0, to: metric.normalizedProgress ?? 0)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(metrics.prefix(2).enumerated()), id: \.element.id) { index, metric in
                HStack(spacing: 7) {
                    legendMark(for: metric, index: index)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.label)
                            .usageFont(.legend)
                            .lineLimit(1)
                        Text(metric.isCount
                            ? "\(metric.valueText) available"
                            : metric.valueText)
                            .usageFont(.legendEmphasized)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func legendMark(
        for metric: UsagePresentationMetric,
        index: Int
    ) -> some View {
        if metric.isCount {
            Image(systemName: "arrow.counterclockwise.circle")
                .usageFont(.legend)
                .foregroundStyle(.secondary)
                .frame(width: 10)
        } else {
            Circle()
                .fill(index == 0 ? Color.blue : Color.orange)
                .frame(width: 8, height: 8)
        }
    }

    private var percentageMetrics: [UsagePresentationMetric] {
        metrics.filter { $0.normalizedProgress != nil }
    }

    private func orbitAccessibilityLabel(
        time: String,
        countdown: Double
    ) -> String {
        let values = metrics
            .map { "\($0.label) \($0.accessibilityValue)" }
            .joined(separator: ", ")
        return "\(values), \(Int(round(countdown * 100))) percent of reset time remaining, \(time)"
    }
}

private struct ProviderHeader: View {
    let name: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(name, systemImage: systemImage)
                .usageFont(.detailHeader)
            Spacer()
            Text("Details")
                .usageFont(.supporting)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OpenAIUsageView: View {
    @ObservedObject var service: ConnectedUsageService
    let style: DetailVisualizationStyle
    let metrics: [UsagePresentationMetric]

    var body: some View {
        ProviderHeader(name: "OpenAI / Codex", systemImage: "circle.hexagongrid")

        if !service.isOpenAIConfigured {
            configurePrompt("Add a ChatGPT session token in Settings.")
        } else if let usage = service.openAIUsage {
            let summaryMetrics = UsagePresentationMetrics.detailPair(
                for: .openAI,
                available: metrics
            )
            let summaryIDs = Set(summaryMetrics.map(\.id))

            DetailUsageVisualization(
                style: style,
                metrics: summaryMetrics
            )

            ForEach(metrics.filter { !summaryIDs.contains($0.id) }) { metric in
                UsageMetricRow(metric: metric)
            }

            ForEach(usage.additionalRateLimits ?? []) { additional in
                if let window = additional.rateLimit?.primaryWindow {
                    UsageValueRow(
                        label: additional.label ?? additional.type ?? "Additional Limit",
                        percent: window.usedPercent,
                        resetDate: window.resetDate
                    )
                }
            }

            let announcements = service.openAIResetCredits?.credits.filter(\.isAvailable) ?? []
            if !announcements.isEmpty {
                DisclosureGroup("Announcements (\(announcements.count))") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(announcements) { credit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(credit.title ?? "Available reset")
                                    .usageFont(.legendEmphasized)
                                if let description = credit.description {
                                    Text(description)
                                        .usageFont(.supporting)
                                        .foregroundStyle(.secondary)
                                }
                                if let expiry = credit.expiresAtDate {
                                    Text("Expires \(expiry, style: .relative)")
                                        .usageFont(.supporting)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .usageFont(.supporting)
            }
        } else {
            loadingOrError(service.openAIError)
        }

        if let error = service.openAIError, service.openAIUsage != nil {
            errorLabel(error)
        }
    }
}

private struct CursorUsageView: View {
    @ObservedObject var service: ConnectedUsageService
    let style: DetailVisualizationStyle
    let metrics: [UsagePresentationMetric]

    var body: some View {
        ProviderHeader(name: "Cursor", systemImage: "cursorarrow.rays")

        if !service.isCursorConfigured {
            configurePrompt("Add a Cursor session token in Settings.")
        } else if let usage = service.cursorUsage {
            let summaryMetrics = UsagePresentationMetrics.detailPair(
                for: .cursor,
                available: metrics
            )
            let summaryIDs = Set(summaryMetrics.map(\.id))

            DetailUsageVisualization(
                style: style,
                metrics: summaryMetrics
            )

            ForEach(metrics.filter { !summaryIDs.contains($0.id) }) { metric in
                UsageMetricRow(metric: metric)
            }

            if let spend = usage.spendLimitUsage,
               let used = spend.spent,
               let limit = spend.individualLimit {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("On-Demand")
                            .usageFont(.metric)
                        Spacer()
                        Text("\(UsageMoney.minorUnits(used)) / \(UsageMoney.minorUnits(limit))")
                            .usageFont(.metric)
                            .monospacedDigit()
                    }
                    ProgressView(value: (spend.utilization ?? 0) / 100, total: 1)
                        .tint(colorForPct((spend.utilization ?? 0) / 100))
                }
            }
        } else {
            loadingOrError(service.cursorError)
        }

        if let error = service.cursorError, service.cursorUsage != nil {
            errorLabel(error)
        }
    }
}

private struct ElevenLabsUsageView: View {
    @ObservedObject var service: ConnectedUsageService
    let style: DetailVisualizationStyle
    let metrics: [UsagePresentationMetric]

    var body: some View {
        ProviderHeader(name: "ElevenLabs", systemImage: "waveform")

        if !service.isElevenLabsConfigured {
            configurePrompt("Add an ElevenLabs API key in Settings.")
        } else if let usage = service.elevenLabsUsage {
            let summaryMetrics = UsagePresentationMetrics.detailPair(
                for: .elevenLabs,
                available: metrics
            )

            DetailUsageVisualization(
                style: style,
                metrics: summaryMetrics
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Subscription")
                        .usageFont(.legendEmphasized)
                    Spacer()
                    if let status = usage.status {
                        Text(displayName(status))
                            .usageFont(.supporting)
                            .foregroundStyle(
                                status.lowercased() == "active" ? .green : .secondary
                            )
                    }
                }

                Divider()

                elevenLabsValueRow(
                    "Plan",
                    value: usage.tier.map(displayName) ?? "—"
                )
                elevenLabsValueRow(
                    "Total credits",
                    value: formattedCredits(usage.characterLimit)
                )
                elevenLabsValueRow(
                    "Credits used",
                    value: formattedCredits(usage.characterCount)
                )
                elevenLabsValueRow(
                    "Credits remaining",
                    value: formattedCredits(usage.creditsRemaining)
                )

                if let billingPeriod = usage.billingPeriod {
                    elevenLabsValueRow(
                        "Billing cycle",
                        value: displayName(
                            billingPeriod.replacingOccurrences(
                                of: "_period",
                                with: ""
                            )
                        )
                    )
                }

                if let used = usage.voiceSlotsUsed, let limit = usage.voiceLimit {
                    elevenLabsValueRow(
                        "Voice slots",
                        value: "\(used.formatted()) of \(limit.formatted())"
                    )
                }

                if let used = usage.professionalVoiceSlotsUsedInWorkspace,
                   let limit = usage.professionalVoiceLimit {
                    elevenLabsValueRow(
                        "Professional voices",
                        value: "\(used.formatted()) of \(limit.formatted())"
                    )
                }

                if let resetDate = usage.nextResetDate {
                    elevenLabsValueRow(
                        "Next reset",
                        value: resetDate.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
        } else {
            loadingOrError(service.elevenLabsError)
        }

        if let error = service.elevenLabsError, service.elevenLabsUsage != nil {
            errorLabel(error)
        }
    }

    private func elevenLabsValueRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .usageFont(.supporting)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .usageFont(.legendEmphasized)
                .monospacedDigit()
        }
    }

    private func formattedCredits(_ value: Int?) -> String {
        value?.formatted(.number.grouping(.automatic)) ?? "—"
    }

    private func displayName(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private struct UsageValueRow: View {
    let label: String
    let percent: Double?
    let resetDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .usageFont(.metric)
                Spacer()
                Text(percent.map { "\(Int(round($0)))%" } ?? "—")
                    .usageFont(.metric)
                    .monospacedDigit()
            }
            ProgressView(value: (percent ?? 0) / 100, total: 1)
                .tint(colorForPct((percent ?? 0) / 100))
            if let resetDate {
                Text("Resets \(resetDate, style: .relative)")
                    .usageFont(.supporting)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func configurePrompt(_ text: String) -> some View {
    HStack {
        Text(text)
            .usageFont(.supporting)
            .foregroundStyle(.secondary)
        Spacer()
        SettingsLink {
            Text("Configure")
        }
        .usageFont(.supporting)
        .buttonStyle(.borderless)
    }
}

@ViewBuilder
private func loadingOrError(_ error: String?) -> some View {
    if let error {
        errorLabel(error)
    } else {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Loading…")
                .usageFont(.supporting)
                .foregroundStyle(.secondary)
        }
    }
}

private func errorLabel(_ error: String) -> some View {
    Label(error, systemImage: "exclamationmark.triangle")
        .usageFont(.supporting)
        .foregroundStyle(.red)
}

// MARK: - Setup (first launch)

private struct SetupView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var connectedService: ConnectedUsageService
    var onComplete: () -> Void

    var body: some View {
        Text("Welcome")
            .font(.headline)
        Text("Configure your preferences to get started.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        Divider()

        LaunchAtLoginToggle(controlSize: .small, useSwitchStyle: true)

        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SetupThresholdSlider(
                label: "Session usage",
                value: notificationService.claudeSessionThreshold,
                onChange: { notificationService.setClaudeSessionThreshold($0) }
            )
            SetupThresholdSlider(
                label: "Seven-day usage",
                value: notificationService.claudeSevenDayThreshold,
                onChange: { notificationService.setClaudeSevenDayThreshold($0) }
            )
            SetupThresholdSlider(
                label: "Fable usage",
                value: notificationService.claudeFableThreshold,
                onChange: { notificationService.setClaudeFableThreshold($0) }
            )
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text("Polling Interval")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { service.pollingMinutes },
                set: {
                    service.updatePollingInterval($0)
                    connectedService.updatePollingInterval($0)
                }
            )) {
                ForEach(UsageService.pollingOptions, id: \.self) { mins in
                    Text(localizedPollingInterval(for: mins, locale: .autoupdatingCurrent))
                        .tag(mins)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isDiscouragedPollingOption(service.pollingMinutes) {
                Text("Frequent polling may cause rate limiting")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }

        Divider()

        Button("Get Started") {
            onComplete()
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)

        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Subviews

private struct CodeEntryView: View {
    @ObservedObject var service: UsageService
    @State private var code = ""

    var body: some View {
        Text("Paste the code from your browser:")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        HStack(spacing: 4) {
            TextField("code#state", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { submit() }
            Button {
                if let str = NSPasteboard.general.string(forType: .string) {
                    code = str.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
        }

        HStack {
            Button("Cancel") {
                service.isAwaitingCode = false
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Submit") { submit() }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty)
        }
    }

    private func submit() {
        let value = code
        Task { await service.submitOAuthCode(value) }
    }
}

private struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extra Usage")
                .usageFont(.metric)
            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                HStack {
                    Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                        .usageFont(.legend)
                        .monospacedDigit()
                    Spacer()
                    if let pct = extra.utilization {
                        Text("\(Int(round(pct)))%")
                            .usageFont(.legend)
                            .monospacedDigit()
                    }
                }
                ProgressView(value: (extra.utilization ?? 0) / 100.0, total: 1.0)
                    .tint(.blue)
            }
        }
    }
}

private struct SetupThresholdSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text(value > 0 ? "\(value)%" : "Off")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: 0...100,
                step: 5
            )
            .controlSize(.small)
        }
    }
}

private func colorForPct(_ pct: Double) -> Color {
    switch pct {
    case ..<0.60: return .green
    case 0.60..<0.80: return .yellow
    default: return .red
    }
}

private struct UsageTextSizeEnvironmentKey: EnvironmentKey {
    static let defaultValue = UsagePresentationDefaults.textSize
}

private extension EnvironmentValues {
    var usageTextSize: UsageTextSize {
        get { self[UsageTextSizeEnvironmentKey.self] }
        set { self[UsageTextSizeEnvironmentKey.self] = newValue }
    }
}

private enum UsageFontRole {
    case pageTitle
    case sectionEyebrow
    case overviewTitle
    case overviewMetric
    case detailHeader
    case metric
    case supporting
    case legend
    case legendEmphasized
    case orbitTime

    func font(for size: UsageTextSize) -> Font {
        switch (self, size) {
        case (.pageTitle, .compact): return .headline
        case (.pageTitle, .comfortable): return .title3.weight(.semibold)
        case (.pageTitle, .large): return .title2.weight(.semibold)

        case (.sectionEyebrow, .compact): return .caption2.weight(.medium)
        case (.sectionEyebrow, .comfortable): return .caption.weight(.medium)
        case (.sectionEyebrow, .large): return .callout.weight(.medium)

        case (.overviewTitle, .compact): return .caption.weight(.semibold)
        case (.overviewTitle, .comfortable): return .callout.weight(.semibold)
        case (.overviewTitle, .large): return .body.weight(.semibold)

        case (.overviewMetric, .compact): return .caption2
        case (.overviewMetric, .comfortable): return .caption
        case (.overviewMetric, .large): return .callout

        case (.detailHeader, .compact): return .subheadline.weight(.semibold)
        case (.detailHeader, .comfortable): return .headline
        case (.detailHeader, .large): return .title3.weight(.semibold)

        case (.metric, .compact): return .subheadline
        case (.metric, .comfortable): return .body
        case (.metric, .large): return .title3

        case (.supporting, .compact): return .caption2
        case (.supporting, .comfortable): return .caption
        case (.supporting, .large): return .callout

        case (.legend, .compact): return .caption
        case (.legend, .comfortable): return .callout
        case (.legend, .large): return .body

        case (.legendEmphasized, .compact): return .caption.weight(.medium)
        case (.legendEmphasized, .comfortable): return .callout.weight(.semibold)
        case (.legendEmphasized, .large): return .body.weight(.semibold)

        case (.orbitTime, .compact): return .caption.weight(.medium)
        case (.orbitTime, .comfortable): return .callout.weight(.medium)
        case (.orbitTime, .large): return .body.weight(.medium)
        }
    }
}

private struct UsageFontModifier: ViewModifier {
    @Environment(\.usageTextSize) private var textSize
    let role: UsageFontRole

    func body(content: Content) -> some View {
        content.font(role.font(for: textSize))
    }
}

private extension View {
    func usageFont(_ role: UsageFontRole) -> some View {
        modifier(UsageFontModifier(role: role))
    }
}

private extension UsageTextSize {
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .compact: return .large
        case .comfortable: return .xxLarge
        case .large: return .accessibility1
        }
    }
}
