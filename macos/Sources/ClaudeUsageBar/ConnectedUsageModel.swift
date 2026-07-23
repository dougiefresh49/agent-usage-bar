import Foundation

struct CursorUsageResponse: Codable, Equatable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let planUsage: CursorPlanUsage?
    let spendLimitUsage: CursorSpendLimitUsage?
    let displayMessage: String?
    let autoModelSelectedDisplayMessage: String?
    let namedModelSelectedDisplayMessage: String?

    var billingCycleEndDate: Date? {
        Self.millisecondDate(from: billingCycleEnd)
    }

    private static func millisecondDate(from value: String?) -> Date? {
        guard let value, let milliseconds = Double(value) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

struct CursorPlanUsage: Codable, Equatable {
    let totalSpend: Double?
    let includedSpend: Double?
    let bonusSpend: Double?
    let limit: Double?
    let remainingBonus: Bool?
    let bonusTooltip: String?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalPercentUsed: Double?
}

struct CursorSpendLimitUsage: Codable, Equatable {
    let individualLimit: Double?
    let individualRemaining: Double?
    let limitType: String?

    var spent: Double? {
        guard let limit = individualLimit, let remaining = individualRemaining else { return nil }
        return max(0, limit - remaining)
    }

    var utilization: Double? {
        guard let limit = individualLimit, limit > 0, let spent else { return nil }
        return min(max(spent / limit * 100, 0), 100)
    }
}

struct OpenAIUsageResponse: Codable, Equatable {
    let email: String?
    let planType: String?
    let rateLimit: OpenAIRateLimit?
    let codeReviewRateLimit: OpenAIRateLimit?
    let additionalRateLimits: [OpenAIAdditionalRateLimit]?
    let credits: OpenAICreditBalance?
    let spendControl: OpenAISpendControl?
    let rateLimitResetCredits: OpenAIResetCreditSummary?

    enum CodingKeys: String, CodingKey {
        case email
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case codeReviewRateLimit = "code_review_rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case credits
        case spendControl = "spend_control"
        case rateLimitResetCredits = "rate_limit_reset_credits"
    }
}

struct OpenAIRateLimit: Codable, Equatable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: OpenAIUsageWindow?
    let secondaryWindow: OpenAIUsageWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct OpenAIAdditionalRateLimit: Codable, Equatable, Identifiable {
    let type: String?
    let label: String?
    let rateLimit: OpenAIRateLimit?

    var id: String { type ?? label ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case type
        case label
        case rateLimit = "rate_limit"
    }
}

struct OpenAIUsageWindow: Codable, Equatable {
    let usedPercent: Double?
    let limitWindowSeconds: Double?
    let resetAfterSeconds: Double?
    let resetAt: Double?

    var resetDate: Date? {
        resetAt.map(Date.init(timeIntervalSince1970:))
    }

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }
}

struct OpenAICreditBalance: Codable, Equatable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let overageLimitReached: Bool?
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case overageLimitReached = "overage_limit_reached"
        case balance
    }
}

struct OpenAISpendControl: Codable, Equatable {
    let reached: Bool?
    let individualLimit: Double?

    enum CodingKeys: String, CodingKey {
        case reached
        case individualLimit = "individual_limit"
    }
}

struct OpenAIResetCreditSummary: Codable, Equatable {
    let availableCount: Int?
    let applicableAvailableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case applicableAvailableCount = "applicable_available_count"
    }
}

struct OpenAIResetCreditsResponse: Codable, Equatable {
    let credits: [OpenAIResetCredit]
    let availableCount: Int?
    let totalEarnedCount: Int?

    enum CodingKeys: String, CodingKey {
        case credits
        case availableCount = "available_count"
        case totalEarnedCount = "total_earned_count"
    }
}

struct OpenAIResetCredit: Codable, Equatable, Identifiable {
    let id: String
    let resetType: String?
    let isSupportedByPlan: Bool?
    let status: String?
    let grantedAt: String?
    let expiresAt: String?
    let title: String?
    let description: String?

    var expiresAtDate: Date? {
        guard let expiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }

    var isAvailable: Bool {
        status == "available"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case resetType = "reset_type"
        case isSupportedByPlan = "is_supported_by_plan"
        case status
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case title
        case description
    }
}

enum UsageMoney {
    static func minorUnits(_ value: Double) -> String {
        ExtraUsage.formatUSD(value / 100)
    }
}
