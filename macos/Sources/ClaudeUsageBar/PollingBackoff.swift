import Foundation

/// Shared polling helpers for Claude (`UsageService`) and connected providers
/// (`ConnectedUsageService`): 429 backoff, debounce, timeouts, low-power interval.
enum PollingBackoff {
    static let maxInterval: TimeInterval = 60 * 60
    /// Skip a scheduled poll when the last successful fetch is newer than this.
    static let debounceInterval: TimeInterval = 60
    static let usageRequestTimeout: TimeInterval = 15
    /// Credits, plan, profile, and other non-usage provider calls.
    static let secondaryRequestTimeout: TimeInterval = 10

    nonisolated static func backoffInterval(
        retryAfter: TimeInterval?,
        currentInterval: TimeInterval
    ) -> TimeInterval {
        min(max(retryAfter ?? currentInterval, currentInterval * 2), maxInterval)
    }

    nonisolated static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
    }

    nonisolated static func pollingInterval(
        minutes: Int,
        isLowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    ) -> TimeInterval {
        let base = TimeInterval(minutes * 60)
        return isLowPower ? base * 2 : base
    }

    /// Scheduled polls only. Manual refresh, wake, and start always run.
    nonisolated static func shouldSkipScheduledPoll(
        lastSuccessfulFetch: Date?,
        now: Date = Date(),
        debounce: TimeInterval = debounceInterval
    ) -> Bool {
        guard let lastSuccessfulFetch else { return false }
        return now.timeIntervalSince(lastSuccessfulFetch) < debounce
    }

    nonisolated static func shouldSkipForBackoff(
        until backoffUntil: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let backoffUntil else { return false }
        return now < backoffUntil
    }
}
