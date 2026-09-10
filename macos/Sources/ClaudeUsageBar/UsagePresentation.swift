import Foundation

enum UsageProvider: String, CaseIterable, Identifiable {
    case claude
    case openAI
    case cursor
    case elevenLabs

    var id: Self { self }

    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .openAI: return "Codex"
        case .cursor: return "Cursor"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var settingsName: String {
        switch self {
        case .claude: return "Claude"
        case .openAI: return "OpenAI / Codex"
        case .cursor: return "Cursor"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: return "sparkles"
        case .openAI: return "circle.hexagongrid"
        case .cursor: return "cursorarrow.rays"
        case .elevenLabs: return "waveform"
        }
    }

    var usagePageURL: URL {
        switch self {
        case .claude:
            return URL(string: "https://claude.ai/new#settings/usage")!
        case .openAI:
            return URL(string: "https://chatgpt.com/#settings/Usage")!
        case .cursor:
            return URL(string: "https://cursor.com/dashboard/spending")!
        case .elevenLabs:
            return URL(string: "https://elevenlabs.io/app/subscription/")!
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

enum UsageFillMode: String, CaseIterable, Identifiable {
    case fill
    case drain

    var id: Self { self }

    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .drain: return "Drain"
        }
    }

    /// Fraction a bar or ring draws for a used share (0...1): the used share in fill, what is left in drain.
    func drawnShare(used: Double) -> Double {
        let clamped = min(max(used, 0), 1)
        switch self {
        case .fill: return clamped
        case .drain: return 1 - clamped
        }
    }

    /// Where the even-pace hairline sits (0...1) for an elapsed share; the bar's leading edge on it means on pace in both modes.
    func hairlinePosition(elapsed: Double) -> Double {
        drawnShare(used: elapsed)
    }
}

enum UsagePresentationDefaults {
    static let menuBarProviderKey = "menuBarProvider"
    static let menuBarStyleKey = "menuBarVisualizationStyle"
    static let menuBarPrimaryMetricKey = "menuBarPrimaryMetric"
    static let menuBarSecondaryMetricKey = "menuBarSecondaryMetric"
    static let detailStyleKey = "detailVisualizationStyle"
    static let textSizeKey = "usageTextSize"
    static let fillModeKey = "usageFillMode"

    static let menuBarProvider = UsageProvider.claude
    static let menuBarStyle = MenuBarVisualizationStyle.bars
    static let detailStyle = DetailVisualizationStyle.bars
    static let textSize = UsageTextSize.comfortable
    static let fillMode = UsageFillMode.drain
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
    /// Pace inputs for Claude, Codex, and Cursor Grok Bot windows. Other Cursor metrics and ElevenLabs stay nil.
    let geometry: UsageWindowGeometry?
    /// Popover labels for drain mode when the default label names the used share
    /// ("Credits Used"); nil keeps `label` and `shortLabel` in both modes.
    let drainLabel: String?
    let drainShortLabel: String?

    init(
        id: String,
        label: String,
        shortLabel: String,
        kind: UsageMetricKind,
        resetDate: Date?,
        resetInterval: TimeInterval?,
        geometry: UsageWindowGeometry? = nil,
        drainLabel: String? = nil,
        drainShortLabel: String? = nil
    ) {
        self.id = id
        self.label = label
        self.shortLabel = shortLabel
        self.kind = kind
        self.resetDate = resetDate
        self.resetInterval = resetInterval
        self.geometry = geometry
        self.drainLabel = drainLabel
        self.drainShortLabel = drainShortLabel
    }

    /// Popover label for the mode; the menu bar and widgets keep `label`.
    func label(mode: UsageFillMode) -> String {
        mode == .drain ? (drainLabel ?? label) : label
    }

    /// Popover short label for the mode; the menu bar and widgets keep `shortLabel`.
    func shortLabel(mode: UsageFillMode) -> String {
        mode == .drain ? (drainShortLabel ?? shortLabel) : shortLabel
    }

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

    /// Used-percent text for menu bar, widgets, and overview capsules.
    var valueText: String {
        switch kind {
        case .percentage(let percent?):
            return "\(Int(round(percent)))%"
        case .percentage(nil), .count(nil):
            return "—"
        case .count(let count?):
            return count.formatted(.number.grouping(.automatic))
        }
    }

