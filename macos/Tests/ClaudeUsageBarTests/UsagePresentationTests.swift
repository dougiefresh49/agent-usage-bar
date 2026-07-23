import XCTest
@testable import AgentUsageBar

@MainActor
final class UsagePresentationTests: XCTestCase {
    func testUsageTextSizeDefaultsToComfortableAndLargeUsesTwoColumns() {
        XCTAssertEqual(UsagePresentationDefaults.textSize, .comfortable)
        XCTAssertEqual(UsageTextSize.compact.overviewColumnCount, 3)
        XCTAssertEqual(UsageTextSize.comfortable.overviewColumnCount, 3)
        XCTAssertEqual(UsageTextSize.large.overviewColumnCount, 2)
    }

    func testCountdownProgressMapsFiveHourSessionToExpectedDrainLevels() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let interval: TimeInterval = 5 * 60 * 60

        XCTAssertEqual(
            try XCTUnwrap(UsagePresentationMetrics.countdownProgress(
                resetDate: now.addingTimeInterval(interval),
                interval: interval,
                now: now
            )),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(UsagePresentationMetrics.countdownProgress(
                resetDate: now.addingTimeInterval(4 * 60 * 60 + 12 * 60),
                interval: interval,
                now: now
            )),
            0.84,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(UsagePresentationMetrics.countdownProgress(
                resetDate: now.addingTimeInterval(3 * 60),
                interval: interval,
                now: now
            )),
            0.01,
            accuracy: 0.0001
        )
    }

    func testCompactRemainingTimeUsesTwoLargestUsefulUnits() {
        let now = Date(timeIntervalSince1970: 2_000_000)

        XCTAssertEqual(
            UsagePresentationMetrics.compactRemainingTime(
                until: now.addingTimeInterval(4 * 60 * 60 + 12 * 60),
                now: now
            ),
            "4h 12m"
        )
        XCTAssertEqual(
            UsagePresentationMetrics.compactRemainingTime(
                until: now.addingTimeInterval(3 * 60),
                now: now
            ),
            "3m"
        )
        XCTAssertEqual(
            UsagePresentationMetrics.compactRemainingTime(
                until: now.addingTimeInterval(2 * 24 * 60 * 60 + 4 * 60 * 60),
                now: now
            ),
            "2d 4h"
        )
    }

    func testOpenAIDetailPairUsesWeeklyUsageAndNumericResetCredits() {
        let weekly = percentageMetric(
            id: UsagePresentationMetrics.openAIPrimaryID,
            label: "7-Day Window",
            value: 37
        )
        let resets = UsagePresentationMetric(
            id: UsagePresentationMetrics.openAIResetCreditsID,
            label: "Reset Credits",
            shortLabel: "R",
            kind: .count(2),
            resetDate: nil,
            resetInterval: nil
        )
        let secondary = percentageMetric(
            id: UsagePresentationMetrics.openAISecondaryID,
            label: "Secondary",
            value: 8
        )

        let pair = UsagePresentationMetrics.detailPair(
            for: .openAI,
            available: [weekly, resets, secondary]
        )

        XCTAssertEqual(pair.map(\.id), [weekly.id, resets.id])
        XCTAssertEqual(pair[1].valueText, "2")
        XCTAssertEqual(pair[1].accessibilityValue, "2 available")
        XCTAssertTrue(pair[1].isCount)
        XCTAssertNil(pair[1].normalizedProgress)
    }

    func testResolvedPairFallsBackToProviderDefaultsWithoutDuplicates() {
        let primary = percentageMetric(
            id: UsagePresentationMetrics.cursorModelsID,
            label: "Models",
            value: 12
        )
        let secondary = percentageMetric(
            id: UsagePresentationMetrics.cursorAPIID,
            label: "API",
            value: 6
        )

        let pair = UsagePresentationMetrics.resolvedPair(
            provider: .cursor,
            primaryID: "missing",
            secondaryID: "missing",
            available: [primary, secondary]
        )

        XCTAssertEqual(pair.map(\.id), [primary.id, secondary.id])
    }

    func testElevenLabsDetailPairUsesCreditsAndFormattedRemainingBalance() {
        let used = percentageMetric(
            id: UsagePresentationMetrics.elevenLabsCreditsID,
            label: "Credits Used",
            value: 41
        )
        let remaining = UsagePresentationMetric(
            id: UsagePresentationMetrics.elevenLabsRemainingID,
            label: "Credits Remaining",
            shortLabel: "Left",
            kind: .count(159602),
            resetDate: nil,
            resetInterval: nil
        )

        let pair = UsagePresentationMetrics.detailPair(
            for: .elevenLabs,
            available: [used, remaining]
        )

        XCTAssertEqual(pair.map(\.id), [used.id, remaining.id])
        XCTAssertEqual(remaining.valueText, 159602.formatted(.number.grouping(.automatic)))
    }

    func testMenuBarStylesProduceCompactTemplateImages() {
        let metrics = [
            percentageMetric(
                id: UsagePresentationMetrics.openAIPrimaryID,
                label: "Weekly",
                value: 37
            ),
            UsagePresentationMetric(
                id: UsagePresentationMetrics.openAIResetCreditsID,
                label: "Reset Credits",
                shortLabel: "R",
                kind: .count(2),
                resetDate: nil,
                resetInterval: nil
            )
        ]

        let bars = renderMenuBarIcon(
            provider: .openAI,
            metrics: metrics,
            style: .bars,
            isConfigured: true
        )
        let capsule = renderMenuBarIcon(
            provider: .openAI,
            metrics: metrics,
            style: .capsule,
            isConfigured: true
        )

        XCTAssertTrue(bars.isTemplate)
        XCTAssertTrue(capsule.isTemplate)
        XCTAssertEqual(bars.size.height, 18)
        XCTAssertEqual(capsule.size.height, 18)
        XCTAssertGreaterThan(capsule.size.width, bars.size.width)
        XCTAssertLessThan(capsule.size.width, 70)
    }

    private func percentageMetric(
        id: String,
        label: String,
        value: Double
    ) -> UsagePresentationMetric {
        UsagePresentationMetric(
            id: id,
            label: label,
            shortLabel: label,
            kind: .percentage(value),
            resetDate: nil,
            resetInterval: nil
        )
    }
}
