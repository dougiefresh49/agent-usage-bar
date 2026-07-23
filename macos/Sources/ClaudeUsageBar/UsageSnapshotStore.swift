import Foundation

/// One usage metric (a rate-limit window or spend bucket) in the on-disk snapshot.
struct UsageSnapshotMetric: Codable, Equatable {
    let id: String
    let label: String
    let percentUsed: Double?
    let resetsAt: Date?
}

struct UsageSnapshotProvider: Codable, Equatable {
    let updatedAt: Date
    let metrics: [UsageSnapshotMetric]
}

struct UsageSnapshot: Codable, Equatable {
    var version = 1
    var generatedAt: Date
    var providers: [String: UsageSnapshotProvider]
}

/// Persists the latest usage numbers for every provider to a JSON file that
/// external tools (agent skills, scripts) can read without talking to the
/// provider APIs themselves. See skills/ai-usage in the repo.
@MainActor
final class UsageSnapshotStore {
    nonisolated static let defaultDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AgentUsageBar", isDirectory: true)

    let fileURL: URL
    private var providers: [String: UsageSnapshotProvider] = [:]
    private let now: () -> Date

    init(
        directory: URL = UsageSnapshotStore.defaultDirectory,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = directory.appendingPathComponent("usage-snapshot.json")
        self.now = now
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

    private func write() {
        let snapshot = UsageSnapshot(generatedAt: now(), providers: providers)
        guard let data = try? Self.makeEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
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
                percentUsed: usage.fiveHour?.utilization,
                resetsAt: usage.fiveHour?.resetsAtDate
            ),
            UsageSnapshotMetric(
                id: "seven_day",
                label: "7-day window",
                percentUsed: usage.sevenDay?.utilization,
                resetsAt: usage.sevenDay?.resetsAtDate
            ),
        ]
        if let opus = usage.sevenDayOpus, opus.utilization != nil {
            metrics.append(UsageSnapshotMetric(
                id: "seven_day_opus",
                label: "Opus 7-day window",
                percentUsed: opus.utilization,
                resetsAt: opus.resetsAtDate
            ))
        }
        if let sonnet = usage.sevenDaySonnet, sonnet.utilization != nil {
            metrics.append(UsageSnapshotMetric(
                id: "seven_day_sonnet",
                label: "Sonnet 7-day window",
                percentUsed: sonnet.utilization,
                resetsAt: sonnet.resetsAtDate
            ))
        }
        if let extra = usage.extraUsage, extra.utilization != nil {
            metrics.append(UsageSnapshotMetric(
                id: "extra_usage",
                label: "Extra usage (monthly credits)",
                percentUsed: extra.utilization,
                resetsAt: nil
            ))
        }
        return metrics
    }

    nonisolated static func openAIMetrics(for usage: OpenAIUsageResponse) -> [UsageSnapshotMetric] {
        var metrics: [UsageSnapshotMetric] = []
        if let primary = usage.rateLimit?.primaryWindow {
            metrics.append(UsageSnapshotMetric(
                id: "primary",
                label: windowLabel(primary.limitWindowSeconds, fallback: "Primary window"),
                percentUsed: primary.usedPercent,
                resetsAt: primary.resetDate
            ))
        }
        if let secondary = usage.rateLimit?.secondaryWindow {
            metrics.append(UsageSnapshotMetric(
                id: "secondary",
                label: windowLabel(secondary.limitWindowSeconds, fallback: "Secondary window"),
                percentUsed: secondary.usedPercent,
                resetsAt: secondary.resetDate
            ))
        }
        return metrics
    }

    nonisolated static func cursorMetrics(for usage: CursorUsageResponse) -> [UsageSnapshotMetric] {
        var metrics = [
            UsageSnapshotMetric(
                id: "models",
                label: "First-party models",
                percentUsed: usage.planUsage?.autoPercentUsed,
                resetsAt: usage.billingCycleEndDate
            ),
            UsageSnapshotMetric(
                id: "api",
                label: "API",
                percentUsed: usage.planUsage?.apiPercentUsed,
                resetsAt: usage.billingCycleEndDate
            ),
        ]
        if let spend = usage.spendLimitUsage, spend.utilization != nil {
            metrics.append(UsageSnapshotMetric(
                id: "on_demand",
                label: "On-demand spend",
                percentUsed: spend.utilization,
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
                percentUsed: usage.utilization,
                resetsAt: usage.nextResetDate
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
}
