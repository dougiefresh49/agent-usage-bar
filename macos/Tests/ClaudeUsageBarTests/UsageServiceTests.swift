import XCTest
@testable import AgentUsageBar

@MainActor
final class UsageServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testBackoffIntervalCapsAtSixtyMinutes() {
        XCTAssertEqual(
            UsageService.backoffInterval(retryAfter: 120, currentInterval: 30 * 60),
            60 * 60
        )
    }

    func testBackoffIntervalNeverReducesSixtyMinutePolling() {
        XCTAssertEqual(
            UsageService.backoffInterval(retryAfter: 120, currentInterval: 60 * 60),
            60 * 60
        )
    }

    func testFetchUsageRefreshesOn401AndRetriesOnce() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "old-access",
                refreshToken: "refresh-old",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!
        let session = makeSession()
        var requests: [String] = []

        MockURLProtocol.handler = { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
            requests.append("\(request.httpMethod ?? "GET") \(request.url?.path ?? "") \(authorization)")

            switch (request.httpMethod, request.url?.path, authorization) {
            case ("GET", "/api/oauth/usage", "Bearer old-access"):
                return try Self.httpResponse(url: usageURL, statusCode: 401)
            case ("POST", "/v1/oauth/token", _):
                let body = try XCTUnwrap(Self.jsonBody(for: request))
                XCTAssertEqual(body["grant_type"], "refresh_token")
                XCTAssertEqual(body["refresh_token"], "refresh-old")
                XCTAssertEqual(body["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
                XCTAssertEqual(body["scope"], "user:profile user:inference")

                return try Self.httpResponse(
                    url: tokenURL,
                    statusCode: 200,
                    body: """
                    {
                      "access_token": "new-access",
                      "refresh_token": "refresh-new",
                      "expires_in": 3600,
                      "scope": "user:profile user:inference"
                    }
                    """
                )
            case ("GET", "/api/oauth/usage", "Bearer new-access"):
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 200,
                    body: """
                    {
                      "five_hour": { "utilization": 12, "resets_at": "2026-03-08T18:00:00Z" },
                      "seven_day": { "utilization": 20, "resets_at": "2026-03-15T18:00:00Z" }
                    }
                    """
                )
            case ("GET", "/api/oauth/profile", _):
                return try Self.httpResponse(
                    url: URL(string: "https://example.com/api/oauth/profile")!,
                    statusCode: 200,
                    body: Self.profileFixtureBody
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: session,
            usageEndpoint: usageURL,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: tokenURL,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 12)
        XCTAssertEqual(requests.count, 4)

        let saved = try XCTUnwrap(store.load(defaultScopes: UsageService.defaultOAuthScopes))
        XCTAssertEqual(saved.accessToken, "new-access")
        XCTAssertEqual(saved.refreshToken, "refresh-new")
        XCTAssertNotNil(saved.expiresAt)
    }

    func testFetchUsageDoesNotSignOutWhenRetriedRequestIsRateLimited() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "old-access",
                refreshToken: "refresh-old",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!

        MockURLProtocol.handler = { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""

            switch (request.httpMethod, request.url?.path, authorization) {
            case ("GET", "/api/oauth/usage", "Bearer old-access"):
                return try Self.httpResponse(url: usageURL, statusCode: 401)
            case ("POST", "/v1/oauth/token", _):
                return try Self.httpResponse(
                    url: tokenURL,
                    statusCode: 200,
                    body: """
                    {
                      "access_token": "new-access",
                      "expires_in": 3600,
                      "scope": "user:profile user:inference"
                    }
                    """
                )
            case ("GET", "/api/oauth/usage", "Bearer new-access"):
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 429,
                    headers: ["Retry-After": "120"]
                )
            case ("GET", "/api/oauth/profile", _):
                return try Self.httpResponse(
                    url: URL(string: "https://example.com/api/oauth/profile")!,
                    statusCode: 200,
                    body: Self.profileFixtureBody
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: tokenURL,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated)
        XCTAssertEqual(service.lastError, "Rate limited — backing off to 3600s")

        let saved = try XCTUnwrap(store.load(defaultScopes: UsageService.defaultOAuthScopes))
        XCTAssertEqual(saved.accessToken, "new-access")
        XCTAssertEqual(saved.refreshToken, "refresh-old")
    }

    func testFetchUsageSignsOutWhenRefreshFails() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "old-access",
                refreshToken: "refresh-old",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!

        MockURLProtocol.handler = { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""

            switch (request.httpMethod, request.url?.path, authorization) {
            case ("GET", "/api/oauth/usage", "Bearer old-access"):
                return try Self.httpResponse(url: usageURL, statusCode: 401)
            case ("POST", "/v1/oauth/token", _):
                return try Self.httpResponse(
                    url: tokenURL,
                    statusCode: 400,
                    body: #"{"error":"invalid_grant"}"#
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: tokenURL,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertFalse(service.isAuthenticated)
        XCTAssertEqual(service.lastError, "Session expired — please sign in again")
        XCTAssertNil(store.load(defaultScopes: UsageService.defaultOAuthScopes))
    }

    func testFetchProfileDoesNotSignOutWhenUserinfoStillReturns401AfterRefresh() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "old-access",
                refreshToken: "refresh-old",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let userinfoURL = URL(string: "https://example.com/api/oauth/userinfo")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!

        MockURLProtocol.handler = { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""

            switch (request.httpMethod, request.url?.path, authorization) {
            case ("GET", "/api/oauth/userinfo", "Bearer old-access"):
                return try Self.httpResponse(url: userinfoURL, statusCode: 401)
            case ("POST", "/v1/oauth/token", _):
                return try Self.httpResponse(
                    url: tokenURL,
                    statusCode: 200,
                    body: """
                    {
                      "access_token": "new-access",
                      "refresh_token": "refresh-new",
                      "expires_in": 3600,
                      "scope": "user:profile user:inference"
                    }
                    """
                )
            case ("GET", "/api/oauth/userinfo", "Bearer new-access"):
                return try Self.httpResponse(url: userinfoURL, statusCode: 401)
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: URL(string: "https://example.com/api/oauth/usage")!,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: userinfoURL,
            tokenEndpoint: tokenURL,
            credentialsStore: store,
            localProfileLoader: { nil }
        )

        await service.fetchProfile()

        XCTAssertTrue(service.isAuthenticated)
        XCTAssertNil(service.accountEmail)
        XCTAssertNil(service.lastError)

        let saved = try XCTUnwrap(store.load(defaultScopes: UsageService.defaultOAuthScopes))
        XCTAssertEqual(saved.accessToken, "new-access")
        XCTAssertEqual(saved.refreshToken, "refresh-new")
    }

    // MARK: - Transient vs permanent refresh failure

    func testServer500DuringRefreshStaysAuthenticated() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "old-access",
                refreshToken: "refresh-old",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!

        MockURLProtocol.handler = { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""

            switch (request.httpMethod, request.url?.path, authorization) {
            case ("GET", "/api/oauth/usage", "Bearer old-access"):
                return try Self.httpResponse(url: usageURL, statusCode: 401)
            case ("POST", "/v1/oauth/token", _):
                return try Self.httpResponse(url: tokenURL, statusCode: 500)
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: tokenURL,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated)
        XCTAssertEqual(service.lastError, "Token refresh failed — will retry")
        XCTAssertNotNil(store.load(defaultScopes: UsageService.defaultOAuthScopes))
    }

    func testNetworkErrorDuringRefreshStaysAuthenticated() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "old-access",
                refreshToken: "refresh-old",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!

        MockURLProtocol.handler = { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""

            switch (request.httpMethod, request.url?.path, authorization) {
            case ("GET", "/api/oauth/usage", "Bearer old-access"):
                return try Self.httpResponse(url: usageURL, statusCode: 401)
            case ("POST", "/v1/oauth/token", _):
                throw URLError(.notConnectedToInternet)
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: tokenURL,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated)
        XCTAssertEqual(service.lastError, "Token refresh failed — will retry")
        XCTAssertNotNil(store.load(defaultScopes: UsageService.defaultOAuthScopes))
    }

    func testExpiredTokenWithTransientRefreshFailureDoesNotMakeAPICall() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "expired-access",
                refreshToken: "refresh-old",
                expiresAt: Date().addingTimeInterval(-60),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!
        var usageRequestCount = 0

        MockURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/oauth/token"):
                return try Self.httpResponse(url: tokenURL, statusCode: 500)
            case ("GET", "/api/oauth/usage"):
                usageRequestCount += 1
                return try Self.httpResponse(url: usageURL, statusCode: 200, body: "{}")
            case ("GET", "/api/oauth/profile"):
                return try Self.httpResponse(
                    url: URL(string: "https://example.com/api/oauth/profile")!,
                    statusCode: 200,
                    body: Self.profileFixtureBody
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: tokenURL,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated)
        XCTAssertEqual(service.lastError, "Token refresh failed — will retry")
        XCTAssertEqual(usageRequestCount, 0, "Should not make API call when token is expired and refresh failed")
    }

    func testExpiredTokenWithPermanentRefreshFailureSignsOut() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "expired-access",
                refreshToken: "refresh-old",
                expiresAt: Date().addingTimeInterval(-60),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!

        MockURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/oauth/token"):
                return try Self.httpResponse(
                    url: tokenURL,
                    statusCode: 400,
                    body: #"{"error":"invalid_grant"}"#
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: tokenURL,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertFalse(service.isAuthenticated)
        XCTAssertEqual(service.lastError, "Session expired — please sign in again")
        XCTAssertNil(store.load(defaultScopes: UsageService.defaultOAuthScopes))
    }

    // MARK: - End-to-end refresh recovery simulation

    /// Simulates three consecutive polling cycles during a refresh server outage:
    ///
    /// Poll 1: Token nearing expiry, refresh server is down (500).
    ///         Token isn't expired yet → API call proceeds → usage fetched.
    /// Poll 2: Token now expired, refresh server still down.
    ///         Proactive refresh fails, token is expired → skips API call, stays signed in.
    /// Poll 3: Refresh server recovers → refresh succeeds → usage fetched with new token.
    func testEndToEndRefreshRecoveryAcrossMultiplePolls() async throws {
        let store = try makeStore()
        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!

        var phase = 1
        var usageRequestTokens: [String] = []

        MockURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/oauth/token"):
                if phase <= 2 {
                    return try Self.httpResponse(url: tokenURL, statusCode: 500)
                }
                return try Self.httpResponse(
                    url: tokenURL,
                    statusCode: 200,
                    body: """
                    {
                      "access_token": "access-refreshed",
                      "refresh_token": "refresh-2",
                      "expires_in": 3600,
                      "scope": "user:profile user:inference"
                    }
                    """
                )
            case ("GET", "/api/oauth/usage"):
                let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
                usageRequestTokens.append(token)
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 200,
                    body: """
                    {
                      "five_hour": { "utilization": \(phase * 10), "resets_at": "2026-03-08T18:00:00Z" },
                      "seven_day": { "utilization": 20, "resets_at": "2026-03-15T18:00:00Z" }
                    }
                    """
                )
            case ("GET", "/api/oauth/profile"):
                return try Self.httpResponse(
                    url: URL(string: "https://example.com/api/oauth/profile")!,
                    statusCode: 200,
                    body: Self.profileFixtureBody
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        // Save initial credentials BEFORE creating the service so isAuthenticated = true
        try store.save(StoredCredentials(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            expiresAt: Date().addingTimeInterval(200), // within 300s leeway but not expired
            scopes: UsageService.defaultOAuthScopes
        ))

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: tokenURL,
            credentialsStore: store
        )

        // ── Poll 1: token nearing expiry (within 300s leeway), refresh server down ──
        // Token not yet expired → API call still proceeds → usage fetched successfully
        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated, "Poll 1: must stay authenticated")
        XCTAssertNil(service.lastError, "Poll 1: usage succeeded so no error")
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 10, "Poll 1: usage should update")
        XCTAssertEqual(usageRequestTokens.count, 1, "Poll 1: exactly one API call")
        XCTAssertEqual(usageRequestTokens.last, "Bearer access-1")

        // ── Poll 2: token now expired, refresh server still down ──
        // Proactive refresh fails + token is expired → skip API call, but stay signed in
        phase = 2
        try store.save(StoredCredentials(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            expiresAt: Date().addingTimeInterval(-60), // definitively expired
            scopes: UsageService.defaultOAuthScopes
        ))
        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated, "Poll 2: must NOT sign out on transient failure")
        XCTAssertEqual(service.lastError, "Token refresh failed — will retry")
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 10, "Poll 2: usage unchanged")
        XCTAssertEqual(usageRequestTokens.count, 1, "Poll 2: no new API call (token expired)")

        // ── Poll 3: refresh server recovers ──
        // Refresh succeeds → API call with new token → usage updated
        phase = 3
        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated, "Poll 3: authenticated after recovery")
        XCTAssertNil(service.lastError, "Poll 3: error cleared")
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 30, "Poll 3: usage updated")
        XCTAssertEqual(usageRequestTokens.count, 2, "Poll 3: one new API call")
        XCTAssertEqual(usageRequestTokens.last, "Bearer access-refreshed")

        let saved = try XCTUnwrap(store.load(defaultScopes: UsageService.defaultOAuthScopes))
        XCTAssertEqual(saved.accessToken, "access-refreshed")
        XCTAssertEqual(saved.refreshToken, "refresh-2")
    }

    /// Simulates a 401 during normal API usage followed by transient refresh failure,
    /// then recovery on the next poll.
    func testEndToEnd401WithTransientFailureThenRecovery() async throws {
        let store = try makeStore()
        try store.save(StoredCredentials(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            expiresAt: Date().addingTimeInterval(3600), // not nearing expiry
            scopes: UsageService.defaultOAuthScopes
        ))

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let tokenURL = URL(string: "https://example.com/v1/oauth/token")!

        var phase = 1

        MockURLProtocol.handler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""

            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/oauth/token"):
                if phase == 1 {
                    // Phase 1: network blip during refresh
                    throw URLError(.networkConnectionLost)
                }
                // Phase 2: server recovered
                return try Self.httpResponse(
                    url: tokenURL,
                    statusCode: 200,
                    body: """
                    {
                      "access_token": "access-2",
                      "refresh_token": "refresh-2",
                      "expires_in": 3600,
                      "scope": "user:profile user:inference"
                    }
                    """
                )
            case ("GET", "/api/oauth/usage"):
                if auth == "Bearer access-1" {
                    // Old token always gets rejected
                    return try Self.httpResponse(url: usageURL, statusCode: 401)
                }
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 200,
                    body: """
                    {
                      "five_hour": { "utilization": 42, "resets_at": "2026-03-08T18:00:00Z" },
                      "seven_day": { "utilization": 20, "resets_at": "2026-03-15T18:00:00Z" }
                    }
                    """
                )
            case ("GET", "/api/oauth/profile"):
                return try Self.httpResponse(
                    url: URL(string: "https://example.com/api/oauth/profile")!,
                    statusCode: 200,
                    body: Self.profileFixtureBody
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: tokenURL,
            credentialsStore: store
        )

        // ── Poll 1: API returns 401, refresh fails (network) → stays authenticated ──
        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated, "Must not sign out on transient refresh failure")
        XCTAssertEqual(service.lastError, "Token refresh failed — will retry")
        XCTAssertNil(service.usage, "No usage data yet")

        // ── Poll 2: next cycle, server is healthy → everything works ──
        phase = 2
        // API will return 401 for old token, refresh succeeds, retry with new token succeeds
        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated, "Authenticated after recovery")
        XCTAssertNil(service.lastError, "Error cleared")
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 42)

        let saved = try XCTUnwrap(store.load(defaultScopes: UsageService.defaultOAuthScopes))
        XCTAssertEqual(saved.accessToken, "access-2")
        XCTAssertEqual(saved.refreshToken, "refresh-2")
    }

    // MARK: - OAuth code submission

    /// A whitespace-only paste passes the `code.isEmpty` button guard (which checks
    /// the raw, untrimmed field) but trims to "" inside `submitOAuthCode`, so `split`
    /// returns no parts. Indexing `parts[0]` used to crash; it must now surface an error.
    func testSubmitOAuthCodeWithWhitespaceOnlyInputShowsErrorWithoutCrashing() async throws {
        let service = UsageService(
            session: makeSession(),
            usageEndpoint: URL(string: "https://example.com/api/oauth/usage")!,
            profileEndpoint: URL(string: "https://example.com/api/oauth/profile")!,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: URL(string: "https://example.com/v1/oauth/token")!,
            credentialsStore: try makeStore()
        )

        await service.submitOAuthCode("   ")

        XCTAssertEqual(service.lastError, "No OAuth code entered")
        XCTAssertFalse(service.isAuthenticated)
    }

    // MARK: - Claude oauth/profile

    func testFetchUsageFetchesProfileAfterSuccessfulUsage() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "access-1",
                refreshToken: "refresh-1",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let profileURL = URL(string: "https://example.com/api/oauth/profile")!
        var profileRequestCount = 0
        var profileAuthorization: String?
        var profileBeta: String?

        MockURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/oauth/usage"):
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 200,
                    body: """
                    {
                      "five_hour": { "utilization": 15, "resets_at": "2026-03-08T18:00:00Z" },
                      "seven_day": { "utilization": 25, "resets_at": "2026-03-15T18:00:00Z" }
                    }
                    """
                )
            case ("GET", "/api/oauth/profile"):
                profileRequestCount += 1
                profileAuthorization = request.value(forHTTPHeaderField: "Authorization")
                profileBeta = request.value(forHTTPHeaderField: "anthropic-beta")
                return try Self.httpResponse(
                    url: profileURL,
                    statusCode: 200,
                    body: Self.profileFixtureBody
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: profileURL,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: URL(string: "https://example.com/v1/oauth/token")!,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertNil(service.lastError)
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 15)
        XCTAssertEqual(profileRequestCount, 1)
        XCTAssertEqual(profileAuthorization, "Bearer access-1")
        XCTAssertEqual(profileBeta, "oauth-2025-04-20")
        XCTAssertEqual(service.profile?.planLabel, "Max 20x")
        XCTAssertEqual(service.profile?.organization?.subscriptionStatus, "active")
        XCTAssertNotNil(service.profileLastFetched)
    }

    func testFetchUsageDoesNotRefetchProfileWithinSixtyMinutes() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "access-1",
                refreshToken: "refresh-1",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let profileURL = URL(string: "https://example.com/api/oauth/profile")!
        var profileRequestCount = 0

        MockURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/oauth/usage"):
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 200,
                    body: """
                    {
                      "five_hour": { "utilization": 15, "resets_at": "2026-03-08T18:00:00Z" },
                      "seven_day": { "utilization": 25, "resets_at": "2026-03-15T18:00:00Z" }
                    }
                    """
                )
            case ("GET", "/api/oauth/profile"):
                profileRequestCount += 1
                return try Self.httpResponse(
                    url: profileURL,
                    statusCode: 200,
                    body: Self.profileFixtureBody
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: profileURL,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: URL(string: "https://example.com/v1/oauth/token")!,
            credentialsStore: store
        )

        await service.fetchUsage()
        await service.fetchUsage()

        XCTAssertEqual(profileRequestCount, 1)
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 15)
        XCTAssertEqual(service.profile?.planLabel, "Max 20x")
    }

    func testProfileFailureLeavesUsageStateUntouched() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "access-1",
                refreshToken: "refresh-1",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let profileURL = URL(string: "https://example.com/api/oauth/profile")!

        MockURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/oauth/usage"):
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 200,
                    body: """
                    {
                      "five_hour": { "utilization": 33, "resets_at": "2026-03-08T18:00:00Z" },
                      "seven_day": { "utilization": 44, "resets_at": "2026-03-15T18:00:00Z" }
                    }
                    """
                )
            case ("GET", "/api/oauth/profile"):
                return try Self.httpResponse(url: profileURL, statusCode: 500)
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: profileURL,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: URL(string: "https://example.com/v1/oauth/token")!,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertNil(service.lastError)
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 33)
        XCTAssertEqual(service.usage?.sevenDay?.utilization, 44)
        XCTAssertNil(service.profile)
        XCTAssertNil(service.profileLastFetched)
    }

    func testProfileAuthFailureDoesNotSetLastError() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "access-1",
                refreshToken: "refresh-1",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let profileURL = URL(string: "https://example.com/api/oauth/profile")!
        var tokenRefreshCount = 0

        MockURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/oauth/usage"):
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 200,
                    body: """
                    {
                      "five_hour": { "utilization": 11, "resets_at": "2026-03-08T18:00:00Z" },
                      "seven_day": { "utilization": 22, "resets_at": "2026-03-15T18:00:00Z" }
                    }
                    """
                )
            case ("GET", "/api/oauth/profile"):
                return try Self.httpResponse(url: profileURL, statusCode: 401)
            case ("POST", "/v1/oauth/token"):
                tokenRefreshCount += 1
                XCTFail("Profile 401 must not trigger token refresh")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: profileURL,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: URL(string: "https://example.com/v1/oauth/token")!,
            credentialsStore: store
        )

        await service.fetchUsage()

        XCTAssertTrue(service.isAuthenticated)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(service.usage?.fiveHour?.utilization, 11)
        XCTAssertNil(service.profile)
        XCTAssertNil(service.profileLastFetched)
        XCTAssertEqual(tokenRefreshCount, 0)
    }

    func testConcurrentUsageFetchesShareSingleProfileRequest() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "access-1",
                refreshToken: "refresh-1",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let profileURL = URL(string: "https://example.com/api/oauth/profile")!
        let gate = ProfileRequestGate(targetUsageCount: 2)

        MockURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/oauth/usage"):
                gate.noteUsage()
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 200,
                    body: """
                    {
                      "five_hour": { "utilization": 18, "resets_at": "2026-03-08T18:00:00Z" },
                      "seven_day": { "utilization": 28, "resets_at": "2026-03-15T18:00:00Z" }
                    }
                    """
                )
            case ("GET", "/api/oauth/profile"):
                gate.noteProfileStarted()
                gate.waitForRelease()
                return try Self.httpResponse(
                    url: profileURL,
                    statusCode: 200,
                    body: Self.profileFixtureBody
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: profileURL,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: URL(string: "https://example.com/v1/oauth/token")!,
            credentialsStore: store
        )

        async let first: Void = service.fetchUsage()
        async let second: Void = service.fetchUsage()

        await gate.waitUntilProfileStarted()
        await gate.waitUntilUsagesSeen()
        XCTAssertEqual(gate.profileRequestCount, 1, "Only one profile request while both callers await it")

        gate.release()
        _ = await (first, second)

        XCTAssertEqual(gate.profileRequestCount, 1)
        XCTAssertEqual(service.profile?.planLabel, "Max 20x")
        XCTAssertNil(service.lastError)
    }

    func testSignOutDuringProfileFetchDiscardsResponse() async throws {
        let store = try makeStore()
        try store.save(
            StoredCredentials(
                accessToken: "access-1",
                refreshToken: "refresh-1",
                expiresAt: Date().addingTimeInterval(3600),
                scopes: UsageService.defaultOAuthScopes
            )
        )

        let usageURL = URL(string: "https://example.com/api/oauth/usage")!
        let profileURL = URL(string: "https://example.com/api/oauth/profile")!
        let gate = ProfileRequestGate(targetUsageCount: 1)

        MockURLProtocol.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/oauth/usage"):
                gate.noteUsage()
                return try Self.httpResponse(
                    url: usageURL,
                    statusCode: 200,
                    body: """
                    {
                      "five_hour": { "utilization": 7, "resets_at": "2026-03-08T18:00:00Z" },
                      "seven_day": { "utilization": 9, "resets_at": "2026-03-15T18:00:00Z" }
                    }
                    """
                )
            case ("GET", "/api/oauth/profile"):
                gate.noteProfileStarted()
                gate.waitForRelease()
                return try Self.httpResponse(
                    url: profileURL,
                    statusCode: 200,
                    body: Self.profileFixtureBody
                )
            default:
                XCTFail("Unexpected request: \(request)")
                return try Self.httpResponse(url: request.url!, statusCode: 500)
            }
        }

        let service = UsageService(
            session: makeSession(),
            usageEndpoint: usageURL,
            profileEndpoint: profileURL,
            userinfoEndpoint: URL(string: "https://example.com/api/oauth/userinfo")!,
            tokenEndpoint: URL(string: "https://example.com/v1/oauth/token")!,
            credentialsStore: store
        )

        let fetchTask = Task { await service.fetchUsage() }
        await gate.waitUntilProfileStarted()
        XCTAssertEqual(gate.profileRequestCount, 1, "Sign-out must happen while the profile request is in flight")
        service.signOut()
        gate.release()
        await fetchTask.value

        XCTAssertFalse(service.isAuthenticated)
        XCTAssertNil(service.profile)
        XCTAssertNil(service.profileLastFetched)
        XCTAssertNil(service.usage)
        XCTAssertEqual(gate.profileRequestCount, 1)
    }


    private static let profileFixtureBody = """
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

    private func makeStore() throws -> StoredCredentialsStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return StoredCredentialsStore(directoryURL: directory)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonBody(for request: URLRequest) -> [String: String]? {
        guard let body = bodyData(for: request),
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: String] else {
            return nil
        }
        return object
    }

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }

        return data.isEmpty ? nil : data
    }

    private static func httpResponse(
        url: URL,
        statusCode: Int,
        headers: [String: String] = [:],
        body: String = ""
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )
        )
        return (response, Data(body.utf8))
    }
}

/// Synchronizes profile-request tests without sleeping: URLProtocol blocks on a condition,
/// and the test awaits CheckedContinuations that resume when the request has actually started.
/// Every wait has a bounded timeout so a regression fails instead of hanging the suite.
/// `release()` broadcasts so every blocked handler wakes (not a single semaphore permit).
private final class ProfileRequestGate: @unchecked Sendable {
    private static let waitTimeout: TimeInterval = 5

    private let lock = NSLock()
    private let releaseCondition = NSCondition()
    private let targetUsageCount: Int

    private var usageCount = 0
    private var profileCount = 0
    /// Continuation resumes with `true` on timeout, `false` when the event arrived.
    private var profileStartedContinuation: CheckedContinuation<Bool, Never>?
    private var usagesSeenContinuation: CheckedContinuation<Bool, Never>?
    private var profileDidStart = false
    private var usagesDidReachTarget = false
    private var isReleased = false

    init(targetUsageCount: Int) {
        self.targetUsageCount = targetUsageCount
    }

    var profileRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return profileCount
    }

    func noteUsage() {
        lock.lock()
        usageCount += 1
        let reached = usageCount >= targetUsageCount
        let cont = reached && !usagesDidReachTarget ? usagesSeenContinuation : nil
        if reached {
            usagesDidReachTarget = true
            usagesSeenContinuation = nil
        }
        lock.unlock()
        cont?.resume(returning: false)
    }

    func noteProfileStarted() {
        lock.lock()
        profileCount += 1
        profileDidStart = true
        let cont = profileStartedContinuation
        profileStartedContinuation = nil
        lock.unlock()
        cont?.resume(returning: false)
    }

    func waitUntilProfileStarted() async {
        let timedOut = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            lock.lock()
            if profileDidStart {
                lock.unlock()
                continuation.resume(returning: false)
                return
            }
            profileStartedContinuation = continuation
            lock.unlock()

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.waitTimeout) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                guard let cont = self.profileStartedContinuation else {
                    self.lock.unlock()
                    return
                }
                self.profileStartedContinuation = nil
                self.lock.unlock()
                cont.resume(returning: true)
            }
        }
        if timedOut {
            XCTFail("Timed out waiting for profile request to start")
        }
    }

    func waitUntilUsagesSeen() async {
        let timedOut = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            lock.lock()
            if usagesDidReachTarget {
                lock.unlock()
                continuation.resume(returning: false)
                return
            }
            usagesSeenContinuation = continuation
            lock.unlock()

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.waitTimeout) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                guard let cont = self.usagesSeenContinuation else {
                    self.lock.unlock()
                    return
                }
                self.usagesSeenContinuation = nil
                self.lock.unlock()
                cont.resume(returning: true)
            }
        }
        if timedOut {
            XCTFail("Timed out waiting for usage requests to reach target")
        }
    }

    func waitForRelease() {
        releaseCondition.lock()
        defer { releaseCondition.unlock() }
        let deadline = Date().addingTimeInterval(Self.waitTimeout)
        while !isReleased {
            if !releaseCondition.wait(until: deadline) {
                XCTFail("Timed out waiting for profile request release")
                return
            }
        }
    }

    func release() {
        releaseCondition.lock()
        isReleased = true
        releaseCondition.broadcast()
        releaseCondition.unlock()
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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