    /// Drawn bar/ring fraction for the popover: used share in fill, remaining share in drain.
    func displayedProgress(mode: UsageFillMode) -> Double? {
        normalizedProgress.map { mode.drawnShare(used: $0) }
    }

    /// Popover headline for percentage metrics ("31% used" / "69% left"); nil for counts and missing percent.
    func headlineText(mode: UsageFillMode) -> String? {
        guard case .percentage(let percent?) = kind else { return nil }
        switch mode {
        case .fill:
            return "\(Int(round(percent)))% used"
        case .drain:
            return "\(UsagePace.remainingPercent(percent))% left"
        }
    }

    /// Overview-capsule value: used percent in fill, remaining percent in drain; counts unchanged.
    func compactValueText(mode: UsageFillMode) -> String {
        guard case .percentage(let percent?) = kind else { return valueText }
        switch mode {
        case .fill:
            return valueText
        case .drain:
            return "\(UsagePace.remainingPercent(percent))%"
        }
    }

    func pace(now: Date = Date()) -> UsagePace? {
        guard let geometry else { return nil }
        return UsagePace.pace(geometry, now: now)
    }

    /// SF Symbol for the pace glyph, or nil when pace cannot be computed.
    func paceSystemImage(now: Date = Date()) -> String? {
        switch pace(now: now) {
        case .ahead: return "arrow.up.right"
        case .on: return "minus"
        case .under: return "arrow.down.right"
        case nil: return nil
        }
    }

    /// Spoken pace label for popover accessibility, keyed on `UsagePace` rather than the glyph name.
    func paceAccessibilityText(now: Date = Date()) -> String? {
        switch pace(now: now) {
        case .ahead: return "ahead of pace"
        case .on: return "on pace"
        case .under: return "under pace"
        case nil: return nil
        }
    }

    /// Tooltip for the pace glyph, in plain words: "Ahead of pace: used 91%, window 78% elapsed".
    func paceHelpText(now: Date = Date()) -> String? {
        guard let geometry,
              let paceText = paceAccessibilityText(now: now),
              let elapsed = elapsedShare(now: now) else { return nil }
        let used = Int(min(100, max(0, geometry.usedPercent)).rounded(.toNearestOrAwayFromZero))
        let elapsedPercent = Int((elapsed * 100).rounded(.toNearestOrAwayFromZero))
        return "\(paceText.prefix(1).uppercased())\(paceText.dropFirst()): used \(used)%, window \(elapsedPercent)% elapsed"
    }

    func restoresLine(now: Date = Date()) -> String? {
        guard let geometry else { return nil }
        return UsagePace.restoresLine(geometry, now: now)
    }

    func elapsedShare(now: Date = Date()) -> Double? {
        guard let geometry else { return nil }
        return UsagePace.elapsedShare(geometry, now: now)
    }

    /// Relative "Resets …" fallback when there is no pace geometry (Cursor, ElevenLabs, and similar).
    var showsLegacyResetLine: Bool {
        geometry == nil
    }

    /// Used-percent accessibility for the menu bar and overview.
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

    /// Overview-card accessibility value in the mode's terms: "31 percent used" / "69 percent left".
    func accessibilityValue(mode: UsageFillMode) -> String {
        guard case .percentage(let percent?) = kind else { return accessibilityValue }
        switch mode {
        case .fill: return "\(Int(round(percent))) percent used"
        case .drain: return "\(UsagePace.remainingPercent(percent)) percent left"
        }
    }

