import Foundation

enum CursorConnectAPI {
    static let baseURL = URL(string: "https://api2.cursor.sh")!

    static let getCurrentPeriodUsage = "GetCurrentPeriodUsage"
    static let getPlanInfo = "GetPlanInfo"

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
