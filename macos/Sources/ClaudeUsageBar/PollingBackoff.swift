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

    /// Who asked for a refresh. Manual is the only path that may ignore backoff.
    enum Trigger: Equatable {
        /// Timer tick: debounce and backoff both apply.
        case scheduled
        /// Popover open, wake, start, skill: skip debounce, still honour backoff.
        case automatic
        /// Explicit Refresh control: always runs (single-flight still applies).
        case manual

        var skipsDebounce: Bool { self != .scheduled }
        var skipsBackoff: Bool { self == .manual }
    }

    nonisolated static func backoffInterval(
        retryAfter: TimeInterval?,
        currentInterval: TimeInterval
    ) -> TimeInterval {
        min(max(retryAfter ?? currentInterval, currentInterval * 2), maxInterval)
    }

    /// Parses `Retry-After` as delay-seconds or an HTTP-date (IMF-fixdate).
    /// - Parameter now: injected for deterministic HTTP-date tests.
    nonisolated static func retryAfterSeconds(
        from response: HTTPURLResponse,
        now: Date = Date()
    ) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }

        if let seconds = TimeInterval(raw) {
            return max(0, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    nonisolated static func pollingInterval(
        minutes: Int,
        isLowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    ) -> TimeInterval {
        let base = TimeInterval(minutes * 60)
        return isLowPower ? base * 2 : base
    }

    /// Scheduled polls only. Automatic and manual skip this gate.
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
