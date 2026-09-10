import XCTest
@testable import AgentUsageBar

@MainActor
final class UsagePresentationTests: XCTestCase {
    func testProviderUsagePageURLs() {
        XCTAssertEqual(
            UsageProvider.claude.usagePageURL.absoluteString,
            "https://claude.ai/new#settings/usage"
        )
        XCTAssertEqual(
            UsageProvider.openAI.usagePageURL.absoluteString,
            "https://chatgpt.com/#settings/Usage"
        )
        XCTAssertEqual(
            UsageProvider.cursor.usagePageURL.absoluteString,
            "https://cursor.com/dashboard/spending"
        )
        XCTAssertEqual(
            UsageProvider.elevenLabs.usagePageURL.absoluteString,
            "https://elevenlabs.io/app/subscription/"
        )
    }

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

    func testOpenAIDetailPairPairsSessionAndWeeklyWindows() {
        let session = percentageMetric(
            id: UsagePresentationMetrics.openAIPrimaryID,
            label: "5-Hour Window",
            value: 12
        )
        let weekly = percentageMetric(
            id: UsagePresentationMetrics.openAISecondaryID,
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

        let pair = UsagePresentationMetrics.detailPair(
            for: .openAI,
            available: [session, weekly, resets]
        )

        XCTAssertEqual(pair.map(\.id), [session.id, weekly.id])
        XCTAssertNotNil(pair[1].normalizedProgress)
    }

    func testOpenAIDetailPairFallsBackToResetCreditsWithoutWeeklyWindow() {
        let session = percentageMetric(
            id: UsagePresentationMetrics.openAIPrimaryID,
            label: "5-Hour Window",
            value: 12
        )
        let resets = UsagePresentationMetric(
            id: UsagePresentationMetrics.openAIResetCreditsID,
            label: "Reset Credits",
            shortLabel: "R",
            kind: .count(2),
            resetDate: nil,
            resetInterval: nil
        )

        let pair = UsagePresentationMetrics.detailPair(
            for: .openAI,
            available: [session, resets]
        )

        XCTAssertEqual(pair.map(\.id), [session.id, resets.id])
        XCTAssertEqual(pair[1].valueText, "2")
        XCTAssertEqual(pair[1].accessibilityValue, "2 available")
        XCTAssertTrue(pair[1].isCount)
        XCTAssertNil(pair[1].normalizedProgress)
    }

    func testOpenAIDefaultsPreferWeeklyWindowOverResetCredits() {
        let session = percentageMetric(
            id: UsagePresentationMetrics.openAIPrimaryID,
            label: "5-Hour Window",
            value: 12
        )
        let weekly = percentageMetric(
            id: UsagePresentationMetrics.openAISecondaryID,
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

        let defaults = UsagePresentationMetrics.defaults(
            for: .openAI,
            available: [session, weekly, resets]
        )

        XCTAssertEqual(defaults.primary, session.id)
        XCTAssertEqual(defaults.secondary, weekly.id)
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

    func testClaudeMetricsAttachSessionAndWeeklyGeometry() throws {
        let resetsAt = "2026-09-10T12:00:00Z"
        let usage = UsageResponse(
            fiveHour: UsageBucket(utilization: 32.4, resetsAt: resetsAt),
            sevenDay: UsageBucket(utilization: 41, resetsAt: resetsAt),
            sevenDayOpus: UsageBucket(utilization: 10, resetsAt: resetsAt),
            sevenDaySonnet: nil,
            extraUsage: ExtraUsage(
                isEnabled: true,
                utilization: 5,
                usedCredits: nil,
                monthlyLimit: nil
            ),
            limits: [
                ClaudeUsageLimit(
                    kind: "weekly_scoped",
                    group: "weekly",
                    percent: 55,
                    severity: nil,
                    resetsAt: resetsAt,
                    scope: ClaudeUsageScope(
                        model: ClaudeUsageModel(id: "fable", displayName: "Fable"),
                        surface: nil
                    ),
                    isActive: true
                ),
                ClaudeUsageLimit(
                    kind: "session_scoped",
                    group: "session",
                    percent: 12,
                    severity: nil,
                    resetsAt: resetsAt,
                    scope: ClaudeUsageScope(
                        model: ClaudeUsageModel(id: "sonnet", displayName: "Sonnet"),
                        surface: nil
                    ),
                    isActive: true
                ),
                ClaudeUsageLimit(
                    kind: "monthly_scoped",
                    group: "monthly",
                    percent: 8,
                    severity: nil,
                    resetsAt: resetsAt,
                    scope: ClaudeUsageScope(
                        model: ClaudeUsageModel(id: "opus", displayName: "Opus"),
                        surface: nil
                    ),
                    isActive: true
                ),
                ClaudeUsageLimit(
                    kind: "ungrouped_scoped",
                    group: nil,
                    percent: 3,
                    severity: nil,
                    resetsAt: resetsAt,
                    scope: ClaudeUsageScope(
                        model: ClaudeUsageModel(id: "composer", displayName: "Composer"),
                        surface: nil
                    ),
                    isActive: true
                )
            ]
        )

        let metrics = UsagePresentationMetrics.claudeMetrics(usage)
        let fiveHour = try XCTUnwrap(metrics.first { $0.id == UsagePresentationMetrics.claudeFiveHourID })
        let sevenDay = try XCTUnwrap(metrics.first { $0.id == UsagePresentationMetrics.claudeSevenDayID })
        let opus = try XCTUnwrap(metrics.first { $0.id == UsagePresentationMetrics.claudeOpusID })
        let weeklyScoped = try XCTUnwrap(metrics.first { $0.label.contains("Fable") })
        let sessionScoped = try XCTUnwrap(metrics.first { $0.label.contains("session") })
        let monthlyScoped = try XCTUnwrap(metrics.first { $0.label.contains("monthly") })
        let ungroupedScoped = try XCTUnwrap(metrics.first { $0.label == "Composer" })
        let extra = try XCTUnwrap(metrics.first { $0.id == UsagePresentationMetrics.claudeExtraID })

        XCTAssertEqual(fiveHour.geometry?.duration, UsageWindowGeometry.claudeSessionDuration)
        XCTAssertEqual(fiveHour.geometry?.usedPercent, 32.4)
        XCTAssertEqual(fiveHour.geometry?.resetsAt, fiveHour.resetDate)
        XCTAssertEqual(sevenDay.geometry?.duration, UsageWindowGeometry.claudeWeeklyDuration)
        XCTAssertEqual(sevenDay.geometry?.resetsAt, sevenDay.resetDate)
        XCTAssertEqual(opus.geometry?.duration, UsageWindowGeometry.claudeWeeklyDuration)
        XCTAssertEqual(weeklyScoped.geometry?.duration, UsageWindowGeometry.claudeWeeklyDuration)
        XCTAssertEqual(sessionScoped.geometry?.duration, UsageWindowGeometry.claudeSessionDuration)
        XCTAssertNotNil(monthlyScoped.geometry)
        XCTAssertNil(monthlyScoped.geometry?.duration)
        XCTAssertEqual(monthlyScoped.geometry?.usedPercent, 8)
        XCTAssertEqual(monthlyScoped.geometry?.resetsAt, monthlyScoped.resetDate)
        XCTAssertEqual(monthlyScoped.remainingHeadlineText, "92% left")
        XCTAssertFalse(monthlyScoped.showsLegacyResetLine)
        XCTAssertNotNil(ungroupedScoped.geometry)
        XCTAssertNil(ungroupedScoped.geometry?.duration)
        XCTAssertEqual(ungroupedScoped.remainingHeadlineText, "97% left")
        XCTAssertNil(extra.geometry)
        XCTAssertNil(extra.remainingHeadlineText)
    }

    func testOpenAIMetricsAttachGeometryFromLimitWindowSeconds() throws {
        let resetAt: TimeInterval = 1_700_000_000 + 5 * 60 * 60
        let additionalResetAt: TimeInterval = 1_700_000_000 + 24 * 60 * 60
        let usage = OpenAIUsageResponse(
            email: nil,
            planType: nil,
            rateLimit: OpenAIRateLimit(
                allowed: true,
                limitReached: false,
                primaryWindow: OpenAIUsageWindow(
                    usedPercent: 32.4,
                    limitWindowSeconds: 5 * 60 * 60,
                    resetAfterSeconds: nil,
                    resetAt: resetAt
                ),
                secondaryWindow: OpenAIUsageWindow(
                    usedPercent: 41,
                    limitWindowSeconds: 7 * 24 * 60 * 60,
                    resetAfterSeconds: nil,
                    resetAt: resetAt
                )
            ),
            codeReviewRateLimit: nil,
            additionalRateLimits: [
                OpenAIAdditionalRateLimit(
                    type: "code_review",
                    label: "Code Review",
                    rateLimit: OpenAIRateLimit(
                        allowed: true,
                        limitReached: false,
                        primaryWindow: OpenAIUsageWindow(
                            usedPercent: 18,
                            limitWindowSeconds: 24 * 60 * 60,
                            resetAfterSeconds: nil,
                            resetAt: additionalResetAt
                        ),
                        secondaryWindow: nil
                    )
                )
            ],
            credits: nil,
            spendControl: nil,
            rateLimitResetCredits: nil
        )

        let metrics = UsagePresentationMetrics.openAIMetrics(usage: usage, resetCredits: nil)
        let additionalMetrics = UsagePresentationMetrics.openAIAdditionalLimitMetrics(usage: usage)
        let primary = try XCTUnwrap(metrics.first { $0.id == UsagePresentationMetrics.openAIPrimaryID })
        let secondary = try XCTUnwrap(metrics.first { $0.id == UsagePresentationMetrics.openAISecondaryID })
        let credits = try XCTUnwrap(metrics.first { $0.id == UsagePresentationMetrics.openAIResetCreditsID })
        let additional = try XCTUnwrap(additionalMetrics.first { $0.id == "openai.additional.code_review.0" })

        XCTAssertEqual(primary.geometry?.duration, 5 * 60 * 60)
        XCTAssertEqual(primary.geometry?.usedPercent, 32.4)
        XCTAssertEqual(primary.geometry?.resetsAt, Date(timeIntervalSince1970: resetAt))
        XCTAssertEqual(secondary.geometry?.duration, 7 * 24 * 60 * 60)
        XCTAssertEqual(secondary.geometry?.resetsAt, Date(timeIntervalSince1970: resetAt))
        XCTAssertNil(credits.geometry)
        XCTAssertEqual(additional.label, "Code Review")
        XCTAssertEqual(additional.geometry?.duration, 24 * 60 * 60)
        XCTAssertEqual(additional.geometry?.usedPercent, 18)
        XCTAssertEqual(additional.geometry?.resetsAt, Date(timeIntervalSince1970: additionalResetAt))
        XCTAssertEqual(additional.remainingHeadlineText, "82% left")
    }

    func testOpenAISharedMetricsOmitAdditionalLimits() throws {
        let resetAt: TimeInterval = 1_700_000_000 + 5 * 60 * 60
        let usage = OpenAIUsageResponse(
            email: nil,
            planType: nil,
            rateLimit: OpenAIRateLimit(
                allowed: true,
                limitReached: false,
                primaryWindow: OpenAIUsageWindow(
                    usedPercent: 32.4,
                    limitWindowSeconds: 5 * 60 * 60,
                    resetAfterSeconds: nil,
                    resetAt: resetAt
                ),
                secondaryWindow: OpenAIUsageWindow(
                    usedPercent: 41,
                    limitWindowSeconds: 7 * 24 * 60 * 60,
                    resetAfterSeconds: nil,
                    resetAt: resetAt
                )
            ),
            codeReviewRateLimit: nil,
            additionalRateLimits: [
                OpenAIAdditionalRateLimit(
                    type: "code_review",
                    label: "Code Review",
                    rateLimit: OpenAIRateLimit(
                        allowed: true,
                        limitReached: false,
                        primaryWindow: OpenAIUsageWindow(
                            usedPercent: 18,
                            limitWindowSeconds: 24 * 60 * 60,
                            resetAfterSeconds: nil,
                            resetAt: resetAt
                        ),
                        secondaryWindow: nil
                    )
                )
            ],
            credits: nil,
            spendControl: nil,
            rateLimitResetCredits: nil
        )

        let shared = UsagePresentationMetrics.openAIMetrics(usage: usage, resetCredits: nil)
        let additional = UsagePresentationMetrics.openAIAdditionalLimitMetrics(usage: usage)

        XCTAssertEqual(
            shared.map(\.id),
            [
                UsagePresentationMetrics.openAIPrimaryID,
                UsagePresentationMetrics.openAISecondaryID,
                UsagePresentationMetrics.openAIResetCreditsID
            ]
        )
        XCTAssertFalse(shared.contains { $0.id.hasPrefix("openai.additional.") })
        XCTAssertEqual(additional.map(\.id), ["openai.additional.code_review.0"])
    }

    func testCursorAndElevenLabsMetricsHaveNoGeometry() throws {
        let cursor = UsagePresentationMetrics.cursorMetrics(
            CursorUsageResponse(
                billingCycleStart: nil,
                billingCycleEnd: "1790439879000",
                planUsage: CursorPlanUsage(
                    totalSpend: nil,
                    includedSpend: nil,
                    bonusSpend: nil,
                    limit: nil,
                    remainingBonus: nil,
                    bonusTooltip: nil,
                    autoPercentUsed: 12,
                    apiPercentUsed: 6,
                    totalPercentUsed: 18
                ),
                spendLimitUsage: nil,
                displayMessage: nil,
                autoModelSelectedDisplayMessage: nil,
                namedModelSelectedDisplayMessage: nil
            )
        )
        XCTAssertTrue(cursor.allSatisfy { $0.geometry == nil })
        XCTAssertTrue(cursor.allSatisfy { $0.paceSystemImage() == nil })
        XCTAssertTrue(cursor.allSatisfy { $0.restoresLine() == nil })
        let models = try XCTUnwrap(cursor.first { $0.id == UsagePresentationMetrics.cursorModelsID })
        XCTAssertNil(models.remainingHeadlineText)
        XCTAssertEqual(models.valueText, "12%")

        let eleven = UsagePresentationMetrics.elevenLabsMetrics(
            ElevenLabsSubscriptionResponse(
                tier: "creator",
                characterCount: 100,
                characterLimit: 100_000,
                nextCharacterCountResetUnix: 1_700_100_000,
                status: "active",
                billingPeriod: "monthly_period",
                characterRefreshPeriod: "monthly_period",
                voiceSlotsUsed: nil,
                voiceLimit: nil,
                professionalVoiceSlotsUsedInWorkspace: nil,
                professionalVoiceLimit: nil
            )
        )
        XCTAssertTrue(eleven.allSatisfy { $0.geometry == nil })
        XCTAssertTrue(eleven.allSatisfy { $0.paceSystemImage() == nil })
        XCTAssertTrue(eleven.allSatisfy { $0.restoresLine() == nil })
        let credits = try XCTUnwrap(eleven.first { $0.id == UsagePresentationMetrics.elevenLabsCreditsID })
        XCTAssertNil(credits.remainingHeadlineText)
        XCTAssertEqual(credits.valueText, "0%")
    }

    func testRemainingHeadlineAndRestoresLineForFixedNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetsAt = now.addingTimeInterval(5 * 86_400 + 3 * 3_600)
        let metric = UsagePresentationMetric(
            id: "test",
            label: "Weekly",
            shortLabel: "7d",
            kind: .percentage(32.4),
            resetDate: resetsAt,
            resetInterval: UsageWindowGeometry.claudeWeeklyDuration,
            geometry: UsageWindowGeometry(
                usedPercent: 32.4,
                resetsAt: resetsAt,
                duration: UsageWindowGeometry.claudeWeeklyDuration
            )
        )

        XCTAssertEqual(metric.remainingHeadlineText, "68% left")
        XCTAssertEqual(metric.valueText, "32%")
        XCTAssertEqual(metric.restoresLine(now: now), "+32% in 5d 3h")
        // Elapsed ~26.8%; used 32.4 is ahead of even pace.
        XCTAssertEqual(metric.paceSystemImage(now: now), "arrow.up.right")
        XCTAssertEqual(metric.paceAccessibilityText(now: now), "ahead of pace")
        XCTAssertEqual(
            metric.popoverAccessibilityValue(now: now),
            "68% left, ahead of pace, +32% in 5d 3h"
        )
    }

    // MARK: - Detail rows (#56)

    func testResetCreditsLineCountsAndNamesTheSoonestExpiry() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tenDays: TimeInterval = 10 * 86_400
        let extra: TimeInterval = 22 * 3_600 + 30 * 60
        let expiry = now.addingTimeInterval(tenDays + extra)

        XCTAssertEqual(
            UsageDetailRows.resetCreditsLine(count: 3, nextExpiry: expiry, now: now),
            "3 banked · next expires in 10d 22h"
        )
        XCTAssertEqual(UsageDetailRows.resetCreditsLine(count: 1, nextExpiry: nil, now: now), "1 banked")
        XCTAssertNil(UsageDetailRows.resetCreditsLine(count: 0, nextExpiry: expiry, now: now))
    }

    func testOpenAIPopoverMetricsDropsResetCreditsRow() {
        let session = percentageMetric(
            id: UsagePresentationMetrics.openAIPrimaryID,
            label: "5-Hour Window",
            value: 12
        )
        let weekly = percentageMetric(
            id: UsagePresentationMetrics.openAISecondaryID,
            label: "7-Day Window",
            value: 37
        )
        let resets = UsagePresentationMetric(
            id: UsagePresentationMetrics.openAIResetCreditsID,
            label: "Reset Credits",
            shortLabel: "R",
            kind: .count(3),
            resetDate: nil,
            resetInterval: nil
        )
        let additional = percentageMetric(
            id: "openai.additional.code_review.0",
            label: "Code Review",
            value: 18
        )

        let popover = UsagePresentationMetrics.openAIPopoverMetrics(
            [session, weekly, resets, additional]
        )
        XCTAssertEqual(popover.map(\.id), [session.id, weekly.id, additional.id])

        let pair = UsagePresentationMetrics.detailPair(for: .openAI, available: popover)
        XCTAssertEqual(pair.map(\.id), [session.id, weekly.id])
        XCTAssertFalse(popover.contains { $0.id == UsagePresentationMetrics.openAIResetCreditsID })
    }

    func testOpenAIPopoverMetricsWithoutWeeklyLeavesResetCreditsOutOfOrbit() {
        let session = percentageMetric(
            id: UsagePresentationMetrics.openAIPrimaryID,
            label: "5-Hour Window",
            value: 12
        )
        let resets = UsagePresentationMetric(
            id: UsagePresentationMetrics.openAIResetCreditsID,
            label: "Reset Credits",
            shortLabel: "R",
            kind: .count(3),
            resetDate: nil,
            resetInterval: nil
        )

        let popover = UsagePresentationMetrics.openAIPopoverMetrics([session, resets])
        let pair = UsagePresentationMetrics.detailPair(for: .openAI, available: popover)
        XCTAssertEqual(pair.map(\.id), [session.id])
        XCTAssertNil(pair.first { $0.id == UsagePresentationMetrics.openAIResetCreditsID })
    }

    func testCodexPlanAndSourceLines() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(UsageDetailRows.codexPlanLine(planType: "plus"), "Plan: Plus")
        XCTAssertEqual(UsageDetailRows.codexPlanLine(planType: "Team"), "Plan: Team")
        XCTAssertNil(UsageDetailRows.codexPlanLine(planType: ""))
        XCTAssertNil(UsageDetailRows.codexPlanLine(planType: nil))

        XCTAssertEqual(
            UsageDetailRows.codexSourceLine(
                source: .codexCLI,
                tokenExpiry: now.addingTimeInterval(4 * 86_400 + 5 * 3_600),
                now: now
            ),
            "Source: Codex CLI login · expires in 4d"
        )
        XCTAssertEqual(
            UsageDetailRows.codexSourceLine(source: .codexCLI, tokenExpiry: now.addingTimeInterval(-60), now: now),
            "Source: Codex CLI login · expired"
        )
        XCTAssertEqual(
            UsageDetailRows.codexSourceLine(source: .codexCLI, tokenExpiry: nil, now: now),
            "Source: Codex CLI login"
        )
        XCTAssertEqual(
            UsageDetailRows.codexSourceLine(source: .pasted, tokenExpiry: nil, now: now),
            "Source: pasted token"
        )
        XCTAssertEqual(
            UsageDetailRows.codexSourceLine(source: .environment, tokenExpiry: nil, now: now),
            "Source: environment variable"
        )
        XCTAssertNil(UsageDetailRows.codexSourceLine(source: .none, tokenExpiry: nil, now: now))
        // Source lines depend only on the credential source, not on usage success.
        XCTAssertNotNil(UsageDetailRows.codexSourceLine(source: .pasted, tokenExpiry: nil, now: now))
        XCTAssertNil(UsageDetailRows.codexPlanLine(planType: nil))
    }