    /// Popover accessibility value: mode headline, optional pace, optional restores line.
    func popoverAccessibilityValue(mode: UsageFillMode, now: Date = Date()) -> String {
        if let headline = headlineText(mode: mode) {
            var parts = [headline]
            if let paceText = paceAccessibilityText(now: now) {
                parts.append(paceText)
            }
            if let restores = restoresLine(now: now) {
                parts.append(restores)
            }
            return parts.joined(separator: ", ")
        }
        return accessibilityValue
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
    static let cursorGrokBotID = "cursor.grokBot"
    static let elevenLabsCreditsID = "elevenlabs.credits"
    static let elevenLabsRemainingID = "elevenlabs.remaining"

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
            return cursorMetrics(
                connectedService.cursorUsage,
                grokBot: connectedService.cursorGrokBotUsage
            )
        case .elevenLabs:
            return elevenLabsMetrics(connectedService.elevenLabsUsage)
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
            preferred = [openAIPrimaryID, openAISecondaryID, openAIResetCreditsID]
        case .cursor:
            preferred = [cursorModelsID, cursorAPIID, cursorGrokBotID]
        case .elevenLabs:
            preferred = [elevenLabsCreditsID, elevenLabsRemainingID]
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
            // Codex now has a 5-hour session window plus a weekly window, so the
            // orbit pairs both like Claude; reset credits stay as a row below.
            return compactPair(
                primary: metrics.first(where: { $0.id == openAIPrimaryID }),
                secondary: metrics.first(where: { $0.id == openAISecondaryID })
                    ?? metrics.first(where: { $0.id == openAIResetCreditsID })
            )
        case .cursor:
            return compactPair(
                primary: metrics.first(where: { $0.id == cursorModelsID }),
                secondary: metrics.first(where: { $0.id == cursorAPIID })
            )
        case .elevenLabs:
            return compactPair(
                primary: metrics.first(where: { $0.id == elevenLabsCreditsID }),
                secondary: metrics.first(where: { $0.id == elevenLabsRemainingID })
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

    static func claudeMetrics(_ usage: UsageResponse?) -> [UsagePresentationMetric] {
        var metrics = [
            percentageMetric(
                id: claudeFiveHourID,
                label: "5-Hour Window",
                shortLabel: "5h",
                percent: usage?.fiveHour?.utilization,
                resetDate: usage?.fiveHour?.resetsAtDate,
                resetInterval: UsageWindowGeometry.claudeSessionDuration,
                geometryDuration: UsageWindowGeometry.claudeSessionDuration
            ),
            percentageMetric(
                id: claudeSevenDayID,
                label: "7-Day Window",
                shortLabel: "7d",
                percent: usage?.sevenDay?.utilization,
                resetDate: usage?.sevenDay?.resetsAtDate,
                resetInterval: UsageWindowGeometry.claudeWeeklyDuration,
                geometryDuration: UsageWindowGeometry.claudeWeeklyDuration
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
                    resetInterval: UsageWindowGeometry.claudeWeeklyDuration,
                    geometryDuration: UsageWindowGeometry.claudeWeeklyDuration
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
                    resetInterval: UsageWindowGeometry.claudeWeeklyDuration,
                    geometryDuration: UsageWindowGeometry.claudeWeeklyDuration
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
            let geometryDuration: TimeInterval?
            switch limit.group {
            case "session":
                geometryDuration = UsageWindowGeometry.claudeSessionDuration
            case "weekly":
                geometryDuration = UsageWindowGeometry.claudeWeeklyDuration
            default:
                geometryDuration = nil
            }
            metrics.append(
                percentageMetric(
                    id: "claude.limit.\(limit.id)",
                    label: label,
                    shortLabel: compactLabel(modelName),
                    percent: limit.percent,
                    resetDate: limit.resetsAtDate,
                    resetInterval: geometryDuration,
                    geometryDuration: geometryDuration
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
                    resetInterval: nil,
                    geometryDuration: nil
                )
            )
        }
        return metrics
    }

    static func openAIMetrics(
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
                resetInterval: primary?.limitWindowSeconds,
                geometryDuration: primary?.limitWindowSeconds
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
                    resetInterval: secondary?.limitWindowSeconds,
                    geometryDuration: secondary?.limitWindowSeconds
                )
            )
        }

        metrics.append(
            UsagePresentationMetric(
                id: openAIResetCreditsID,
                label: "Reset Credits",
                shortLabel: "R",
                kind: .count(count),
                resetDate: nil,
                resetInterval: nil,
                geometry: nil
            )
        )
        return metrics
    }

    /// Popover Codex metrics without the legacy reset-credit count row.
    /// The banked-credit row replaces that metric in the popover; menu-bar and
    /// widgets keep `openAIResetCreditsID` via `openAIMetrics`.
    static func openAIPopoverMetrics(
        _ metrics: [UsagePresentationMetric]
    ) -> [UsagePresentationMetric] {
        metrics.filter { $0.id != openAIResetCreditsID }
    }

