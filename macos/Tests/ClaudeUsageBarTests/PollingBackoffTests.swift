import XCTest
@testable import AgentUsageBar

final class PollingBackoffTests: XCTestCase {
    func testBackoffIntervalCapsAtSixtyMinutes() {
        XCTAssertEqual(
            PollingBackoff.backoffInterval(retryAfter: 120, currentInterval: 30 * 60),
            60 * 60
        )
    }

    func testBackoffIntervalWithoutRetryAfterDoublesCurrent() {
        XCTAssertEqual(
            PollingBackoff.backoffInterval(retryAfter: nil, currentInterval: 5 * 60),
            10 * 60
        )
    }

    func testBackoffIntervalHonoursRetryAfterWhenLargerThanDouble() {
        XCTAssertEqual(
            PollingBackoff.backoffInterval(retryAfter: 900, currentInterval: 5 * 60),
            900
        )
    }

    func testBackoffIntervalNeverReducesSixtyMinutePolling() {
        XCTAssertEqual(
            PollingBackoff.backoffInterval(retryAfter: 120, currentInterval: 60 * 60),
            60 * 60
        )
    }

    func testDebounceSkipsWhenLastFetchIsFresh() {
        let now = Date()
        XCTAssertTrue(
            PollingBackoff.shouldSkipScheduledPoll(
                lastSuccessfulFetch: now.addingTimeInterval(-30),
                now: now
            )
        )
        XCTAssertFalse(
            PollingBackoff.shouldSkipScheduledPoll(
                lastSuccessfulFetch: now.addingTimeInterval(-90),
                now: now
            )
        )
        XCTAssertFalse(
            PollingBackoff.shouldSkipScheduledPoll(lastSuccessfulFetch: nil, now: now)
        )
    }

    func testLowPowerDoublesPollingInterval() {
        XCTAssertEqual(
            PollingBackoff.pollingInterval(minutes: 15, isLowPower: false),
            15 * 60
        )
        XCTAssertEqual(
            PollingBackoff.pollingInterval(minutes: 15, isLowPower: true),
            30 * 60
        )
    }

    func testRetryAfterParsesHeader() throws {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "42"]
            )
        )
        XCTAssertEqual(PollingBackoff.retryAfterSeconds(from: response), 42)
    }

    func testRetryAfterParsesHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let headerDate = now.addingTimeInterval(120)
        let header = formatter.string(from: headerDate)

        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": header]
            )
        )
        let delay = try XCTUnwrap(
            PollingBackoff.retryAfterSeconds(from: response, now: now)
        )
        XCTAssertEqual(delay, 120, accuracy: 0.5)
        XCTAssertEqual(
            PollingBackoff.retryAfterSeconds(from: response, now: headerDate.addingTimeInterval(1)),
            0,
            "Past HTTP-date clamps to zero rather than a negative delay"
        )
    }

    func testTimeoutConstants() {
        XCTAssertEqual(PollingBackoff.usageRequestTimeout, 15)
        XCTAssertEqual(PollingBackoff.secondaryRequestTimeout, 10)
    }
}
