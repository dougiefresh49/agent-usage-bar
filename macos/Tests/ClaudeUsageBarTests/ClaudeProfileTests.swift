import XCTest
@testable import AgentUsageBar

final class ClaudeProfileTests: XCTestCase {
    private let fixtureJSON = """
    {
      "account": {
        "email": "user@example.com",
        "has_claude_max": true,
        "has_claude_pro": false,
        "created_at": "2026-03-24T16:25:09.805345Z"
      },
      "organization": {
        "organization_type": "claude_max",
        "billing_type": "stripe_subscription",
        "rate_limit_tier": "default_claude_max_20x",
        "subscription_status": "active",
        "subscription_created_at": "2026-04-10T15:53:44.244879Z",
        "has_extra_usage_enabled": true
      }
    }
    """

    func testDecodeFixture() throws {
        let data = try XCTUnwrap(fixtureJSON.data(using: .utf8))
        let profile = try JSONDecoder().decode(ClaudeProfileResponse.self, from: data)

        XCTAssertEqual(profile.account?.email, "user@example.com")
        XCTAssertEqual(profile.account?.hasClaudeMax, true)
        XCTAssertEqual(profile.account?.hasClaudePro, false)
        XCTAssertEqual(profile.account?.createdAt, "2026-03-24T16:25:09.805345Z")
        XCTAssertEqual(profile.organization?.organizationType, "claude_max")
        XCTAssertEqual(profile.organization?.billingType, "stripe_subscription")
        XCTAssertEqual(profile.organization?.rateLimitTier, "default_claude_max_20x")
        XCTAssertEqual(profile.organization?.subscriptionStatus, "active")
        XCTAssertEqual(profile.organization?.subscriptionCreatedAt, "2026-04-10T15:53:44.244879Z")
        XCTAssertEqual(profile.organization?.hasExtraUsageEnabled, true)
        XCTAssertEqual(profile.planLabel, "Max 20x")
    }

    func testPlanLabelMax20x() {
        XCTAssertEqual(profile(tier: "default_claude_max_20x").planLabel, "Max 20x")
    }

    func testPlanLabelMax5x() {
        XCTAssertEqual(profile(tier: "default_claude_max_5x").planLabel, "Max 5x")
    }

    func testPlanLabelProFromTier() {
        XCTAssertEqual(profile(tier: "claude_pro").planLabel, "Pro")
        XCTAssertEqual(profile(tier: "has_claude_pro").planLabel, "Pro")
    }

    func testPlanLabelProFromAccountFlag() {
        let profile = ClaudeProfileResponse(
            account: ClaudeProfileAccount(
                email: nil,
                hasClaudeMax: false,
                hasClaudePro: true,
                createdAt: nil
            ),
            organization: ClaudeProfileOrganization(
                organizationType: "claude_pro",
                billingType: nil,
                rateLimitTier: nil,
                subscriptionStatus: "active",
                subscriptionCreatedAt: nil,
                hasExtraUsageEnabled: nil
            )
        )
        XCTAssertEqual(profile.planLabel, "Pro")
    }

    func testPlanLabelFallsBackToTitleCasedOrganizationType() {
        XCTAssertEqual(
            profile(tier: nil, organizationType: "claude_max").planLabel,
            "Claude Max"
        )
    }

    private func profile(
        tier: String?,
        organizationType: String? = "claude_max",
        hasClaudePro: Bool? = false
    ) -> ClaudeProfileResponse {
        ClaudeProfileResponse(
            account: ClaudeProfileAccount(
                email: nil,
                hasClaudeMax: nil,
                hasClaudePro: hasClaudePro,
                createdAt: nil
            ),
            organization: ClaudeProfileOrganization(
                organizationType: organizationType,
                billingType: nil,
                rateLimitTier: tier,
                subscriptionStatus: nil,
                subscriptionCreatedAt: nil,
                hasExtraUsageEnabled: nil
            )
        )
    }
}