    /// Codex additional rate-limit rows for the popover only. Kept out of `openAIMetrics` so the menu-bar metric picker stays unchanged.
    static func openAIAdditionalLimitMetrics(
        usage: OpenAIUsageResponse?
    ) -> [UsagePresentationMetric] {
        (usage?.additionalRateLimits ?? []).enumerated().compactMap { index, additional in
            guard let window = additional.rateLimit?.primaryWindow else { return nil }
            let label = additional.label ?? additional.type ?? "Additional Limit"
            let idSuffix = additional.type ?? additional.label ?? "\(index)"
            return percentageMetric(
                id: "openai.additional.\(idSuffix).\(index)",
                label: label,
                shortLabel: compactLabel(label),
                percent: window.usedPercent,
                resetDate: window.resetDate,
                resetInterval: window.limitWindowSeconds,
                geometryDuration: window.limitWindowSeconds
            )
        }
    }

    static func cursorMetrics(
        _ usage: CursorUsageResponse?,
        grokBot: CursorGrokBotUsageResponse? = nil
    ) -> [UsagePresentationMetric] {
        let resetDate = usage?.billingCycleEndDate
        let interval: TimeInterval = 30 * 24 * 60 * 60
        // Models and API have no window duration from the API. Grok Bot does.
        var metrics = [
            UsagePresentationMetric(
                id: cursorModelsID,
                label: "First-Party Models",
                shortLabel: "M",
                kind: .percentage(usage?.planUsage?.autoPercentUsed),
                resetDate: resetDate,
                resetInterval: interval,
                geometry: nil
            ),
            UsagePresentationMetric(
                id: cursorAPIID,
                label: "API",
                shortLabel: "API",
                kind: .percentage(usage?.planUsage?.apiPercentUsed),
                resetDate: resetDate,
                resetInterval: interval,
                geometry: nil
            ),
        ]
        // Only with a reported percent, matching the snapshot writer, so the popover and the phone agree.
        if let grokBot, grokBot.usagePercent != nil {
            metrics.append(
                percentageMetric(
                    id: cursorGrokBotID,
                    label: "Grok Bot",
                    shortLabel: "Grok",
                    percent: grokBot.usagePercent,
                    resetDate: grokBot.nextResetDate,
                    resetInterval: 7 * 24 * 60 * 60,
                    geometryDuration: grokBot.windowDuration
                )
            )
        }
        return metrics
    }

    static func elevenLabsMetrics(
        _ usage: ElevenLabsSubscriptionResponse?
    ) -> [UsagePresentationMetric] {
        [
            // No pace geometry: ElevenLabs has no even-pace window.
            UsagePresentationMetric(
                id: elevenLabsCreditsID,
                label: "Credits Used",
                shortLabel: "Used",
                kind: .percentage(usage?.utilization),
                resetDate: usage?.nextResetDate,
                resetInterval: billingInterval(for: usage?.characterRefreshPeriod),
                geometry: nil,
                drainLabel: "Credits",
                drainShortLabel: "Credits"
            ),
            UsagePresentationMetric(
                id: elevenLabsRemainingID,
                label: "Credits Remaining",
                shortLabel: "Left",
                kind: .count(usage?.creditsRemaining),
                resetDate: nil,
                resetInterval: nil,
                geometry: nil
            )
        ]
    }

    private static func billingInterval(for period: String?) -> TimeInterval? {
        switch period {
        case "daily_period": return 24 * 60 * 60
        case "weekly_period": return 7 * 24 * 60 * 60
        case "monthly_period": return 30 * 24 * 60 * 60
        case "annual_period", "yearly_period": return 365 * 24 * 60 * 60
        default: return nil
        }
    }

