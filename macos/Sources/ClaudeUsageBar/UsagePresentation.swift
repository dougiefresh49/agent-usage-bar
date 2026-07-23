import Foundation

enum UsageProvider: String, CaseIterable, Identifiable {
    case claude
    case openAI
    case cursor

    var id: Self { self }

    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .openAI: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    var settingsName: String {
        switch self {
        case .claude: return "Claude"
        case .openAI: return "OpenAI / Codex"
        case .cursor: return "Cursor"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: return "sparkles"
        case .openAI: return "circle.hexagongrid"
        case .cursor: return "cursorarrow.rays"
        }
    }
}

enum MenuBarVisualizationStyle: String, CaseIterable, Identifiable {
    case bars
    case capsule

    var id: Self { self }

    var displayName: String {
        switch self {
        case .bars: return "Bars"
        case .capsule: return "Capsule"
        }
    }
}

enum DetailVisualizationStyle: String, CaseIterable, Identifiable {
    case bars
    case capsule
    case orbit

    var id: Self { self }

    var displayName: String {
        switch self {
        case .bars: return "Bars"
        case .capsule: return "Capsule"
        case .orbit: return "Orbit"
        }
    }
}

enum UsageTextSize: String, CaseIterable, Identifiable {
    case compact
    case comfortable
    case large

    var id: Self { self }

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .comfortable: return "Comfortable"
        case .large: return "Large"
        }
    }

    var overviewColumnCount: Int {
        self == .large ? 2 : 3
    }
}

enum UsagePresentationDefaults {
    static let menuBarProviderKey = "menuBarProvider"
    static let menuBarStyleKey = "menuBarVisualizationStyle"
    static let menuBarPrimaryMetricKey = "menuBarPrimaryMetric"
    static let menuBarSecondaryMetricKey = "menuBarSecondaryMetric"
    static let detailStyleKey = "detailVisualizationStyle"
    static let textSizeKey = "usageTextSize"

    static let menuBarProvider = UsageProvider.claude
    static let menuBarStyle = MenuBarVisualizationStyle.bars
    static let detailStyle = DetailVisualizationStyle.bars
    static let textSize = UsageTextSize.comfortable
}

enum UsageMetricKind: Equatable {
    case percentage(Double?)
    case count(Int?)
}

struct UsagePresentationMetric: Identifiable, Equatable {
    let id: String
    let label: String
    let shortLabel: String
    let kind: UsageMetricKind
    let resetDate: Date?
    let resetInterval: TimeInterval?

    var normalizedProgress: Double? {
        guard case .percentage(let percent?) = kind else { return nil }
        return min(max(percent / 100, 0), 1)
    }

    var percentage: Double? {
        guard case .percentage(let percent) = kind else { return nil }
        return percent
    }

    var count: Int? {
        guard case .count(let count) = kind else { return nil }
        return count
    }

    var isCount: Bool {
        if case .count = kind { return true }
        return false
    }

    var hasDisplayValue: Bool {
        switch kind {
        case .percentage(.some), .count(.some): return true
        case .percentage(.none), .count(.none): return false
        }
    }

    var valueText: String {
        switch kind {
        case .percentage(let percent?):
            return "\(Int(round(percent)))%"
        case .percentage(nil), .count(nil):
            return "—"
        case .count(let count?):
            return "\(count)"
        }
    }

    var accessibilityValue: String {
        switch kind {
        case .percentage(let percent?):
            return "\(Int(round(percent))) percent"
        case .percentage(nil), .count(nil):
            return "Unavailable"
        case .count(let count?):
            return "\(count) available"
        }
    }
}

@MainActor
enum UsagePresentationMetrics {
    static let claudeFiveHourID = "claude.5h"
    static let claudeSevenDayID = "claude.7d"
    static let claudeOpusID = "claude.opus"
    static let claudeSonnetID = "claude.sonnet"
    static let claudeExtraID = "claude.extra"
    static let openAIPrimaryID = "openai.primary"
    static let openAISecondaryID = "openai.secondary"
    static let openAIResetCreditsID = "openai.resetCredits"
    static let cursorModelsID = "cursor.models"
    static let cursorAPIID = "cursor.api"
    static let cursorTotalID = "cursor.total"

    static func metrics(
        for provider: UsageProvider,
        claude service: UsageService,
        connectedService: ConnectedUsageService
    ) -> [UsagePresentationMetric] {
        switch provider {
        case .claude:
            return claudeMetrics(service.usage)
        case .openAI:
            return openAIMetrics(
                usage: connectedService.openAIUsage,
                resetCredits: connectedService.openAIResetCredits
            )
        case .cursor:
            return cursorMetrics(connectedService.cursorUsage)
        }
    }

