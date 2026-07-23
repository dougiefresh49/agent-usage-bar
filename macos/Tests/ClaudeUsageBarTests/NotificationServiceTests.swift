import XCTest
@testable import AgentUsageBar

final class NotificationServiceTests: XCTestCase {
    func testNoAlertsWhenOff() {
        let alert = crossedPercentageThreshold(
            threshold: 0,
            previous: 40,
            current: 90,
            provider: "Claude",
            window: "Session"
        )
        XCTAssertNil(alert)
    }

    func testPercentageFiresWhenCrossing() {
        let alert = crossedPercentageThreshold(
            threshold: 80,
            previous: 70,
            current: 85,
            provider: "Claude",
            window: "Session"
        )
        XCTAssertEqual(
            alert,
            ThresholdAlert(provider: "Claude", window: "Session", valueText: "85%")
        )
    }

    func testPercentageDoesNotFireWhenStayingAbove() {
        let alert = crossedPercentageThreshold(
            threshold: 80,
            previous: 85,
            current: 88,
            provider: "Cursor",
            window: "API"
        )
        XCTAssertNil(alert)
    }

    func testPercentageDoesNotFireWhenStayingBelow() {
        let alert = crossedPercentageThreshold(
            threshold: 80,
            previous: 50,
            current: 70,
            provider: "Codex",
            window: "Weekly usage"
        )
        XCTAssertNil(alert)
    }

    func testExactPercentageThresholdTriggers() {
        let alert = crossedPercentageThreshold(
            threshold: 80,
            previous: 79,
            current: 80,
            provider: "Claude",
            window: "Seven-day"
        )
        XCTAssertEqual(
            alert,
            ThresholdAlert(provider: "Claude", window: "Seven-day", valueText: "80%")
        )
    }

    func testFirstPollFiresWhenAlreadyAboveThreshold() {
        let alert = crossedPercentageThreshold(
            threshold: 25,
            previous: 0,
            current: 60,
            provider: "Claude",
            window: "Fable"
        )
        XCTAssertEqual(
            alert,
            ThresholdAlert(provider: "Claude", window: "Fable", valueText: "60%")
        )
    }

    func testCountFiresWhenDroppingToThreshold() {
        let alert = crossedCountThreshold(
            threshold: 1,
            previous: 2,
            current: 1,
            provider: "Codex",
            window: "Reset credits"
        )
        XCTAssertEqual(
            alert,
            ThresholdAlert(
                provider: "Codex",
                window: "Reset credits",
                valueText: "1 credit remaining"
            )
        )
    }

    func testCountPluralizesRemaining() {
        let alert = crossedCountThreshold(
            threshold: 2,
            previous: 3,
            current: 0,
            provider: "Codex",
            window: "Reset credits"
        )
        XCTAssertEqual(
            alert,
            ThresholdAlert(
                provider: "Codex",
                window: "Reset credits",
                valueText: "0 credits remaining"
            )
        )
    }

    func testCountDoesNotFireWhenStayingAtOrBelow() {
        let alert = crossedCountThreshold(
            threshold: 1,
            previous: 1,
            current: 0,
            provider: "Codex",
            window: "Reset credits"
        )
        XCTAssertNil(alert)
    }

    func testCountDoesNotFireWhenOff() {
        let alert = crossedCountThreshold(
            threshold: 0,
            previous: 5,
            current: 0,
            provider: "Codex",
            window: "Reset credits"
        )
        XCTAssertNil(alert)
    }
}
