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

    func testSparkAdditionalLimitsDoNotReplacePrimaryOrSecondaryWindows() throws {
        let data = Data(
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 41,
                  "limit_window_seconds": 18000
                },
                "secondary_window": {
                  "used_percent": 22,
                  "limit_window_seconds": 604800
                }
              },
              "additional_rate_limits": [
                {
                  "type": "spark",
                  "label": "Spark",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 99,
                      "limit_window_seconds": 18000
                    }
                  }
                }
              ]
            }
            """.utf8
        )

        let usage = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)

        XCTAssertEqual(usage.rateLimit?.primaryWindow?.usedPercent, 41)
        XCTAssertEqual(usage.rateLimit?.secondaryWindow?.usedPercent, 22)
        XCTAssertEqual(usage.additionalRateLimits?.count, 1)
        XCTAssertEqual(usage.additionalRateLimits?.first?.type, "spark")
        XCTAssertEqual(usage.additionalRateLimits?.first?.rateLimit?.primaryWindow?.usedPercent, 99)
        XCTAssertEqual(usage.rateLimit?.weeklyWindow?.usedPercent, 22)
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
        var openAIHeaderSnapshots: [[String: String?]] = []
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
            case "/openai", "/credits":
                openAIHeaderSnapshots.append([
                    "Authorization": request.value(forHTTPHeaderField: "Authorization"),
                    "Content-Type": request.value(forHTTPHeaderField: "Content-Type"),
                    "OpenAI-Beta": request.value(forHTTPHeaderField: "OpenAI-Beta"),
                    "Originator": request.value(forHTTPHeaderField: "Originator"),
                    "Chatgpt-Account-Id": request.value(forHTTPHeaderField: "Chatgpt-Account-Id")
                ])
                if request.url?.path == "/openai" {
                    return (
                        response,
                        Data(#"{"account_id":"acct-discovered","rate_limit":{"primary_window":{"used_percent":43}}}"#.utf8)
                    )
                }
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

        let service = makeService(
            session: session,
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            elevenLabsSubscriptionEndpoint: URL(string: "https://example.com/elevenlabs")!,
            credentialsStore: store
        )

        await service.fetchAll()

        XCTAssertEqual(service.cursorUsage?.planUsage?.apiPercentUsed, 6)
        XCTAssertEqual(service.openAIUsage?.rateLimit?.primaryWindow?.usedPercent, 43)
        XCTAssertEqual(service.elevenLabsUsage?.creditsRemaining, 9000)
        XCTAssertEqual(service.openAICredentialSource, .pasted)
        XCTAssertEqual(service.cursorCredentialSource, .pasted)
        XCTAssertEqual(service.openAIAccountID, "acct-discovered")
        XCTAssertEqual(openAIHeaderSnapshots.count, 2)
        for headers in openAIHeaderSnapshots {
            XCTAssertEqual(headers["Authorization"] ?? nil, "Bearer openai-token")
            XCTAssertEqual(headers["Content-Type"] ?? nil, "application/json")
            XCTAssertEqual(headers["OpenAI-Beta"] ?? nil, "codex-1")
            XCTAssertEqual(headers["Originator"] ?? nil, "Codex Desktop")
        }
        XCTAssertNil(openAIHeaderSnapshots[0]["Chatgpt-Account-Id"] ?? nil)
        XCTAssertEqual(openAIHeaderSnapshots[1]["Chatgpt-Account-Id"] ?? nil, "acct-discovered")
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

        let service = makeService(
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
        var openAIHeaderSnapshots: [[String: String?]] = []
        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path == "/openai" || request.url?.path == "/credits" {
                openAIHeaderSnapshots.append([
                    "Authorization": request.value(forHTTPHeaderField: "Authorization"),
                    "Content-Type": request.value(forHTTPHeaderField: "Content-Type"),
                    "OpenAI-Beta": request.value(forHTTPHeaderField: "OpenAI-Beta"),
                    "Originator": request.value(forHTTPHeaderField: "Originator"),
                    "Chatgpt-Account-Id": request.value(forHTTPHeaderField: "Chatgpt-Account-Id")
                ])
            }
            if request.url?.path == "/openai" {
                authorizedToken = request.value(forHTTPHeaderField: "Authorization")
                accountHeader = request.value(forHTTPHeaderField: "Chatgpt-Account-Id")
                return (response, Data(#"{"rate_limit":{"primary_window":{"used_percent":2}}}"#.utf8))
            }
            if request.url?.path == "/credits" {
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let cliService = makeService(
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
        XCTAssertEqual(openAIHeaderSnapshots.count, 2)
        for headers in openAIHeaderSnapshots {
            XCTAssertEqual(headers["Content-Type"] ?? nil, "application/json")
            XCTAssertEqual(headers["OpenAI-Beta"] ?? nil, "codex-1")
            XCTAssertEqual(headers["Originator"] ?? nil, "Codex Desktop")
            XCTAssertEqual(headers["Chatgpt-Account-Id"] ?? nil, "acct-cli")
            XCTAssertEqual(headers["Authorization"] ?? nil, "Bearer \(cliToken)")
        }
        XCTAssertEqual(
            cliService.openAITokenExpiry?.timeIntervalSince1970 ?? -1,
            Double(Int(exp.timeIntervalSince1970)),
            accuracy: 0.5
        )

        authorizedToken = nil
        openAIHeaderSnapshots = []
        let envService = makeService(
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

    func testOpenAIAccountIDClearsWhenCredentialSourceChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        let session = makeSession()
        var accountHeaders: [String?] = []

        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path == "/openai" {
                accountHeaders.append(request.value(forHTTPHeaderField: "Chatgpt-Account-Id"))
                return (response, Data(#"{"rate_limit":{"primary_window":{"used_percent":1}}}"#.utf8))
            }
            if request.url?.path == "/credits" {
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            }
            throw URLError(.badURL)
        }

        var cliCredentials = CodexCLICredentials(
            accessToken: "cli-token",
            accountId: "acct-cli",
            lastRefresh: nil
        )
        let service = makeService(
            session: session,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            codexAuthLoader: { cliCredentials }
        )

        await service.fetchOpenAIUsage()
        XCTAssertEqual(service.openAIAccountID, "acct-cli")
        XCTAssertEqual(accountHeaders.last ?? nil, "acct-cli")

        try store.save(ConnectedServiceCredentials(openAISessionToken: "pasted-token"))
        await service.fetchOpenAIUsage()
        XCTAssertNil(service.openAIAccountID)
        XCTAssertNil(accountHeaders.last ?? nil)

        try store.save(ConnectedServiceCredentials())
        cliCredentials = CodexCLICredentials(
            accessToken: "cli-token-rewritten",
            accountId: nil,
            lastRefresh: nil
        )
        await service.fetchOpenAIUsage()
        XCTAssertNil(service.openAIAccountID)
        XCTAssertNil(accountHeaders.last ?? nil)
    }

    func testStaleOpenAIUsageResponseDoesNotOverwriteClearedAccountID() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        let session = makeSession()
        let requestStarted = ConnectedAsyncGate()
        let releaseResponse = DispatchSemaphore(value: 0)

        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path == "/openai" {
                Task { await requestStarted.open() }
                let waited = releaseResponse.wait(timeout: .now() + 5)
                precondition(waited == .success, "stale OpenAI usage response was not released")
                return (
                    response,
                    Data(#"{"account_id":"acct-stale","rate_limit":{"primary_window":{"used_percent":9}}}"#.utf8)
                )
            }
            if request.url?.path == "/credits" {
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let service = makeService(
            session: session,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            codexAuthLoader: {
                CodexCLICredentials(
                    accessToken: "cli-token-a",
                    accountId: "acct-a",
                    lastRefresh: nil
                )
            }
        )

        async let fetchDone: Void = service.fetchOpenAIUsage()
        await requestStarted.wait()
        XCTAssertEqual(service.openAIAccountID, "acct-a")

        try service.saveOpenAIToken("pasted-token-b")
        XCTAssertNil(service.openAIAccountID)

        releaseResponse.signal()
        await fetchDone

        XCTAssertNil(service.openAIAccountID)
    }

    func testDeviceSyncCredentialsExcludeCLITokens() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)

        let cliOnly = makeService(
            credentialsStore: store,
            environment: [:],
            codexAuthLoader: {
                CodexCLICredentials(accessToken: "cli-openai", accountId: "acct", lastRefresh: nil)
            },
            cursorKeychainRunner: { _, _ in "cli-cursor" }
        )
        let cliSync = cliOnly.deviceSyncCredentials()
        XCTAssertNil(cliSync.openAISessionToken)
        XCTAssertNil(cliSync.cursorSessionToken)
        XCTAssertTrue(cliOnly.isOpenAIConfigured)
        XCTAssertTrue(cliOnly.isCursorConfigured)

        try store.save(
            ConnectedServiceCredentials(
                openAISessionToken: "pasted-openai",
                cursorSessionToken: "pasted-cursor"
            )
        )
        let pasted = makeService(
            credentialsStore: store,
            environment: [:],
            codexAuthLoader: {
                CodexCLICredentials(accessToken: "cli-openai", accountId: "acct", lastRefresh: nil)
            },
            cursorKeychainRunner: { _, _ in "cli-cursor" }
        )
        let pastedSync = pasted.deviceSyncCredentials()
        XCTAssertEqual(pastedSync.openAISessionToken, "pasted-openai")
        XCTAssertEqual(pastedSync.cursorSessionToken, "pasted-cursor")

        try store.save(ConnectedServiceCredentials())
        let envOnly = makeService(
            credentialsStore: store,
            environment: [
                "OPENAI_SESSION_TOKEN": "env-openai",
                "CURSOR_SESSION_TOKEN": "env-cursor"
            ]
        )
        let envSync = envOnly.deviceSyncCredentials()
        XCTAssertEqual(envSync.openAISessionToken, "env-openai")
        XCTAssertEqual(envSync.cursorSessionToken, "env-cursor")
    }

    func testCursorCredentialPrecedencePrefersPastedOverCLIAndEnvironment() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(cursorSessionToken: "pasted-cursor"))
        let session = makeSession()
        var usedCookie = false
        var usedConnect = false

        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path == "/cursor" {
                usedCookie = true
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Cookie"),
                    "WorkosCursorSessionToken=pasted-cursor"
                )
                return (response, Data(#"{"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2}}"#.utf8))
            }
            if (request.url?.path ?? "").contains("GetCurrentPeriodUsage")
                || (request.url?.path ?? "").contains("GetPlanInfo") {
                usedConnect = true
            }
            throw URLError(.badURL)
        }

        let service = makeService(
            session: session,
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            credentialsStore: store,
            environment: ["CURSOR_SESSION_TOKEN": "env-cursor"],
            cursorKeychainRunner: { _, _ in "cli-cursor" }
        )
        await service.fetchCursorUsage()

        XCTAssertEqual(service.cursorCredentialSource, .pasted)
        XCTAssertTrue(usedCookie)
        XCTAssertFalse(usedConnect)
        XCTAssertNil(service.cursorPlanInfo)
    }

    func testCursorFallsBackToCLIThenEnvironment() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        let session = makeSession()
        var connectAuth: String?
        var cookieAuth: String?

        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let path = request.url?.path ?? ""
            if path.contains("GetCurrentPeriodUsage") {
                connectAuth = request.value(forHTTPHeaderField: "Authorization")
                return (response, Data(#"{"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2}}"#.utf8))
            }
            if path.contains("GetPlanInfo") {
                return (
                    response,
                    Data(#"{"planInfo":{"planName":"Pro","includedAmountCents":2000,"price":"$20/mo"}}"#.utf8)
                )
            }
            if path == "/cursor" {
                cookieAuth = request.value(forHTTPHeaderField: "Cookie")
                return (response, Data(#"{"planUsage":{"autoPercentUsed":3,"apiPercentUsed":4}}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let cliService = makeService(
            session: session,
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            credentialsStore: store,
            environment: ["CURSOR_SESSION_TOKEN": "env-cursor"],
            cursorKeychainRunner: { _, _ in "cli-cursor" }
        )
        await cliService.fetchCursorUsage()
        XCTAssertEqual(cliService.cursorCredentialSource, .cursorCLI)
        XCTAssertEqual(connectAuth, "Bearer cli-cursor")
        XCTAssertNil(cookieAuth)

        connectAuth = nil
        let envService = makeService(
            session: session,
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            credentialsStore: store,
            environment: ["CURSOR_SESSION_TOKEN": "env-cursor"],
            cursorKeychainRunner: { _, _ in "" }
        )
        await envService.fetchCursorUsage()
        XCTAssertEqual(envService.cursorCredentialSource, .environment)
        XCTAssertEqual(cookieAuth, "WorkosCursorSessionToken=env-cursor")
        XCTAssertNil(envService.cursorPlanInfo)
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

        let service = makeService(
            session: session,
            credentialsStore: store,
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

    func testFailedCursorPlanInfoIsThrottledToOncePerHour() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        let session = makeSession()
        var planInfoCount = 0

        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let path = request.url?.path ?? ""
            if path.contains("GetCurrentPeriodUsage") {
                return (response, Data(#"{"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2}}"#.utf8))
            }
            if path.contains("GetPlanInfo") {
                planInfoCount += 1
                let failure = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (failure, Data())
            }
            throw URLError(.badURL)
        }

        let service = makeService(
            session: session,
            credentialsStore: store,
            cursorKeychainRunner: { _, _ in "cli-cursor" },
            planInfoInterval: 3600
        )

        await service.fetchCursorUsage()
        await service.fetchCursorUsage()
        await service.fetchCursorUsage()

        XCTAssertEqual(planInfoCount, 1)
        XCTAssertNil(service.cursorPlanInfo)
        XCTAssertEqual(service.cursorUsage?.planUsage?.apiPercentUsed, 2)
        XCTAssertNil(service.cursorError)
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

        let pasted = makeService(
            session: session,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store
        )
        await pasted.fetchOpenAIUsage()
        XCTAssertEqual(pasted.openAIError?.contains("OpenAI session expired"), true)
        XCTAssertEqual(pasted.openAIError?.contains("Settings"), true)

        try store.save(ConnectedServiceCredentials())
        let cli = makeService(
            session: session,
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            codexAuthLoader: {
                CodexCLICredentials(accessToken: "cli", accountId: nil, lastRefresh: nil)
            }
        )
        await cli.fetchOpenAIUsage()
        XCTAssertEqual(
            cli.openAIError,
            "Codex login expired. Run any codex command or `codex login` to refresh."
        )

        let cursorCLI = makeService(
            session: session,
            credentialsStore: store,
            cursorKeychainRunner: { _, _ in "cursor-cli-token" }
        )
        await cursorCLI.fetchCursorUsage()
        XCTAssertEqual(
            cursorCLI.cursorError,
            "Cursor CLI login expired. Run `cursor-agent login`."
        )

        try store.save(ConnectedServiceCredentials(cursorSessionToken: "pasted-cursor"))
        let cursorPasted = makeService(
            session: session,
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            credentialsStore: store
        )
        await cursorPasted.fetchCursorUsage()
        XCTAssertEqual(cursorPasted.cursorError?.contains("Cursor session expired"), true)
        XCTAssertEqual(cursorPasted.cursorError?.contains("Settings"), true)
    }

    // MARK: - Use reset (#56)

    private static let consumePath = "/backend-api/wham/rate-limit-reset-credits/consume"

    /// Three eligible `codex_rate_limits` credits plus one used one and one other reset type.
    /// `available_count` matches the eligible set redemption picks from (not every available credit).
    /// `soon` expires first among eligible credits; `other` expires sooner still but must never be picked.
    private static let resetCreditsFixture = #"""
    {
      "credits": [
        {"id": "later", "reset_type": "codex_rate_limits", "status": "available", "expires_at": "2026-10-20T00:00:00Z"},
        {"id": "soon", "reset_type": "codex_rate_limits", "status": "available", "expires_at": "2026-09-21T00:00:00Z"},
        {"id": "other", "reset_type": "something_else", "status": "available", "expires_at": "2026-09-12T00:00:00Z"},
        {"id": "used", "reset_type": "codex_rate_limits", "status": "redeemed", "expires_at": "2026-09-11T00:00:00Z"},
        {"id": "undated", "reset_type": "codex_rate_limits", "status": "available"}
      ],
      "available_count": 3
    }
    """#

    private struct ResetStub {
        var consumeBodies: [[String: String]] = []
        var consumeAccountHeaders: [String?] = []
        var usageFetches = 0
        var consumeResponse: (status: Int, body: String) = (200, #"{"code":"reset"}"#)
        var usageStatusAfterConsume = 200
    }

    /// Serves usage, credits, and the consume endpoint from the fixture; records every consume body.
    private func installResetStub(_ box: ResetStubBox) {
        ConnectedMockURLProtocol.handler = { request in
            func response(_ status: Int) -> HTTPURLResponse {
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            }
            switch request.url?.path {
            case "/openai":
                box.stub.usageFetches += 1
                let status = box.stub.consumeBodies.isEmpty ? 200 : box.stub.usageStatusAfterConsume
                return (
                    response(status),
                    Data(#"{"plan_type":"plus","account_id":"acct-1","rate_limit":{"primary_window":{"used_percent":90}}}"#.utf8)
                )
            case "/credits":
                return (response(200), Data(Self.resetCreditsFixture.utf8))
            case Self.consumePath:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "codex-1")
                box.stub.consumeAccountHeaders.append(request.value(forHTTPHeaderField: "Chatgpt-Account-Id"))
                let body = try XCTUnwrap(Self.bodyData(of: request))
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
                box.stub.consumeBodies.append(object)
                let reply = box.stub.consumeResponse
                return (response(reply.status), Data(reply.body.utf8))
            default:
                throw URLError(.badURL)
            }
        }
    }

    private final class ResetStubBox {
        var stub = ResetStub()
    }

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private func makeResetService(box: ResetStubBox) throws -> (ConnectedUsageService, UserDefaults, String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(openAISessionToken: "openai-token"))
        let suiteName = "ConnectedUsageServiceTests.reset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        installResetStub(box)
        let session = makeSession()
        let redeemer = OpenAIResetCreditRedeemer(session: session, defaults: defaults)
        let service = makeService(session: session, credentialsStore: store, resetCreditRedeemer: redeemer)
        return (service, defaults, suiteName)
    }

    func testRedeemPicksSoonestExpiringCodexCreditAndReportsReset() async throws {
        let box = ResetStubBox()
        let (service, defaults, suiteName) = try makeResetService(box: box)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        await service.fetchOpenAIUsage()
        XCTAssertEqual(service.availableResetCredits.map(\.id), ["soon", "later", "undated"])
        XCTAssertEqual(service.availableResetCredits.count, service.openAIResetCredits?.availableCount)
        XCTAssertEqual(
            UsageDetailRows.resetCreditsLine(
                count: service.availableResetCredits.count,
                nextExpiry: service.availableResetCredits.first?.expiresAtDate
            )?.hasPrefix("3 banked"),
            true
        )
        XCTAssertEqual(service.nextResetCredit?.id, "soon")
        XCTAssertEqual(service.openAIAccountID, "acct-1")
        let updatedBefore = try XCTUnwrap(service.openAILastUpdated)

        await service.redeemNextResetCredit()

        XCTAssertEqual(box.stub.consumeBodies.count, 1)
        XCTAssertEqual(box.stub.consumeBodies.first?["credit_id"], "soon")
        XCTAssertEqual(
            box.stub.consumeBodies.first?["redeem_request_id"],
            OpenAIResetCreditRedemption.requestID(accountID: "acct-1", creditID: "soon").uuidString.lowercased()
        )
        XCTAssertEqual(box.stub.consumeAccountHeaders, ["acct-1"])
        XCTAssertEqual(box.stub.usageFetches, 2)
        XCTAssertEqual(service.resetCreditOutcome?.message, "Limits reset")
        let updatedAfter = try XCTUnwrap(service.openAILastUpdated)
        XCTAssertGreaterThan(updatedAfter, updatedBefore)
        XCTAssertFalse(service.isRedeemingResetCredit)
    }

    func testRedeemReportsCouldNotConfirmWhenUsageDoesNotAdvance() async throws {
        let box = ResetStubBox()
        let (service, defaults, suiteName) = try makeResetService(box: box)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        box.stub.usageStatusAfterConsume = 500

        await service.fetchOpenAIUsage()
        let updatedBefore = service.openAILastUpdated

        await service.redeemNextResetCredit()

        XCTAssertEqual(box.stub.consumeBodies.count, 1)
        XCTAssertEqual(service.openAILastUpdated, updatedBefore)
        XCTAssertEqual(service.resetCreditOutcome?.message, ConnectedUsageService.resetUnconfirmedMessage)
        XCTAssertEqual(
            service.resetCreditOutcome?.message,
            "The reset was applied, but Codex could not confirm the new limits. Refresh to check."
        )
    }

    func testRedeemOtherOutcomesAndErrorsSetTheirOwnMessages() async throws {
        let box = ResetStubBox()
        let (service, defaults, suiteName) = try makeResetService(box: box)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await service.fetchOpenAIUsage()

        box.stub.consumeResponse = (200, #"{"code":"nothing_to_reset"}"#)
        await service.redeemNextResetCredit()
        XCTAssertEqual(service.resetCreditOutcome?.message, "Nothing to reset yet")
        XCTAssertEqual(box.stub.usageFetches, 1, "no confirming refresh for nothing_to_reset")

        box.stub.consumeResponse = (200, #"{"code":"no_credit"}"#)
        await service.redeemNextResetCredit()
        XCTAssertEqual(service.resetCreditOutcome?.message, "No credit available")

        box.stub.consumeResponse = (503, "nope")
        await service.redeemNextResetCredit()
        XCTAssertEqual(service.resetCreditOutcome?.message, "Codex HTTP 503")

        box.stub.consumeResponse = (200, "not json")
        await service.redeemNextResetCredit()
        XCTAssertEqual(service.resetCreditOutcome?.message, "Codex returned an invalid response")

        box.stub.consumeResponse = (200, #"{"code":"already_redeemed"}"#)
        await service.redeemNextResetCredit()
        XCTAssertEqual(service.resetCreditOutcome?.message, "Already redeemed")
        XCTAssertEqual(box.stub.usageFetches, 2, "already_redeemed refreshes to confirm, like reset")
    }

    func testRedeemWithoutAnEligibleCreditReportsNoCreditWithoutCalling() async throws {
        let box = ResetStubBox()
        let (service, defaults, suiteName) = try makeResetService(box: box)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        await service.redeemNextResetCredit()

        XCTAssertEqual(service.resetCreditOutcome?.message, "No credit available")
        XCTAssertTrue(box.stub.consumeBodies.isEmpty)
    }

    func testRedeemInFlightGuardDropsASecondCall() async throws {
        let box = ResetStubBox()
        let (service, defaults, suiteName) = try makeResetService(box: box)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        await service.fetchOpenAIUsage()

        let started = expectation(description: "consume started")
        let gate = DispatchSemaphore(value: 0)
        let inner = ConnectedMockURLProtocol.handler
        ConnectedMockURLProtocol.handler = { request in
            if request.url?.path == Self.consumePath {
                started.fulfill()
                gate.wait()
            }
            return try inner!(request)
        }

        let first = Task { await service.redeemNextResetCredit() }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(service.isRedeemingResetCredit)
        XCTAssertTrue(service.resetCreditRedeemer.isRedeeming)

        await service.redeemNextResetCredit()
        XCTAssertNil(service.resetCreditOutcome, "the dropped call leaves no message")

        gate.signal()
        await first.value

        XCTAssertEqual(box.stub.consumeBodies.count, 1)
        XCTAssertEqual(service.resetCreditOutcome?.message, "Limits reset")
        XCTAssertFalse(service.isRedeemingResetCredit)
    }

    /// Credits and credential source stay available when the usage endpoint fails.
    func testResetCreditsAndSourceSurviveUsageFetchFailure() async throws {
        let box = ResetStubBox()
        let (service, defaults, suiteName) = try makeResetService(box: box)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ConnectedMockURLProtocol.handler = { request in
            func response(_ status: Int) -> HTTPURLResponse {
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            }
            switch request.url?.path {
            case "/openai":
                return (response(401), Data(#"{"error":"unauthorized"}"#.utf8))
            case "/credits":
                return (response(200), Data(Self.resetCreditsFixture.utf8))
            default:
                throw URLError(.badURL)
            }
        }

        await service.fetchOpenAIUsage()

        XCTAssertNil(service.openAIUsage)
        XCTAssertNotNil(service.openAIError)
        XCTAssertEqual(service.openAICredentialSource, .pasted)
        XCTAssertEqual(service.availableResetCredits.map(\.id), ["soon", "later", "undated"])
        XCTAssertEqual(service.availableResetCredits.count, 3)
        XCTAssertEqual(
            UsageDetailRows.codexSourceLine(
                source: service.openAICredentialSource,
                tokenExpiry: service.openAITokenExpiry
            ),
            "Source: pasted token"
        )
        XCTAssertEqual(
            UsageDetailRows.resetCreditsLine(
                count: service.availableResetCredits.count,
                nextExpiry: service.availableResetCredits.first?.expiresAtDate
            )?.hasPrefix("3 banked"),
            true
        )
    }

    /// Cursor credential source stays known when the usage endpoint fails.
    func testCursorSourceSurvivesUsageFetchFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(cursorSessionToken: "pasted-cursor"))
        let session = makeSession()

        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path == "/cursor" {
                return (response, Data(#"{"error":"unauthorized"}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let service = makeService(
            session: session,
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            credentialsStore: store
        )
        await service.fetchCursorUsage()

        XCTAssertNil(service.cursorUsage)
        XCTAssertNotNil(service.cursorError)
        XCTAssertEqual(service.cursorCredentialSource, .pasted)
        XCTAssertEqual(
            UsageDetailRows.cursorSourceLine(
                source: service.cursorCredentialSource,
                tokenExpiry: service.cursorTokenExpiry
            ),
            "Source: pasted cookie"
        )
    }

    func testOpenAI429WithRetryAfterSetsBackoffAndSkipsScheduledPoll() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(openAISessionToken: "openai-token"))

        var openAIHits = 0
        var creditHits = 0
        ConnectedMockURLProtocol.handler = { request in
            if request.url?.path == "/openai" {
                openAIHits += 1
                XCTAssertEqual(request.timeoutInterval, PollingBackoff.usageRequestTimeout)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "900"]
                )!
                return (response, Data())
            }
            if request.url?.path == "/credits" {
                creditHits += 1
                XCTFail("Credits must not run after a usage 429")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let service = makeService(
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            lowPowerModeEnabled: { false }
        )
        service.updatePollingInterval(5)

        let before = Date()
        await service.fetchOpenAIUsage(trigger: .manual)
        XCTAssertEqual(openAIHits, 1)
        XCTAssertEqual(creditHits, 0)
        XCTAssertEqual(service.openAIError, "OpenAI rate limited")
        // base 5m doubled is 10m; Retry-After 900s must win over that floor.
        XCTAssertEqual(service.openAIBackoffInterval, 900)
        let until = try XCTUnwrap(service.openAIBackoffUntil)
        XCTAssertGreaterThanOrEqual(until.timeIntervalSince(before), 899)

        await service.fetchOpenAIUsage(trigger: .scheduled)
        XCTAssertEqual(openAIHits, 1, "Scheduled poll must skip while backoff is active")

        await service.fetchOpenAIUsage(trigger: .automatic)
        XCTAssertEqual(openAIHits, 1, "Automatic refresh must honour backoff")

        await service.fetchOpenAIUsage(trigger: .manual)
        XCTAssertEqual(openAIHits, 2, "Manual refresh may bypass backoff")
        XCTAssertEqual(creditHits, 0)
    }

    func testOpenAI429WithoutRetryAfterStillBacksOff() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(openAISessionToken: "openai-token"))

        var openAIHits = 0
        ConnectedMockURLProtocol.handler = { request in
            if request.url?.path == "/openai" {
                openAIHits += 1
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            }
            if request.url?.path == "/credits" {
                XCTFail("Credits must not run after a usage 429")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let service = makeService(
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            lowPowerModeEnabled: { false }
        )
        service.updatePollingInterval(5)

        await service.fetchOpenAIUsage(trigger: .manual)
        XCTAssertEqual(openAIHits, 1)
        XCTAssertEqual(service.openAIBackoffInterval, 10 * 60)
        await service.fetchOpenAIUsage(trigger: .scheduled)
        XCTAssertEqual(openAIHits, 1)
    }

    func testConnectedLowPowerRescheduleUpdatesEffectiveInterval() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        var lowPower = false
        let service = makeService(credentialsStore: store, lowPowerModeEnabled: { lowPower })
        service.updatePollingInterval(15)
        XCTAssertEqual(service.effectivePollingInterval, 15 * 60)
        XCTAssertEqual(service.installedPollingInterval, 15 * 60)

        lowPower = true
        service.rescheduleForPowerState()
        XCTAssertEqual(service.effectivePollingInterval, 30 * 60)
        XCTAssertEqual(
            service.installedPollingInterval,
            30 * 60,
            "Reschedule must replace the installed timer with the doubled interval"
        )

        lowPower = false
        service.rescheduleForPowerState()
        XCTAssertEqual(service.effectivePollingInterval, 15 * 60)
        XCTAssertEqual(service.installedPollingInterval, 15 * 60)

        service.pausePolling()
        XCTAssertNil(service.installedPollingInterval)
    }

    func testScheduledThenManualOpenAIRunsTrailingRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(openAISessionToken: "openai-token"))

        let requestStarted = ConnectedAsyncGate()
        let releaseResponse = DispatchSemaphore(value: 0)
        var openAIHits = 0
        ConnectedMockURLProtocol.handler = { request in
            if request.url?.path == "/openai" {
                openAIHits += 1
                Task { await requestStarted.open() }
                let waited = releaseResponse.wait(timeout: .now() + 5)
                precondition(waited == .success, "openai response was not released")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (
                    response,
                    Data(#"{"rate_limit":{"primary_window":{"used_percent":10},"secondary_window":{"used_percent":20}}}"#.utf8)
                )
            }
            if request.url?.path == "/credits" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let service = makeService(
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store
        )

        async let scheduled: Void = service.fetchOpenAIUsage(trigger: .scheduled)
        await requestStarted.wait()
        XCTAssertEqual(openAIHits, 1)

        async let manual1: Void = service.fetchOpenAIUsage(trigger: .manual)
        async let manual2: Void = service.fetchOpenAIUsage(trigger: .manual)
        await Task.yield()
        await Task.yield()

        releaseResponse.signal()
        // Trailing refresh needs its own permit.
        releaseResponse.signal()
        _ = await (scheduled, manual1, manual2)

        XCTAssertEqual(
            openAIHits,
            2,
            "Scheduled-then-manual must run exactly one trailing usage request"
        )
    }

    func testOpenAIFailedManualUsageDoesNotClearBackoffFromStaleUsage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(openAISessionToken: "openai-token"))

        var openAIHits = 0
        var phase = 0
        ConnectedMockURLProtocol.handler = { request in
            if request.url?.path == "/openai" {
                openAIHits += 1
                let status: Int
                switch phase {
                case 0:
                    status = 200
                case 1:
                    status = 429
                default:
                    status = 500
                }
                var headers: [String: String]?
                if status == 429 {
                    headers = ["Retry-After": "600"]
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: headers
                )!
                if status == 200 {
                    return (
                        response,
                        Data(#"{"rate_limit":{"primary_window":{"used_percent":10},"secondary_window":{"used_percent":20}}}"#.utf8)
                    )
                }
                return (response, Data())
            }
            if request.url?.path == "/credits" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
            }
            throw URLError(.badURL)
        }

        let service = makeService(
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store,
            lowPowerModeEnabled: { false }
        )
        service.updatePollingInterval(5)

        // Prior successful usage leaves openAIUsage non-nil.
        phase = 0
        await service.fetchOpenAIUsage(trigger: .manual)
        XCTAssertNotNil(service.openAIUsage)
        XCTAssertNil(service.openAIBackoffUntil)

        // 429 establishes backoff.
        phase = 1
        await service.fetchOpenAIUsage(trigger: .manual)
        XCTAssertEqual(service.openAIBackoffInterval, 600)
        let untilAfter429 = try XCTUnwrap(service.openAIBackoffUntil)

        // Failed usage (500) plus successful credits must not clear that backoff
        // just because openAIUsage is still set from the earlier success.
        phase = 2
        await service.fetchOpenAIUsage(trigger: .manual)
        XCTAssertEqual(openAIHits, 3)
        XCTAssertEqual(service.openAIBackoffUntil, untilAfter429)
        XCTAssertEqual(service.openAIBackoffInterval, 600)
        XCTAssertNotNil(service.openAIUsage, "Stale prior usage remains on the service")

        await service.fetchOpenAIUsage(trigger: .scheduled)
        XCTAssertEqual(openAIHits, 3, "Scheduled poll must still honour backoff")
    }

    func testCursorScheduledFetchDebouncesWhenFresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(cursorSessionToken: "cursor-token"))

        var cursorHits = 0
        ConnectedMockURLProtocol.handler = { request in
            cursorHits += 1
            XCTAssertEqual(request.timeoutInterval, PollingBackoff.usageRequestTimeout)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2}}"#.utf8))
        }

        let service = makeService(
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            credentialsStore: store
        )

        await service.fetchCursorUsage(force: true)
        XCTAssertEqual(cursorHits, 1)
        await service.fetchCursorUsage(force: false)
        XCTAssertEqual(cursorHits, 1)
        await service.fetchCursorUsage(force: true)
        XCTAssertEqual(cursorHits, 2)
    }

    func testManualCursorFetchIsSingleFlight() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(cursorSessionToken: "cursor-token"))

        let requestStarted = ConnectedAsyncGate()
        let releaseResponse = DispatchSemaphore(value: 0)
        var cursorHits = 0
        ConnectedMockURLProtocol.handler = { request in
            cursorHits += 1
            Task { await requestStarted.open() }
            let waited = releaseResponse.wait(timeout: .now() + 5)
            precondition(waited == .success, "cursor response was not released")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"planUsage":{"autoPercentUsed":1,"apiPercentUsed":2}}"#.utf8))
        }

        let service = makeService(
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            credentialsStore: store
        )

        async let first: Void = service.fetchCursorUsage(force: true)
        async let second: Void = service.fetchCursorUsage(force: true)
        await requestStarted.wait()
        XCTAssertEqual(cursorHits, 1)
        releaseResponse.signal()
        _ = await (first, second)
        XCTAssertEqual(cursorHits, 1)
        XCTAssertEqual(service.cursorUsage?.planUsage?.apiPercentUsed, 2)
    }

    func testFetchAllIncrementsPollCompletionCountOnFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(cursorSessionToken: "cursor-token"))

        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = makeService(
            cursorEndpoint: URL(string: "https://example.com/cursor")!,
            credentialsStore: store
        )

        XCTAssertEqual(service.pollCompletionCount, 0)
        await service.fetchAll(force: true)
        XCTAssertEqual(service.pollCompletionCount, 1)
        XCTAssertNotNil(service.cursorError)
    }

    func testFetchOpenAIKeepsSparkRowsWithoutChangingPrimary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConnectedServiceCredentialsStore(directoryURL: directory)
        try store.save(ConnectedServiceCredentials(openAISessionToken: "openai-token"))

        ConnectedMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.path == "/openai" {
                return (
                    response,
                    Data(
                        """
                        {
                          "rate_limit": {
                            "primary_window": {"used_percent": 41, "limit_window_seconds": 18000},
                            "secondary_window": {"used_percent": 22, "limit_window_seconds": 604800}
                          },
                          "additional_rate_limits": [
                            {
                              "type": "spark",
                              "label": "Spark",
                              "rate_limit": {
                                "primary_window": {"used_percent": 99, "limit_window_seconds": 18000}
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            return (response, Data(#"{"credits":[],"available_count":0}"#.utf8))
        }

        let service = makeService(
            openAIUsageEndpoint: URL(string: "https://example.com/openai")!,
            openAIResetCreditsEndpoint: URL(string: "https://example.com/credits")!,
            credentialsStore: store
        )

        await service.fetchOpenAIUsage(force: true)

        XCTAssertEqual(service.openAIUsage?.rateLimit?.primaryWindow?.usedPercent, 41)
        XCTAssertEqual(service.openAIUsage?.rateLimit?.secondaryWindow?.usedPercent, 22)
        XCTAssertEqual(service.openAIUsage?.additionalRateLimits?.first?.type, "spark")
        XCTAssertEqual(
            service.openAIUsage?.additionalRateLimits?.first?.rateLimit?.primaryWindow?.usedPercent,
            99
        )
    }

    private func makeService(
        session: URLSession? = nil,
        cursorEndpoint: URL = URL(string: "https://example.com/cursor")!,
        openAIUsageEndpoint: URL = URL(string: "https://example.com/openai")!,
        openAIResetCreditsEndpoint: URL = URL(string: "https://example.com/credits")!,
        elevenLabsSubscriptionEndpoint: URL = URL(string: "https://example.com/elevenlabs")!,
        credentialsStore: ConnectedServiceCredentialsStore,
        environment: [String: String] = [:],
        codexAuthLoader: (() -> CodexCLICredentials?)? = nil,
        cursorKeychainRunner: CursorCLIKeychain.Runner? = nil,
        planInfoInterval: TimeInterval = 3600,
        resetCreditRedeemer: OpenAIResetCreditRedeemer? = nil,
        lowPowerModeEnabled: @escaping () -> Bool = { false }
    ) -> ConnectedUsageService {
        ConnectedUsageService(
            session: session ?? makeSession(),
            cursorEndpoint: cursorEndpoint,
            openAIUsageEndpoint: openAIUsageEndpoint,
            openAIResetCreditsEndpoint: openAIResetCreditsEndpoint,
            elevenLabsSubscriptionEndpoint: elevenLabsSubscriptionEndpoint,
            credentialsStore: credentialsStore,
            environment: environment,
            codexAuthLoader: codexAuthLoader ?? { nil },
            cursorKeychainRunner: cursorKeychainRunner ?? { _, _ in "" },
            planInfoInterval: planInfoInterval,
            resetCreditRedeemer: resetCreditRedeemer,
            lowPowerModeEnabled: lowPowerModeEnabled
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

private actor ConnectedAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
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