    static func defaults(
        for provider: UsageProvider,
        available metrics: [UsagePresentationMetric]
    ) -> (primary: String, secondary: String) {
        let preferred: [String]
        switch provider {
        case .claude:
            preferred = [claudeFiveHourID, claudeSevenDayID]
        case .openAI:
            preferred = [openAIPrimaryID, openAIResetCreditsID, openAISecondaryID]
        case .cursor:
            preferred = [cursorModelsID, cursorAPIID, cursorTotalID]
        }

        let availableIDs = Set(metrics.map(\.id))
        let resolved = preferred.filter(availableIDs.contains)
        let fallback = metrics.map(\.id)
        let primary = resolved.first ?? fallback.first ?? ""
        let secondary = resolved.dropFirst().first
            ?? fallback.first(where: { $0 != primary })
            ?? primary
        return (primary, secondary)
    }

    static func resolvedPair(
        provider: UsageProvider,
        primaryID: String,
        secondaryID: String,
        available metrics: [UsagePresentationMetric]
    ) -> [UsagePresentationMetric] {
        guard !metrics.isEmpty else { return [] }
        let defaults = defaults(for: provider, available: metrics)
        let primary = metrics.first(where: { $0.id == primaryID })
            ?? metrics.first(where: { $0.id == defaults.primary })
            ?? metrics[0]
        let secondary = metrics.first(where: { $0.id == secondaryID && $0.id != primary.id })
            ?? metrics.first(where: { $0.id == defaults.secondary && $0.id != primary.id })
            ?? metrics.first(where: { $0.id != primary.id })
        var result = [primary]
        if let secondary {
            result.append(secondary)
        }
        return result
    }

    static func detailPair(
        for provider: UsageProvider,
        available metrics: [UsagePresentationMetric]
    ) -> [UsagePresentationMetric] {
        switch provider {
        case .claude:
            let primary = metrics.first(where: { $0.id == claudeFiveHourID })
            let modelSpecific = metrics.first(where: { $0.id.hasPrefix("claude.limit.") })
            let fallback = metrics.first(where: { $0.id == claudeSevenDayID })
            return compactPair(primary: primary, secondary: modelSpecific ?? fallback)
        case .openAI:
            return compactPair(
                primary: metrics.first(where: { $0.id == openAIPrimaryID }),
                secondary: metrics.first(where: { $0.id == openAIResetCreditsID })
                    ?? metrics.first(where: { $0.id == openAISecondaryID })
            )
        case .cursor:
            return compactPair(
                primary: metrics.first(where: { $0.id == cursorModelsID }),
                secondary: metrics.first(where: { $0.id == cursorAPIID })
            )
        }
    }

    nonisolated static func countdownProgress(
        resetDate: Date?,
        interval: TimeInterval?,
        now: Date = Date()
    ) -> Double? {
        guard let resetDate, let interval, interval > 0 else { return nil }
        return min(max(resetDate.timeIntervalSince(now) / interval, 0), 1)
    }

