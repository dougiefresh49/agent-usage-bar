import Foundation
import WidgetKit

/// One usage metric (a rate-limit window or spend bucket) in the on-disk snapshot.
struct UsageSnapshotMetric: Codable, Equatable {
    let id: String
    let label: String
    let shortLabel: String?
    let percentUsed: Double?
    let count: Int?
    let valueText: String?
    let resetsAt: Date?
    let resetInterval: TimeInterval?

    init(
        id: String,
        label: String,
        shortLabel: String? = nil,
        percentUsed: Double?,
        count: Int? = nil,
        valueText: String? = nil,
        resetsAt: Date?,
        resetInterval: TimeInterval? = nil
    ) {
        self.id = id
        self.label = label
        self.shortLabel = shortLabel
        self.percentUsed = percentUsed
        self.count = count
        self.valueText = valueText
        self.resetsAt = resetsAt
        self.resetInterval = resetInterval
    }
}

struct UsageSnapshotProvider: Codable, Equatable {
    let updatedAt: Date
    let metrics: [UsageSnapshotMetric]
}

struct UsageSnapshotPreferences: Codable, Equatable {
    let preferredProvider: String
    let detailStyle: String
}

struct UsageSnapshot: Codable, Equatable {
    var version = 2
    var generatedAt: Date
    var providers: [String: UsageSnapshotProvider]
    var preferences: UsageSnapshotPreferences?
}

/// Persists the latest usage numbers for every provider to a JSON file that
/// external tools (agent skills, scripts) can read without talking to the
/// provider APIs themselves. See skills/ai-usage in the repo.
@MainActor
final class UsageSnapshotStore {
    nonisolated static let defaultDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AgentUsageBar", isDirectory: true)

    nonisolated static let widgetBundleIdentifier = "com.local.AgentUsageBar.Widget"

    /// Widget extensions are sandboxed. The menu app is not, so it can mirror the
    /// snapshot into the extension's own Application Support container without
    /// requiring an App Group entitlement or a registered developer team.
    nonisolated static let defaultWidgetDirectory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers", isDirectory: true)
        .appendingPathComponent(widgetBundleIdentifier, isDirectory: true)
        .appendingPathComponent("Data/Library/Application Support/AgentUsageBar", isDirectory: true)

    let fileURL: URL
    let widgetFileURL: URL?
    private var providers: [String: UsageSnapshotProvider] = [:]
    private let now: () -> Date
    private let defaults: UserDefaults
    private let reloadWidgets: () -> Void

    init(
        directory: URL? = nil,
        widgetDirectory: URL? = nil,
        now: @escaping () -> Date = Date.init,
        defaults: UserDefaults = .standard,
        reloadWidgets: (() -> Void)? = nil
    ) {
        let resolvedDirectory = directory ?? UsageSnapshotStore.defaultDirectory
        let resolvedWidgetDirectory = widgetDirectory
            ?? (directory == nil ? UsageSnapshotStore.defaultWidgetDirectory : nil)
        self.fileURL = resolvedDirectory.appendingPathComponent("usage-snapshot.json")
        self.widgetFileURL = resolvedWidgetDirectory?
            .appendingPathComponent("usage-snapshot.json")
        self.now = now
        self.defaults = defaults
        self.reloadWidgets = reloadWidgets
            ?? (directory == nil
                ? { WidgetCenter.shared.reloadAllTimelines() }
                : {})
        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? Self.makeDecoder().decode(UsageSnapshot.self, from: data) {
            providers = snapshot.providers
        }
    }

    func update(provider: String, metrics: [UsageSnapshotMetric]) {
        providers[provider] = UsageSnapshotProvider(updatedAt: now(), metrics: metrics)
        write()
    }

    func remove(provider: String) {
        guard providers.removeValue(forKey: provider) != nil else { return }
        write()
    }

    func refreshPreferences() {
        write()
    }

