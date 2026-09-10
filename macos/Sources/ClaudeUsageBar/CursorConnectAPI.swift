import Foundation

enum CursorConnectAPI {
    static let baseURL = URL(string: "https://api2.cursor.sh")!

    static let getCurrentPeriodUsage = "GetCurrentPeriodUsage"
    static let getPlanInfo = "GetPlanInfo"
    /// Cursor's wire name for Grok Bot is "Sand".
    static let getSandUsageStatus = "GetSandUsageStatus"

    static func request(method: String, token: String) -> URLRequest {
        let url = baseURL.appendingPathComponent("aiserver.v1.DashboardService/\(method)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue("cli-agent-usage-bar", forHTTPHeaderField: "x-cursor-client-version")
        request.setValue("cli", forHTTPHeaderField: "x-cursor-client-type")
        return request
    }
}

struct CursorPlanInfoResponse: Codable, Equatable {
    let planInfo: CursorPlanInfo?
    let nextUpgrade: CursorPlanNextUpgrade?
}

struct CursorPlanInfo: Codable, Equatable {
    let planName: String?
    let includedAmountCents: Int?
    let price: String?
    /// Epoch milliseconds as a string, matching the Connect-RPC payload.
    let billingCycleEnd: String?
    let planOwner: String?
}

struct CursorPlanNextUpgrade: Codable, Equatable {
    let tier: String?
    let name: String?
    let includedAmountCents: Int?
    let price: String?
    let description: String?
}

/// Cursor's wire name for Grok Bot is "Sand".
struct CursorGrokBotUsageResponse: Codable, Equatable {
    let currentPeriodStart: String?
    let nextResetTimestampUtc: String?
    let usagePercent: Double?
    let hasAvailableUsage: Bool?
    let hasNonZeroIncludedLimit: Bool?
    let grokPlanLabel: String?

    var currentPeriodStartDate: Date? {
        Self.parseISODate(currentPeriodStart)
    }

    var nextResetDate: Date? {
        Self.parseISODate(nextResetTimestampUtc)
    }

    var windowDuration: TimeInterval? {
        guard let start = currentPeriodStartDate, let end = nextResetDate else { return nil }
        let duration = end.timeIntervalSince(start)
        return duration > 0 ? duration : nil
    }

    private static func parseISODate(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else { return nil }
        return fractionalSecondsFormatter.date(from: value)
            ?? internetDateTimeFormatter.date(from: value)
    }

    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