    private static func percentageMetric(
        id: String,
        label: String,
        shortLabel: String,
        percent: Double?,
        resetDate: Date?,
        resetInterval: TimeInterval?,
        geometryDuration: TimeInterval?
    ) -> UsagePresentationMetric {
        // Geometry whenever percent and reset are known; duration may be nil (pace/hairline stay off, restores still work).
        let geometry: UsageWindowGeometry?
        if let percent, resetDate != nil {
            geometry = UsageWindowGeometry(
                usedPercent: percent,
                resetsAt: resetDate,
                duration: geometryDuration
            )
        } else {
            geometry = nil
        }
        return UsagePresentationMetric(
            id: id,
            label: label,
            shortLabel: shortLabel,
            kind: .percentage(percent),
            resetDate: resetDate,
            resetInterval: resetInterval,
            geometry: geometry
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

/// Plain-text detail rows under each provider's bars: plan, tier, renewal, credits, credential source.
/// Every helper returns nil when its data is absent so the row hides instead of showing a blank.
enum UsageDetailRows {
    /// "3 banked · next expires in 10d 22h"; nil at zero.
    static func resetCreditsLine(count: Int, nextExpiry: Date?, now: Date = Date()) -> String? {
        guard count > 0 else { return nil }
        var line = "\(count) banked"
        if let nextExpiry {
            line += " · next expires in \(UsagePace.formatDuration(nextExpiry.timeIntervalSince(now)))"
        }
        return line
    }

    /// "Plan: Plus" from Codex `plan_type`.
    static func codexPlanLine(planType: String?) -> String? {
        guard let planType, let first = planType.first else { return nil }
        return "Plan: " + first.uppercased() + planType.dropFirst()
    }

    /// "Source: Codex CLI login · expires in 4d" or "Source: pasted token". Never carries the token.
    static func codexSourceLine(
        source: OpenAICredentialSource,
        tokenExpiry: Date?,
        now: Date = Date()
    ) -> String? {
        switch source {
        case .none: return nil
        case .pasted: return "Source: pasted token"
        case .environment: return "Source: environment variable"
        case .codexCLI: return sourceLine("Codex CLI login", expiry: tokenExpiry, now: now)
        }
    }

    /// "Source: Cursor CLI login · expires in 9d" or "Source: pasted cookie". Never carries the cookie.
    static func cursorSourceLine(
        source: CursorCredentialSource,
        tokenExpiry: Date?,
        now: Date = Date()
    ) -> String? {
        switch source {
        case .none: return nil
        case .pasted: return "Source: pasted cookie"
        case .environment: return "Source: environment variable"
        case .cursorCLI: return sourceLine("Cursor CLI login", expiry: tokenExpiry, now: now)
        }
    }

    /// "Pro · $20/mo · renews in 12d"; parts drop out as their fields are absent.
    static func cursorPlanLine(_ planInfo: CursorPlanInfo?, now: Date = Date()) -> String? {
        guard let planInfo else { return nil }
        var parts: [String] = []
        if let name = planInfo.planName, !name.isEmpty {
            parts.append(name)
        }
        if let price = planInfo.price, !price.isEmpty {
            parts.append(price)
        }
        if let raw = planInfo.billingCycleEnd, let milliseconds = Double(raw) {
            let renewsAt = Date(timeIntervalSince1970: milliseconds / 1_000)
            let delta = renewsAt.timeIntervalSince(now)
            parts.append(
                delta >= 0
                    ? "renews in \(coarseDuration(delta))"
                    : "renewed \(coarseDuration(-delta)) ago"
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "used $4.06 of $20.00": the plan's included amount times the total percent used (same math as Android).
    static func cursorSpendLine(planUsage: CursorPlanUsage?, includedAmountCents: Int?) -> String? {
        guard let cents = includedAmountCents, cents >= 0,
              let percent = planUsage?.totalPercentUsed else { return nil }
        let limit = Double(cents) / 100
        let used = limit * (percent / 100)
        return "used \(ExtraUsage.formatUSD(used)) of \(ExtraUsage.formatUSD(limit))"
    }

    /// "Max 20x · active"; nil when both parts are blank.
    static func claudePlanLine(planLabel: String?, subscriptionStatus: String?) -> String? {
        let parts = [planLabel, subscriptionStatus]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func sourceLine(_ name: String, expiry: Date?, now: Date) -> String {
        guard let expiry else { return "Source: \(name)" }
        let delta = expiry.timeIntervalSince(now)
        return delta > 0
            ? "Source: \(name) · expires in \(coarseDuration(delta))"
            : "Source: \(name) · expired"
    }

    /// One unit only, the way T3 and the Android caption show renewal and login expiry: `12d`, `9h`, `40m`.
    static func coarseDuration(_ interval: TimeInterval) -> String {
        let remaining = max(0, interval)
        if remaining >= 86_400 {
            return "\(Int(remaining / 86_400))d"
        }
        if remaining >= 3_600 {
            return "\(Int(remaining / 3_600))h"
        }
        return "\(Int(remaining / 60))m"
    }
}
