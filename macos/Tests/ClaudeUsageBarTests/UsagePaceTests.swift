import XCTest
@testable import AgentUsageBar

final class UsagePaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testElapsedShareAtMidWindow() {
        let duration: TimeInterval = 10 * 60 * 60
        let window = UsageWindowGeometry(
            usedPercent: 40,
            resetsAt: now.addingTimeInterval(5 * 60 * 60),
            duration: duration
        )
        XCTAssertEqual(UsagePace.elapsedShare(window, now: now), 0.5)
    }

    func testElapsedShareClampsBelowZeroAndAboveOne() {
        let duration: TimeInterval = 5 * 60 * 60
        let beforeStart = UsageWindowGeometry(
            usedPercent: 0,
            resetsAt: now.addingTimeInterval(duration + 60 * 60),
            duration: duration
        )
        XCTAssertEqual(UsagePace.elapsedShare(beforeStart, now: now), 0)

        let afterReset = UsageWindowGeometry(
            usedPercent: 100,
            resetsAt: now.addingTimeInterval(-60),
            duration: duration
        )
        XCTAssertEqual(UsagePace.elapsedShare(afterReset, now: now), 1)
    }

    func testElapsedShareNilWhenDurationOrResetMissingOrNonPositive() {
        XCTAssertNil(
            UsagePace.elapsedShare(
                UsageWindowGeometry(usedPercent: 10, resetsAt: nil, duration: 3600),
                now: now
            )
        )
        XCTAssertNil(
            UsagePace.elapsedShare(
                UsageWindowGeometry(usedPercent: 10, resetsAt: now.addingTimeInterval(60), duration: nil),
                now: now
            )
        )
        XCTAssertNil(
            UsagePace.elapsedShare(
                UsageWindowGeometry(usedPercent: 10, resetsAt: now.addingTimeInterval(60), duration: 0),
                now: now
            )
        )
        XCTAssertNil(
            UsagePace.elapsedShare(
                UsageWindowGeometry(usedPercent: 10, resetsAt: now.addingTimeInterval(60), duration: -1),
                now: now
            )
        )
    }

    func testPaceBandsAtBoundaries() {
        // Mid-window elapsed = 50. gap = used - 50.
        let duration: TimeInterval = 10 * 60 * 60
        let resetsAt = now.addingTimeInterval(5 * 60 * 60)

        let onLow = UsageWindowGeometry(usedPercent: 45, resetsAt: resetsAt, duration: duration)
        XCTAssertEqual(UsagePace.pace(onLow, now: now), .on)

        let onHigh = UsageWindowGeometry(usedPercent: 55, resetsAt: resetsAt, duration: duration)
        XCTAssertEqual(UsagePace.pace(onHigh, now: now), .on)

        let ahead = UsageWindowGeometry(usedPercent: 55.000_1, resetsAt: resetsAt, duration: duration)
        XCTAssertEqual(UsagePace.pace(ahead, now: now), .ahead)

        let under = UsageWindowGeometry(usedPercent: 44.999_9, resetsAt: resetsAt, duration: duration)
        XCTAssertEqual(UsagePace.pace(under, now: now), .under)
    }

    func testPaceNilWhenElapsedUnknown() {
        let window = UsageWindowGeometry(usedPercent: 80, resetsAt: nil, duration: 3600)
        XCTAssertNil(UsagePace.pace(window, now: now))
    }

    func testFormatDurationThreeShapes() {
        XCTAssertEqual(UsagePace.formatDuration(5 * 86_400 + 3 * 3_600), "5d 3h")
        XCTAssertEqual(UsagePace.formatDuration(2 * 3_600 + 13 * 60), "2h 13m")
        XCTAssertEqual(UsagePace.formatDuration(12 * 60), "12m")
    }

    func testFormatDurationFloorsUnitsOmitsLowerWhenDaysAndNeverNegative() {
        XCTAssertEqual(UsagePace.formatDuration(5 * 86_400 + 3 * 3_600 + 59 * 60), "5d 3h")
        XCTAssertEqual(UsagePace.formatDuration(86_400), "1d 0h")
        XCTAssertEqual(UsagePace.formatDuration(3_600 + 59.9), "1h 0m")
        XCTAssertEqual(UsagePace.formatDuration(-90), "0m")
        XCTAssertEqual(UsagePace.formatDuration(0), "0m")
    }

    func testRestoresLineFuturePastAndMissing() {
        let future = UsageWindowGeometry(
            usedPercent: 32.4,
            resetsAt: now.addingTimeInterval(5 * 86_400 + 3 * 3_600),
            duration: UsageWindowGeometry.claudeWeeklyDuration
        )
        XCTAssertEqual(UsagePace.restoresLine(future, now: now), "+32% in 5d 3h")

        let past = UsageWindowGeometry(
            usedPercent: 40,
            resetsAt: now.addingTimeInterval(-1),
            duration: 3600
        )
        XCTAssertEqual(UsagePace.restoresLine(past, now: now), "resets now")

        let missing = UsageWindowGeometry(usedPercent: 40, resetsAt: nil, duration: 3600)
        XCTAssertNil(UsagePace.restoresLine(missing, now: now))
    }

    func testRestoresLineIsNilWhenNothingWouldBeRestored() {
        let fresh = UsageWindowGeometry(
            usedPercent: 0,
            resetsAt: now.addingTimeInterval(4 * 3_600 + 12 * 60),
            duration: UsageWindowGeometry.claudeSessionDuration
        )
        XCTAssertNil(UsagePace.restoresLine(fresh, now: now))

        let roundsToZero = UsageWindowGeometry(
            usedPercent: 0.4,
            resetsAt: now.addingTimeInterval(3_600),
            duration: UsageWindowGeometry.claudeSessionDuration
        )
        XCTAssertNil(UsagePace.restoresLine(roundsToZero, now: now))

        let roundsToOne = UsageWindowGeometry(
            usedPercent: 0.5,
            resetsAt: now.addingTimeInterval(3_600),
            duration: UsageWindowGeometry.claudeSessionDuration
        )
        XCTAssertEqual(UsagePace.restoresLine(roundsToOne, now: now), "+1% in 1h 0m")
    }

    func testGeometryEqualityCoversEveryField() {
        let base = UsageWindowGeometry(usedPercent: 10, resetsAt: now, duration: 3600)
        XCTAssertEqual(base, UsageWindowGeometry(usedPercent: 10, resetsAt: now, duration: 3600))
        XCTAssertNotEqual(base, UsageWindowGeometry(usedPercent: 11, resetsAt: now, duration: 3600))
        XCTAssertNotEqual(base, UsageWindowGeometry(usedPercent: 10, resetsAt: now.addingTimeInterval(1), duration: 3600))
        XCTAssertNotEqual(base, UsageWindowGeometry(usedPercent: 10, resetsAt: now, duration: 7200))
    }

    func testRemainingPercentClampsAndRounds() {
        XCTAssertEqual(UsagePace.remainingPercent(32.4), 68)
        XCTAssertEqual(UsagePace.remainingPercent(-5), 100)
        XCTAssertEqual(UsagePace.remainingPercent(150), 0)
        XCTAssertEqual(UsagePace.remainingPercent(50.5), 50)
    }

    func testDefaultClaudeDurations() {
        XCTAssertEqual(UsageWindowGeometry.claudeSessionDuration, 5 * 60 * 60)
        XCTAssertEqual(UsageWindowGeometry.claudeWeeklyDuration, 7 * 24 * 60 * 60)
    }
}
