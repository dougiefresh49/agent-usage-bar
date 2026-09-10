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
        XCTAssertEqual(usage.fableUtilization, 28)
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

    func testWeeklyWindowPicksLongestWindowRegardlessOfOrder() throws {
        let data = Data(
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 4,
                  "limit_window_seconds": 18000
                },
                "secondary_window": {
                  "used_percent": 32,
                  "limit_window_seconds": 604800
                }
              }
            }
            """.utf8
        )

        let usage = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)

        XCTAssertEqual(usage.rateLimit?.weeklyWindow?.usedPercent, 32)
    }

    func testWeeklyWindowFallsBackToPrimaryWhenLengthsAreUnknown() throws {
        let data = Data(
            """
            {
              "rate_limit": {
                "primary_window": { "used_percent": 70 }
              }
            }
            """.utf8
        )

        let usage = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)

        XCTAssertEqual(usage.rateLimit?.weeklyWindow?.usedPercent, 70)
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
                XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "codex-1")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Originator"), "Codex Desktop")
                XCTAssertNil(request.value(forHTTPHeaderField: "Chatgpt-Account-Id"))
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
        XCTAssertEqual(service.openAICredentialSource, .pasted)
        XCTAssertEqual(service.cursorCredentialSource, .pasted)
        XCTAssertNil(service.cursorError)
        XCTAssertNil(service.openAIError)
        XCTAssertNil(service.elevenLabsError)
    }

    func testOpenAICredentialPrecedencePrefersPastedOverCLIAndEnvironment() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(openAISessionToken: "pasted-token"))

        let session = makeSession()
        var authorizedToken: String?
        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path == "/openai" {
                authorizedToken = request.value(forHTTPHeaderField: "Authorization")
                return (response, Data(#"{"account_id":"acct-from-usage","rate_limit":{"primary_window":{"used_percent":1}}}"#.utf8))
            }
            if request.url?.path == "/credits" {
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let service = ConnectedUsageService(
            session: session,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            environment: ["OPENAI_SESSION_TOKEN": "env-token"],
            codexAuthLoader: {
                CodexCLICredentials(accessToken: "cli-token", accountId: "acct-cli", lastRefresh: nil)
            }
        )

        await service.fetchOpenAIUsage()

        XCTAssertEqual(service.openAICredentialSource, .pasted)
        XCTAssertEqual(authorizedToken, "Bearer pasted-token")
        XCTAssertNil(service.openAITokenExpiry)
    }

    func testOpenAIFallsBackToCodexCLIThenEnvironment() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        let session = makeSession()
        let exp = Date().addingTimeInterval(4 * 86_400)
        let cliToken = try makeUnsignedJWT(payloadJSON: #"{"exp":\#(Int(exp.timeIntervalSince1970))}"#)

        var authorizedToken: String?
        var accountHeader: String?
        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path == "/openai" {
                authorizedToken = request.value(forHTTPHeaderField: "Authorization")
                accountHeader = request.value(forHTTPHeaderField: "Chatgpt-Account-Id")
                XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "codex-1")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Originator"), "Codex Desktop")
                return (response, Data(#"{"rate_limit":{"primary_window":{"used_percent":2}}}"#.utf8))
            }
            if request.url?.path == "/credits" {
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let cliService = ConnectedUsageService(
            session: session,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            environment: ["OPENAI_SESSION_TOKEN": "env-token"],
            codexAuthLoader: {
                CodexCLICredentials(accessToken: cliToken, accountId: "acct-cli", lastRefresh: nil)
            }
        )
        await cliService.fetchOpenAIUsage()
        XCTAssertEqual(cliService.openAICredentialSource, .codexCLI)
        XCTAssertEqual(authorizedToken, "Bearer \(cliToken)")
        XCTAssertEqual(accountHeader, "acct-cli")
        XCTAssertEqual(cliService.openAIAccountID, "acct-cli")
        XCTAssertEqual(
            cliService.openAITokenExpiry?.timeIntervalSince1970 ?? -1,
            Double(Int(exp.timeIntervalSince1970)),
            accuracy: 0.5
        )

        authorizedToken = nil
        let envService = ConnectedUsageService(
            session: session,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            environment: ["OPENAI_SESSION_TOKEN": "env-token"],
            codexAuthLoader: { nil }
        )
        await envService.fetchOpenAIUsage()
        XCTAssertEqual(envService.openAICredentialSource, .environment)
        XCTAssertEqual(authorizedToken, "Bearer env-token")
    }

    func testCursorCLIUsesConnectRequestAndFetchesPlanInfoOncePerHour() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        let session = makeSession()
        let exp = Date().addingTimeInterval(9 * 86_400)
        let cliToken = try makeUnsignedJWT(payloadJSON: #"{"exp":\#(Int(exp.timeIntervalSince1970))}"#)

        var usagePaths: [String] = []
        var planInfoCount = 0
        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let path = request.url?.path ?? ""
            usagePaths.append(path)
            if path.contains("GetCurrentPeriodUsage") {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(cliToken)")
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                return (response, Data(#"{"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2}}"#.utf8))
            }
            if path.contains("GetPlanInfo") {
                planInfoCount += 1
                return (
                    response,
                    Data(#"{"planInfo":{"planName":"Pro","includedAmountCents":2000,"price":"$20/mo"}}"#.utf8)
                )
            }
            throw URLError(.badURL)
        }

        let service = ConnectedUsageService(
            session: session,
            credentialsStore: store,
            environment: [:],
            cursorKeychainRunner: { _, _ in cliToken },
            planInfoInterval: 3600
        )

        await service.fetchCursorUsage()
        await service.fetchCursorUsage()

        XCTAssertEqual(service.cursorCredentialSource, .cursorCLI)
        XCTAssertEqual(service.cursorUsage?.planUsage?.apiPercentUsed, 2)
        XCTAssertEqual(service.cursorPlanInfo?.planInfo?.planName, "Pro")
        XCTAssertEqual(planInfoCount, 1)
        XCTAssertEqual(
            usagePaths.filter { $0.contains("GetCurrentPeriodUsage") }.count,
            2
        )
        XCTAssertEqual(
            service.cursorTokenExpiry?.timeIntervalSince1970 ?? -1,
            Double(Int(exp.timeIntervalSince1970)),
            accuracy: 0.5
        )
    }

    func testUnauthorizedCopyDependsOnCredentialSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(openAISessionToken: "pasted"))
        let session = makeSession()

        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let pasted = ConnectedUsageService(
            session: session,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            environment: [:],
            codexAuthLoader: { nil }
        )
        await pasted.fetchOpenAIUsage()
        XCTAssertEqual(pasted.openAIError?.contains("OpenAI session expired"), true)
        XCTAssertEqual(pasted.openAIError?.contains("Settings"), true)

        try store.save(ConnectedServiceCredentials())
        let cli = ConnectedUsageService(
            session: session,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            environment: [:],
            codexAuthLoader: {
                CodexCLICredentials(accessToken: "cli", accountId: nil, lastRefresh: nil)
            }
        )
        await cli.fetchOpenAIUsage()
        XCTAssertEqual(
            cli.openAIError,
            "Codex login expired. Run any codex command or `codex login` to refresh."
        )

        let cursorCLI = ConnectedUsageService(
            session: session,
            credentialsStore: store,
            environment: [:],
            cursorKeychainRunner: { _, _ in "cursor-cli-token" }
        )
        await cursorCLI.fetchCursorUsage()
        XCTAssertEqual(
            cursorCLI.cursorError,
            "Cursor CLI login expired. Run `cursor-agent login`."
        )
    }

    private func makeUnsignedJWT(payloadJSON: String) throws -> String {
        let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8).base64URLEncoded()
        let payload = Data(payloadJSON.utf8).base64URLEncoded()
        return "\(header).\(payload).sig"
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