    nonisolated static func compactRemainingTime(
        until resetDate: Date?,
        now: Date = Date()
    ) -> String? {
        guard let resetDate else { return nil }
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

    private static func compactPair(
        primary: UsagePresentationMetric?,
        secondary: UsagePresentationMetric?
    ) -> [UsagePresentationMetric] {
        [primary, secondary].compactMap { $0 }
    }

    private static func claudeMetrics(_ usage: UsageResponse?) -> [UsagePresentationMetric] {
        var metrics = [
            percentageMetric(
                id: claudeFiveHourID,
                label: "5-Hour Window",
                shortLabel: "5h",
                percent: usage?.fiveHour?.utilization,
                resetDate: usage?.fiveHour?.resetsAtDate,
                resetInterval: 5 * 60 * 60
            ),
            percentageMetric(
                id: claudeSevenDayID,
                label: "7-Day Window",
                shortLabel: "7d",
                percent: usage?.sevenDay?.utilization,
                resetDate: usage?.sevenDay?.resetsAtDate,
                resetInterval: 7 * 24 * 60 * 60
            )
        ]

        if let opus = usage?.sevenDayOpus, opus.utilization != nil {
            metrics.append(
                percentageMetric(
                    id: claudeOpusID,
                    label: "Opus (7 day)",
                    shortLabel: "Op",
                    percent: opus.utilization,
                    resetDate: opus.resetsAtDate,
                    resetInterval: 7 * 24 * 60 * 60
                )
            )
        }
        if let sonnet = usage?.sevenDaySonnet, sonnet.utilization != nil {
            metrics.append(
                percentageMetric(
                    id: claudeSonnetID,
                    label: "Sonnet (7 day)",
                    shortLabel: "Sn",
                    percent: sonnet.utilization,
                    resetDate: sonnet.resetsAtDate,
                    resetInterval: 7 * 24 * 60 * 60
                )
            )
        }
        for limit in usage?.scopedModelLimits ?? [] {
            let modelName = limit.scope?.model?.displayName ?? "Model"
            let groupLabel: String
            switch limit.group {
            case "weekly": groupLabel = "7 day"
            case "session": groupLabel = "session"
            case let group?: groupLabel = group.replacingOccurrences(of: "_", with: " ")
            case nil: groupLabel = ""
            }
            let label = groupLabel.isEmpty ? modelName : "\(modelName) (\(groupLabel))"
            metrics.append(
                percentageMetric(
                    id: "claude.limit.\(limit.id)",
                    label: label,
                    shortLabel: compactLabel(modelName),
                    percent: limit.percent,
                    resetDate: limit.resetsAtDate,
                    resetInterval: limit.group == "session"
                        ? 5 * 60 * 60
                        : 7 * 24 * 60 * 60
                )
            )
        }
        if let extra = usage?.extraUsage, extra.utilization != nil {
            metrics.append(
                percentageMetric(
                    id: claudeExtraID,
                    label: "Extra Usage",
                    shortLabel: "Ex",
                    percent: extra.utilization,
                    resetDate: nil,
                    resetInterval: nil
                )
            )
        }
        return metrics
    }

    private static func openAIMetrics(
        usage: OpenAIUsageResponse?,
        resetCredits: OpenAIResetCreditsResponse?
    ) -> [UsagePresentationMetric] {
        let primary = usage?.rateLimit?.primaryWindow
        let secondary = usage?.rateLimit?.secondaryWindow
        let count = resetCredits?.availableCount
            ?? resetCredits.map { $0.credits.filter(\.isAvailable).count }
            ?? usage?.rateLimitResetCredits?.applicableAvailableCount
            ?? usage?.rateLimitResetCredits?.availableCount

        var metrics = [
            percentageMetric(
                id: openAIPrimaryID,
                label: windowLabel(primary, fallback: "Primary Window"),
                shortLabel: compactWindowLabel(primary, fallback: "Wk"),
                percent: primary?.usedPercent,
                resetDate: primary?.resetDate,
                resetInterval: primary?.limitWindowSeconds
            ),
            UsagePresentationMetric(
                id: openAIResetCreditsID,
                label: "Reset Credits",
                shortLabel: "R",
                kind: .count(count),
                resetDate: nil,
                resetInterval: nil
            )
        ]

        if secondary != nil {
            metrics.append(
                percentageMetric(
                    id: openAISecondaryID,
                    label: windowLabel(secondary, fallback: "Secondary Window"),
                    shortLabel: compactWindowLabel(secondary, fallback: "2nd"),
                    percent: secondary?.usedPercent,
                    resetDate: secondary?.resetDate,
                    resetInterval: secondary?.limitWindowSeconds
                )
            )
        }
        return metrics
    }

    private static func cursorMetrics(_ usage: CursorUsageResponse?) -> [UsagePresentationMetric] {
        let resetDate = usage?.billingCycleEndDate
        let interval: TimeInterval = 30 * 24 * 60 * 60
        return [
            percentageMetric(
                id: cursorModelsID,
                label: "First-Party Models",
                shortLabel: "M",
                percent: usage?.planUsage?.autoPercentUsed,
                resetDate: resetDate,
                resetInterval: interval
            ),
            percentageMetric(
                id: cursorAPIID,
                label: "API",
                shortLabel: "API",
                percent: usage?.planUsage?.apiPercentUsed,
                resetDate: resetDate,
                resetInterval: interval
            ),
            percentageMetric(
                id: cursorTotalID,
                label: "Total Plan Usage",
                shortLabel: "Tot",
                percent: usage?.planUsage?.totalPercentUsed,
                resetDate: resetDate,
                resetInterval: interval
            )
        ]
    }

    private static func percentageMetric(
        id: String,
        label: String,
        shortLabel: String,
        percent: Double?,
        resetDate: Date?,
        resetInterval: TimeInterval?
    ) -> UsagePresentationMetric {
        UsagePresentationMetric(
            id: id,
            label: label,
            shortLabel: shortLabel,
            kind: .percentage(percent),
            resetDate: resetDate,
            resetInterval: resetInterval
        )
    }

    private static func windowLabel(
        _ window: OpenAIUsageWindow?,
        fallback: String
    ) -> String {
        guard let seconds = window?.limitWindowSeconds else { return fallback }
        let hours = Int(seconds / 3_600)
        if hours > 0, hours % 24 == 0 {
            return "\(hours / 24)-Day Window"
        }
        if hours > 0 {
            return "\(hours)-Hour Window"
        }
        return fallback
    }

    private static func compactWindowLabel(
        _ window: OpenAIUsageWindow?,
        fallback: String
    ) -> String {
        guard let seconds = window?.limitWindowSeconds else { return fallback }
        let hours = Int(seconds / 3_600)
        if hours > 0, hours % 24 == 0 {
            return "\(hours / 24)d"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return fallback
    }

    private static func compactLabel(_ label: String) -> String {
        let letters = label.filter(\.isLetter)
        guard !letters.isEmpty else { return "M" }
        return String(letters.prefix(3))
    }
}