    func testCursorPlanSpendAndSourceLines() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let renewsAt = now.addingTimeInterval(12 * 86_400 + 7 * 3_600)
        let planInfo = try JSONDecoder().decode(
            CursorPlanInfoResponse.self,
            from: Data(
                #"{"planInfo":{"planName":"Pro","includedAmountCents":2000,"price":"$20/mo","billingCycleEnd":"\#(Int(renewsAt.timeIntervalSince1970 * 1_000))","planOwner":"PLAN_OWNER_STRIPE"}}"#.utf8
            )
        )
        let usage = try JSONDecoder().decode(
            CursorUsageResponse.self,
            from: Data(#"{"planUsage":{"totalPercentUsed":20.3}}"#.utf8)
        )

        XCTAssertEqual(
            UsageDetailRows.cursorPlanLine(planInfo.planInfo, now: now),
            "Pro · $20/mo · renews in 12d"
        )
        XCTAssertEqual(
            UsageDetailRows.cursorSpendLine(planUsage: usage.planUsage, includedAmountCents: 2000),
            "used $4.06 of $20.00"
        )
        XCTAssertNil(UsageDetailRows.cursorSpendLine(planUsage: usage.planUsage, includedAmountCents: nil))
        XCTAssertNil(UsageDetailRows.cursorSpendLine(planUsage: nil, includedAmountCents: 2000))
        XCTAssertNil(UsageDetailRows.cursorPlanLine(nil, now: now))

        let renewed = CursorPlanInfo(
            planName: "Pro",
            includedAmountCents: nil,
            price: nil,
            billingCycleEnd: "\(Int(now.addingTimeInterval(-2 * 86_400).timeIntervalSince1970 * 1_000))",
            planOwner: nil
        )
        XCTAssertEqual(UsageDetailRows.cursorPlanLine(renewed, now: now), "Pro · renewed 2d ago")

        XCTAssertEqual(
            UsageDetailRows.cursorSourceLine(
                source: .cursorCLI,
                tokenExpiry: now.addingTimeInterval(9 * 86_400 + 60),
                now: now
            ),
            "Source: Cursor CLI login · expires in 9d"
        )
        XCTAssertEqual(
            UsageDetailRows.cursorSourceLine(source: .pasted, tokenExpiry: nil, now: now),
            "Source: pasted cookie"
        )
        XCTAssertNil(UsageDetailRows.cursorSourceLine(source: .none, tokenExpiry: nil, now: now))
        // Source lines depend only on the credential source, not on usage success.
        XCTAssertNotNil(UsageDetailRows.cursorSourceLine(source: .cursorCLI, tokenExpiry: nil, now: now))
    }

    func testClaudePlanLineJoinsTierAndStatus() {
        XCTAssertEqual(
            UsageDetailRows.claudePlanLine(planLabel: "Max 20x", subscriptionStatus: "active"),
            "Max 20x · active"
        )
        XCTAssertEqual(UsageDetailRows.claudePlanLine(planLabel: "Pro", subscriptionStatus: nil), "Pro")
        XCTAssertEqual(UsageDetailRows.claudePlanLine(planLabel: "", subscriptionStatus: "active"), "active")
        XCTAssertNil(UsageDetailRows.claudePlanLine(planLabel: "", subscriptionStatus: nil))
    }

    func testCoarseDurationUsesOneUnit() {
        XCTAssertEqual(UsageDetailRows.coarseDuration(12 * 86_400 + 23 * 3_600), "12d")
        XCTAssertEqual(UsageDetailRows.coarseDuration(9 * 3_600 + 59 * 60), "9h")
        XCTAssertEqual(UsageDetailRows.coarseDuration(40 * 60 + 59), "40m")
        XCTAssertEqual(UsageDetailRows.coarseDuration(-5), "0m")
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
