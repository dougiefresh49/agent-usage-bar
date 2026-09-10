import Foundation

/// One usage window's inputs for elapsed, pace, and restore presentation math.
struct UsageWindowGeometry: Equatable {
    var usedPercent: Double
    var resetsAt: Date?
    var duration: TimeInterval?

    /// Claude five-hour session window length for callers that do not get a duration from the API.
    static let claudeSessionDuration: TimeInterval = 5 * 60 * 60

    /// Claude seven-day window length for callers that do not get a duration from the API.
    static let claudeWeeklyDuration: TimeInterval = 7 * 24 * 60 * 60
}

/// Usage against the clock for a single window, plus the pure helpers that derive it.
enum UsagePace {
    case ahead
    case on
    case under

    /// Elapsed share of the window, 0...1, or nil when duration or reset is missing or duration is not positive.
    static func elapsedShare(_ window: UsageWindowGeometry, now: Date) -> Double? {
        guard let resetsAt = window.resetsAt, let duration = window.duration, duration > 0 else {
            return nil
        }
        let raw = (duration - resetsAt.timeIntervalSince(now)) / duration
        return min(1, max(0, raw))
    }

    /// Spending versus even pace. Gap of usedPercent minus elapsed times 100: above +5 is ahead, below -5 is under, else on.
    static func pace(_ window: UsageWindowGeometry, now: Date) -> UsagePace? {
        guard let elapsed = elapsedShare(window, now: now) else {
            return nil
        }
        let gap = window.usedPercent - elapsed * 100
        if gap > 5 { return .ahead }
        if gap < -5 { return .under }
        return .on
    }

    /// Countdown copy matching T3: `5d 3h`, `2h 13m`, `12m`. Days omit minutes; never negative.
    static func formatDuration(_ interval: TimeInterval) -> String {
        let remaining = max(0, interval)
        let days = Int(remaining / 86_400)
        let hours = Int(remaining.truncatingRemainder(dividingBy: 86_400) / 3_600)
        let minutes = Int(remaining.truncatingRemainder(dividingBy: 3_600) / 60)
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// What the next reset restores: `+32% in 5d 3h`, or `resets now` when the reset is in the past.
    /// Nil when nothing has been used yet, so a fresh window shows no `+0%` line.
    static func restoresLine(_ window: UsageWindowGeometry, now: Date) -> String? {
        guard let resetsAt = window.resetsAt else {
            return nil
        }
        let restored = Int(window.usedPercent.rounded(.toNearestOrAwayFromZero))
        guard restored > 0 else {
            return nil
        }
        if resetsAt <= now {
            return "resets now"
        }
        return "+\(restored)% in \(formatDuration(resetsAt.timeIntervalSince(now)))"
    }

    /// Quota left in the window, 0...100.
    static func remainingPercent(_ usedPercent: Double) -> Int {
        let clamped = min(100, max(0, usedPercent))
        return Int((100 - clamped).rounded(.toNearestOrAwayFromZero))
    }
}
