import XCTest
@testable import AgentUsageBar

final class ConnectedUsageModelTests: XCTestCase {
    func testDecodesClaudeScopedFableLimit() throws {
        let data = Data(
            """
            {
              "five_hour": { "utilization": 56, "resets_at": "2026-07-23T03:19:59Z" },
              "seven_day": { "utilization": 16, "resets_at": "2026-07-29T07:59:59Z" },
              "limits": [{
                "kind": "weekly_scoped",
                "group": "weekly",
                "percent": 28,
                "severity": "normal",
                "resets_at": "2026-07-29T07:59:59Z",
                "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
                "is_active": false
              }]
            }
            """.utf8
        )

        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)

        XCTAssertEqual(usage.scopedModelLimits.count, 1)
        XCTAssertEqual(usage.scopedModelLimits.first?.scope?.model?.displayName, "Fable")
        XCTAssertEqual(usage.scopedModelLimits.first?.percent, 28)
    }

    func testDecodesCursorUsageAndCalculatesOnDemandSpend() throws {
        let data = Data(
            """
            {
              "billingCycleEnd": "1785083079000",
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

        XCTAssertEqual(usage.planUsage?.autoPercentUsed, 10.2)
        XCTAssertEqual(usage.spendLimitUsage?.spent, 300)
        XCTAssertEqual(usage.spendLimitUsage?.utilization, 20)
        XCTAssertNotNil(usage.billingCycleEndDate)
    }

    func testDecodesOpenAIUsageAndResetAnnouncement() throws {
        let usageData = Data(
            """
            {
              "plan_type": "plus",
              "rate_limit": {
                "allowed": true,
                "limit_reached": false,
                "primary_window": {
                  "used_percent": 43,
                  "limit_window_seconds": 604800,
                  "reset_after_seconds": 516468,
                  "reset_at": 1785289159
                },
                "secondary_window": null
              },
              "rate_limit_reset_credits": {
                "available_count": 3,
                "applicable_available_count": 0
              }
            }
            """.utf8
        )
        let creditsData = Data(
            """
            {
              "credits": [{
                "id": "reset-1",
                "reset_type": "codex_rate_limits",
                "is_supported_by_plan": true,
                "status": "available",
                "expires_at": "2026-08-11T21:10:12.988860Z",
                "title": "Full reset",
                "description": "A free rate limit reset is available."
              }],
              "available_count": 1,
              "total_earned_count": 0
            }
            """.utf8
        )

        let usage = try JSONDecoder().decode(OpenAIUsageResponse.self, from: usageData)
        let credits = try JSONDecoder().decode(OpenAIResetCreditsResponse.self, from: creditsData)

        XCTAssertEqual(usage.rateLimit?.primaryWindow?.usedPercent, 43)
        XCTAssertNotNil(usage.rateLimit?.primaryWindow?.resetDate)
        XCTAssertEqual(credits.credits.first?.title, "Full reset")
        XCTAssertTrue(credits.credits.first?.isAvailable == true)
    }

    func testDecodesElevenLabsSubscriptionAndCalculatesCreditBalance() throws {
        let data = Data(
            """
            {
              "tier": "creator",
              "character_count": 111312,
              "character_limit": 270914,
              "next_character_count_reset_unix": 1785289159,
              "status": "active",
              "billing_period": "monthly_period",
              "character_refresh_period": "monthly_period",
              "voice_slots_used": 3,
              "voice_limit": 30
            }
            """.utf8
        )

        let usage = try JSONDecoder().decode(
            ElevenLabsSubscriptionResponse.self,
            from: data
        )

        XCTAssertEqual(usage.tier, "creator")
        XCTAssertEqual(usage.creditsRemaining, 159602)
        XCTAssertEqual(usage.utilization ?? 0, 41.09, accuracy: 0.01)
        XCTAssertNotNil(usage.nextResetDate)
        XCTAssertEqual(usage.voiceSlotsUsed, 3)
    }
}

final class ConnectedServiceCredentialsTests: XCTestCase {
    func testNormalizesTokensFromCopiedRequestFormats() {
        XCTAssertEqual(
            ConnectedTokenNormalizer.cursor(
                "Cookie: a=1; WorkosCursorSessionToken=user%3A%3Atoken-value; b=2"
            ),
            "user%3A%3Atoken-value"
        )
        XCTAssertEqual(
            ConnectedTokenNormalizer.openAI("-H 'authorization: Bearer session-token' \\"),
            "session-token"
        )
        XCTAssertEqual(ConnectedTokenNormalizer.openAI("Bearer raw-token"), "raw-token")
        XCTAssertEqual(
            ConnectedTokenNormalizer.elevenLabs("-H 'xi-api-key: elevenlabs-key'"),
            "elevenlabs-key"
        )
        XCTAssertEqual(
            ConnectedTokenNormalizer.elevenLabs("ELEVENLABS_API_KEY=env-key"),
            "env-key"
        )
    }

    func testCredentialsFileUsesPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)

        try store.save(
            ConnectedServiceCredentials(
                openAISessionToken: "openai",
                cursorSessionToken: "cursor"
            )
        )

        XCTAssertEqual(store.load().openAISessionToken, "openai")
        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.credentialsFileURL.path
        )
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }
}

@MainActor
final class ConnectedUsageServiceTests: XCTestCase {
    override func tearDown() {
        ConnectedMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchesConfiguredProvidersWithMinimalHeaders() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(
            ConnectedServiceCredentials(
                openAISessionToken: "openai-token",
                cursorSessionToken: "cursor-token",
                elevenLabsAPIKey: "elevenlabs-key"
            )
        )

        let session = makeSession()
        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            switch request.url?.path {
            case "/cursor":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Cookie"),
                    "WorkosCursorSessionToken=cursor-token"
                )
                return (response, Data(#"{"planUsage":{"autoPercentUsed":10,"apiPercentUsed":6}}"#.utf8))
            case "/openai":
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Authorization"),
                    "Bearer openai-token"
                )
                return (response, Data(#"{"rate_limit":{"primary_window":{"used_percent":43}}}"#.utf8))
            case "/credits":
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            case "/elevenlabs":
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "xi-api-key"),
                    "elevenlabs-key"
                )
                return (
                    response,
                    Data(
                        #"{"tier":"creator","character_count":1000,"character_limit":10000}"#.utf8
                    )
                )
            default:
                throw URLError(.badURL)
            }
        }

        let service = ConnectedUsageService(
            session: session,
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            elevenLabsSubscriptionEndpoint: URL(string: "https://example.com/elevenlabs")!,
            credentialsStore: store,
            environment: [:]
        )

        await service.fetchAll()

        XCTAssertEqual(service.cursorUsage?.planUsage?.apiPercentUsed, 6)
        XCTAssertEqual(service.openAIUsage?.rateLimit?.primaryWindow?.usedPercent, 43)
        XCTAssertEqual(service.elevenLabsUsage?.creditsRemaining, 9000)
        XCTAssertNil(service.cursorError)
        XCTAssertNil(service.openAIError)
        XCTAssertNil(service.elevenLabsError)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConnectedMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class ConnectedMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