    private func write() {
        let snapshot = UsageSnapshot(
            generatedAt: now(),
            providers: providers,
            preferences: UsageSnapshotPreferences(
                preferredProvider: defaults.string(
                    forKey: UsagePresentationDefaults.menuBarProviderKey
                ) ?? UsagePresentationDefaults.menuBarProvider.rawValue,
                detailStyle: defaults.string(
                    forKey: UsagePresentationDefaults.detailStyleKey
                ) ?? UsagePresentationDefaults.detailStyle.rawValue
            )
        )
        guard let data = try? Self.makeEncoder().encode(snapshot) else { return }
        write(data, to: fileURL)
        if let widgetFileURL {
            write(data, to: widgetFileURL)
        }
        reloadWidgets()
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Metric builders

extension UsageSnapshotStore {
    nonisolated static func claudeMetrics(for usage: UsageResponse) -> [UsageSnapshotMetric] {
        var metrics = [
            UsageSnapshotMetric(
                id: "five_hour",
                label: "5-hour window",
                shortLabel: "5h",
                percentUsed: usage.fiveHour?.utilization,
                resetsAt: usage.fiveHour?.resetsAtDate,
                resetInterval: 5 * 60 * 60
            ),
            UsageSnapshotMetric(
                id: "seven_day",
                label: "7-day window",
                shortLabel: "7d",
                percentUsed: usage.sevenDay?.utilization,
                resetsAt: usage.sevenDay?.resetsAtDate,
                resetInterval: 7 * 24 * 60 * 60
            ),
        ]
        if let opus = usage.sevenDayOpus, opus.utilization != nil {
            metrics.append(UsageSnapshotMetric(
                id: "seven_day_opus",
                label: "Opus 7-day window",
                shortLabel: "Op",
                percentUsed: opus.utilization,
                resetsAt: opus.resetsAtDate,
                resetInterval: 7 * 24 * 60 * 60
            ))
        }
        if let sonnet = usage.sevenDaySonnet, sonnet.utilization != nil {
            metrics.append(UsageSnapshotMetric(
                id: "seven_day_sonnet",
                label: "Sonnet 7-day window",
                shortLabel: "Sn",
                percentUsed: sonnet.utilization,
                resetsAt: sonnet.resetsAtDate,
                resetInterval: 7 * 24 * 60 * 60
            ))
        }
        for limit in usage.scopedModelLimits {
            let modelName = limit.scope?.model?.displayName ?? "Model"
            let groupLabel: String
            switch limit.group {
            case "weekly": groupLabel = "7 day"
            case "session": groupLabel = "session"
            case let group?: groupLabel = group.replacingOccurrences(of: "_", with: " ")
            case nil: groupLabel = ""
            }
            metrics.append(UsageSnapshotMetric(
                id: "limit.\(limit.id)",
                label: groupLabel.isEmpty ? modelName : "\(modelName) (\(groupLabel))",
                shortLabel: String(modelName.prefix(2)),
                percentUsed: limit.percent,
                resetsAt: limit.resetsAtDate,
                resetInterval: limit.group == "session"
                    ? 5 * 60 * 60
                    : 7 * 24 * 60 * 60
            ))
        }
        if let extra = usage.extraUsage, extra.utilization != nil {
            let valueText: String?
            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                valueText = "\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))"
            } else {
                valueText = extra.usedCreditsAmount.map(ExtraUsage.formatUSD)
            }
            metrics.append(UsageSnapshotMetric(
                id: "extra_usage",
                label: "Extra usage (monthly credits)",
                shortLabel: "Ex",
                percentUsed: extra.utilization,
                valueText: valueText,
                resetsAt: nil
            ))
        }
        return metrics
    }

    nonisolated static func openAIMetrics(
        for usage: OpenAIUsageResponse,
        resetCredits: OpenAIResetCreditsResponse? = nil
    ) -> [UsageSnapshotMetric] {
        var metrics: [UsageSnapshotMetric] = []
        if let primary = usage.rateLimit?.primaryWindow {
            metrics.append(UsageSnapshotMetric(
                id: "primary",
                label: windowLabel(primary.limitWindowSeconds, fallback: "Primary window"),
                shortLabel: compactWindowLabel(primary.limitWindowSeconds, fallback: "Wk"),
                percentUsed: primary.usedPercent,
                resetsAt: primary.resetDate,
                resetInterval: primary.limitWindowSeconds
            ))
        }
        let availableResetCredits = resetCredits?.availableCount
            ?? resetCredits.map { $0.credits.filter(\.isAvailable).count }
            ?? usage.rateLimitResetCredits?.applicableAvailableCount
            ?? usage.rateLimitResetCredits?.availableCount
        metrics.append(UsageSnapshotMetric(
            id: "reset_credits",
            label: "Reset credits",
            shortLabel: "R",
            percentUsed: nil,
            count: availableResetCredits,
            resetsAt: nil
        ))
        if let secondary = usage.rateLimit?.secondaryWindow {
            metrics.append(UsageSnapshotMetric(
                id: "secondary",
                label: windowLabel(secondary.limitWindowSeconds, fallback: "Secondary window"),
                shortLabel: compactWindowLabel(secondary.limitWindowSeconds, fallback: "2nd"),
                percentUsed: secondary.usedPercent,
                resetsAt: secondary.resetDate,
                resetInterval: secondary.limitWindowSeconds
            ))
        }
        return metrics
    }

    nonisolated static func cursorMetrics(for usage: CursorUsageResponse) -> [UsageSnapshotMetric] {
        var metrics = [
            UsageSnapshotMetric(
                id: "models",
                label: "First-party models",
                shortLabel: "M",
                percentUsed: usage.planUsage?.autoPercentUsed,
                resetsAt: usage.billingCycleEndDate,
                resetInterval: 30 * 24 * 60 * 60
            ),
            UsageSnapshotMetric(
                id: "api",
                label: "API",
                shortLabel: "API",
                percentUsed: usage.planUsage?.apiPercentUsed,
                resetsAt: usage.billingCycleEndDate,
                resetInterval: 30 * 24 * 60 * 60
            ),
        ]
        if usage.planUsage?.totalPercentUsed != nil {
            metrics.append(UsageSnapshotMetric(
                id: "total",
                label: "Total usage",
                shortLabel: "T",
                percentUsed: usage.planUsage?.totalPercentUsed,
                resetsAt: usage.billingCycleEndDate,
                resetInterval: 30 * 24 * 60 * 60
            ))
        }
        if let spend = usage.spendLimitUsage, spend.utilization != nil {
            metrics.append(UsageSnapshotMetric(
                id: "on_demand",
                label: "On-demand spend",
                shortLabel: "$",
                percentUsed: spend.utilization,
                valueText: spend.spent.map(UsageMoney.minorUnits),
                resetsAt: usage.billingCycleEndDate
            ))
        }
        return metrics
    }

    nonisolated static func elevenLabsMetrics(
        for usage: ElevenLabsSubscriptionResponse
    ) -> [UsageSnapshotMetric] {
        [
            UsageSnapshotMetric(
                id: "credits",
                label: "Credits used",
                shortLabel: "Used",
                percentUsed: usage.utilization,
                resetsAt: usage.nextResetDate,
                resetInterval: 30 * 24 * 60 * 60
            ),
            UsageSnapshotMetric(
                id: "remaining",
                label: "Credits remaining",
                shortLabel: "Left",
                percentUsed: nil,
                count: usage.creditsRemaining,
                resetsAt: usage.nextResetDate,
                resetInterval: 30 * 24 * 60 * 60
            )
        ]
    }

    nonisolated private static func windowLabel(_ seconds: Double?, fallback: String) -> String {
        guard let seconds else { return fallback }
        let hours = Int(seconds / 3_600)
        if hours > 0, hours % 24 == 0 {
            return "\(hours / 24)-day window"
        }
        if hours > 0 {
            return "\(hours)-hour window"
        }
        return fallback
    }

    nonisolated private static func compactWindowLabel(
        _ seconds: Double?,
        fallback: String
    ) -> String {
        guard let seconds else { return fallback }
        let hours = Int(seconds / 3_600)
        if hours > 0, hours % (24 * 7) == 0 {
            return "\(hours / (24 * 7))w"
        }
        if hours > 0, hours % 24 == 0 {
            return "\(hours / 24)d"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return fallback
    }
}
