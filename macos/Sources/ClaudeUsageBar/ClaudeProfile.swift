import Foundation

struct ClaudeProfileResponse: Codable, Equatable {
    let account: ClaudeProfileAccount?
    let organization: ClaudeProfileOrganization?

    var planLabel: String {
        let tier = organization?.rateLimitTier
        if tier == "default_claude_max_20x" {
            return "Max 20x"
        }
        if tier == "default_claude_max_5x" {
            return "Max 5x"
        }
        if tier == "claude_pro" || tier == "has_claude_pro" || account?.hasClaudePro == true {
            return "Pro"
        }
        guard let organizationType = organization?.organizationType, !organizationType.isEmpty else {
            return ""
        }
        return Self.titleCasedOrganizationType(organizationType)
    }

    private static func titleCasedOrganizationType(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
}

struct ClaudeProfileAccount: Codable, Equatable {
    let email: String?
    let hasClaudeMax: Bool?
    let hasClaudePro: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case email
        case hasClaudeMax = "has_claude_max"
        case hasClaudePro = "has_claude_pro"
        case createdAt = "created_at"
    }
}

struct ClaudeProfileOrganization: Codable, Equatable {
    let organizationType: String?
    let billingType: String?
    let rateLimitTier: String?
    let subscriptionStatus: String?
    let subscriptionCreatedAt: String?
    let hasExtraUsageEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case organizationType = "organization_type"
        case billingType = "billing_type"
        case rateLimitTier = "rate_limit_tier"
        case subscriptionStatus = "subscription_status"
        case subscriptionCreatedAt = "subscription_created_at"
        case hasExtraUsageEnabled = "has_extra_usage_enabled"
    }
}
