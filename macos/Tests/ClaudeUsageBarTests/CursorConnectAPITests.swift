import XCTest
@testable import AgentUsageBar

final class CursorConnectAPITests: XCTestCase {
    func testRequestBuildsConnectRPCURLMethodHeadersAndBody() throws {
        let request = CursorConnectAPI.request(
            method: CursorConnectAPI.getCurrentPeriodUsage,
            token: "fake-token"
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "connect-protocol-version"), "1")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-cursor-client-version"),
            "cli-agent-usage-bar"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-cursor-client-type"), "cli")

        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(String(data: body, encoding: .utf8), "{}")
    }

    func testRequestBuildsGetPlanInfoURL() {
        let request = CursorConnectAPI.request(
            method: CursorConnectAPI.getPlanInfo,
            token: "fake-token"
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo"
        )
    }

    func testDecodesPlanInfoResponseFixture() throws {
        let data = Data(
            """
            {"planInfo":{"planName":"Pro","includedAmountCents":2000,"price":"$20/mo","billingCycleEnd":"1790439879000","planOwner":"PLAN_OWNER_STRIPE"},
             "nextUpgrade":{"tier":"pro_plus","name":"Pro+","includedAmountCents":7000,"price":"$60/mo","description":"Unlock 3x more usage on Agent & more"}}
            """.utf8
        )

        let response = try JSONDecoder().decode(CursorPlanInfoResponse.self, from: data)

        XCTAssertEqual(response.planInfo?.planName, "Pro")
        XCTAssertEqual(response.planInfo?.includedAmountCents, 2000)
        XCTAssertEqual(response.planInfo?.price, "$20/mo")
        XCTAssertEqual(response.planInfo?.billingCycleEnd, "1790439879000")
        XCTAssertEqual(response.planInfo?.planOwner, "PLAN_OWNER_STRIPE")
        XCTAssertEqual(response.nextUpgrade?.tier, "pro_plus")
        XCTAssertEqual(response.nextUpgrade?.name, "Pro+")
        XCTAssertEqual(response.nextUpgrade?.includedAmountCents, 7000)
        XCTAssertEqual(response.nextUpgrade?.price, "$60/mo")
        XCTAssertEqual(
            response.nextUpgrade?.description,
            "Unlock 3x more usage on Agent & more"
        )
    }

    func testGetCurrentPeriodUsageDecodesIntoExistingCursorUsageResponse() throws {
        let data = Data(
            """
            {
              "billingCycleStart": "1785083079000",
              "billingCycleEnd": "1787681079000",
              "planUsage": {
                "totalSpend": 3332,
                "includedSpend": 2000,
                "autoPercentUsed": 10.2,
                "apiPercentUsed": 6,
                "totalPercentUsed": 9.65
              },
              "spendLimitUsage": {
                "individualLimit": 1500,
                "individualRemaining": 1200,
                "limitType": "user"
              }
            }
            """.utf8
        )

        let usage = try JSONDecoder().decode(CursorUsageResponse.self, from: data)

        XCTAssertEqual(usage.billingCycleStart, "1785083079000")
        XCTAssertEqual(usage.billingCycleEnd, "1787681079000")
        XCTAssertEqual(usage.planUsage?.totalPercentUsed, 9.65)
        XCTAssertEqual(usage.spendLimitUsage?.individualRemaining, 1200)
    }
}
