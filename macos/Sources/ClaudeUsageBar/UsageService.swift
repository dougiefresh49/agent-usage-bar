import Foundation
import Combine
import CryptoKit
import AppKit
@MainActor
class UsageService: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var isAuthenticated = false
    @Published var isAwaitingCode = false
    @Published private(set) var accountEmail: String?
    @Published private(set) var profile: ClaudeProfileResponse?
    @Published private(set) var profileLastFetched: Date?

    var historyService: UsageHistoryService?
    var notificationService: NotificationService?
    var snapshotStore: UsageSnapshotStore?

    private var timer: Timer?
    private let session: URLSession
    private let usageEndpoint: URL
    private let profileEndpoint: URL
    private let userinfoEndpoint: URL
    private let tokenEndpoint: URL
    private let credentialsStore: StoredCredentialsStore
    private let localProfileLoader: @MainActor () -> String?
    private let lowPowerModeEnabled: () -> Bool
    private var currentInterval: TimeInterval
    private var isPollingPaused = false
    private enum RefreshResult {
        case success
        case permanentFailure
        case transientFailure
    }

    private var refreshTask: Task<RefreshResult, Never>?
    private var usageFetchTask: Task<Void, Never>?
    /// Set when a manual refresh arrives during an in-flight fetch; drained as one trailing run.
    private var pendingManualUsageRefresh = false
    private var profileFetchTask: Task<Bool, Never>?
    private var profileFetchGeneration = 0
    private var lastWakeAt: Date?
    private var isRateLimitedBackoff = false
    private(set) var rateLimitBackoffUntil: Date?

    /// Timer cadence currently in effect (base, low-power, or 429 backoff).
    var effectivePollingInterval: TimeInterval { currentInterval }

    static let defaultPollingMinutes = 30
    static let pollingOptions = [5, 15, 30, 60]
    nonisolated static let maxBackoffInterval: TimeInterval = PollingBackoff.maxInterval
    nonisolated static let profileCacheInterval: TimeInterval = 60 * 60
    nonisolated static let defaultOAuthScopes = ["user:profile", "user:inference"]
    nonisolated private static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    nonisolated private static let defaultUsageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    nonisolated private static let defaultProfileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    nonisolated private static let defaultUserinfoEndpoint = URL(string: "https://api.anthropic.com/api/oauth/userinfo")!
    nonisolated private static let defaultTokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    nonisolated private static let defaultRedirectURI = "https://platform.claude.com/oauth/code/callback"

    @Published private(set) var pollingMinutes: Int

    func updatePollingInterval(_ minutes: Int) {
        pollingMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "pollingMinutes")
        currentInterval = PollingBackoff.pollingInterval(
            minutes: minutes,
            isLowPower: lowPowerModeEnabled()
        )
        if isAuthenticated {
            scheduleTimer()
            Task { await fetchUsage(trigger: .automatic) }
        }
    }

    private var baseInterval: TimeInterval {
        PollingBackoff.pollingInterval(
            minutes: pollingMinutes,
            isLowPower: lowPowerModeEnabled()
        )
    }

    /// Forwards to `PollingBackoff` so call sites and older tests keep compiling.
    nonisolated static func backoffInterval(
        retryAfter: TimeInterval?,
        currentInterval: TimeInterval
    ) -> TimeInterval {
        PollingBackoff.backoffInterval(
            retryAfter: retryAfter,
            currentInterval: currentInterval
        )
    }

    // OAuth constants
    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let redirectUri: String

    // PKCE state (lives only during an auth flow)
    private var codeVerifier: String?
    private var oauthState: String?

    var pct5h: Double { (usage?.fiveHour?.utilization ?? 0) / 100.0 }
    var pct7d: Double { (usage?.sevenDay?.utilization ?? 0) / 100.0 }
    var pctExtra: Double { (usage?.extraUsage?.utilization ?? 0) / 100.0 }
    var reset5h: Date? { usage?.fiveHour?.resetsAtDate }
    var reset7d: Date? { usage?.sevenDay?.resetsAtDate }

    init(
        session: URLSession = .shared,
        usageEndpoint: URL = UsageService.defaultUsageEndpoint,
        profileEndpoint: URL = UsageService.defaultProfileEndpoint,
        userinfoEndpoint: URL = UsageService.defaultUserinfoEndpoint,
        tokenEndpoint: URL = UsageService.defaultTokenEndpoint,
        redirectUri: String = UsageService.defaultRedirectURI,
        credentialsStore: StoredCredentialsStore = StoredCredentialsStore(),
        localProfileLoader: @MainActor @escaping () -> String? = UsageService.loadLocalProfile,
        lowPowerModeEnabled: @escaping () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    ) {
        self.session = session
        self.usageEndpoint = usageEndpoint
        self.profileEndpoint = profileEndpoint
        self.userinfoEndpoint = userinfoEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.redirectUri = redirectUri
        self.credentialsStore = credentialsStore
        self.localProfileLoader = localProfileLoader
        self.lowPowerModeEnabled = lowPowerModeEnabled
        let stored = UserDefaults.standard.integer(forKey: "pollingMinutes")
        let minutes = Self.pollingOptions.contains(stored) ? stored : Self.defaultPollingMinutes
        self.pollingMinutes = minutes
        self.currentInterval = PollingBackoff.pollingInterval(
            minutes: minutes,
            isLowPower: lowPowerModeEnabled()
        )
        isAuthenticated = loadCredentials() != nil
    }

    // MARK: - Polling

    func startPolling() {
        guard isAuthenticated else { return }
        isPollingPaused = false
        Task {
            await fetchUsage(trigger: .automatic)
            if accountEmail == nil { await fetchProfile() }
        }
        scheduleTimer()
    }

    func pausePolling() {
        isPollingPaused = true
        timer?.invalidate()
        timer = nil
    }

    func handleWake() {
        guard isAuthenticated else { return }
        let now = Date()
        if let lastWakeAt, now.timeIntervalSince(lastWakeAt) < 2 { return }
        lastWakeAt = now
        let wasPaused = isPollingPaused
        isPollingPaused = false
        Task {
            await fetchUsage(trigger: .automatic)
            if wasPaused || timer == nil {
                scheduleTimer()
            }
        }
    }

    /// Call when Low Power Mode flips so the timer picks up the doubled (or restored) interval.
    func rescheduleForPowerState() {
        if !isRateLimitedBackoff {
            currentInterval = baseInterval
        }
        scheduleTimer()
    }

    /// Popover-open path: refresh when the last successful fetch is older than `interval`.
    func refreshIfStale(olderThan interval: TimeInterval) async {
        guard isAuthenticated else { return }
        let isStale = lastUpdated.map { Date().timeIntervalSince($0) > interval } ?? true
        guard isStale else { return }
        await fetchUsage(trigger: .automatic)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard isAuthenticated, !isPollingPaused else { return }
        let interval = currentInterval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isAuthenticated, !self.isPollingPaused else { return }
                Task { await self.fetchUsage(trigger: .scheduled) }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - OAuth PKCE Flow

    func startOAuthFlow() {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateCodeVerifier() // random state

        codeVerifier = verifier
        oauthState = state

        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: Self.defaultOAuthScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
            isAwaitingCode = true
        }
    }

    func submitOAuthCode(_ rawCode: String) async {
        // Response format: "code#state" — parse it
        let parts = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", maxSplits: 1)
        // A whitespace-only paste trims to "" and yields no parts, so guard before
        // indexing. Leave isAwaitingCode set so the user can retry without restarting.
        guard let code = parts.first.map(String.init), !code.isEmpty else {
            lastError = "No OAuth code entered"
            return
        }

        if parts.count > 1 {
            let returnedState = String(parts[1])
            guard returnedState == oauthState else {
                lastError = "OAuth state mismatch — try again"
                isAwaitingCode = false
                codeVerifier = nil
                oauthState = nil
                return
            }
        }

        guard let verifier = codeVerifier else {
            lastError = "No pending OAuth flow"
            isAwaitingCode = false
            return
        }

        // Exchange code for token
        var request = URLRequest(
            url: tokenEndpoint,
            timeoutInterval: PollingBackoff.secondaryRequestTimeout
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": oauthState ?? "",
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "code_verifier": verifier,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "Invalid token response"
                return
            }
            guard http.statusCode == 200 else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                lastError = "Token exchange failed: HTTP \(http.statusCode) \(bodyStr)"
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let credentials = credentials(from: json) else {
                lastError = "Could not parse token response"
                return
            }

            do {
                try saveCredentials(credentials)
            } catch {
                lastError = "Failed to save credentials: \(error.localizedDescription)"
                return
            }
            isAuthenticated = true
            isAwaitingCode = false
            lastError = nil
            codeVerifier = nil
            oauthState = nil

            await fetchProfile()
            startPolling()
        } catch {
            lastError = "Token exchange error: \(error.localizedDescription)"
        }
    }

    func signOut() {
        deleteCredentials()
        snapshotStore?.remove(provider: "claude")
        isAuthenticated = false
        usage = nil
        lastUpdated = nil
        accountEmail = nil
        profile = nil
        profileLastFetched = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        usageFetchTask?.cancel()
        usageFetchTask = nil
        profileFetchGeneration &+= 1
        profileFetchTask?.cancel()
        profileFetchTask = nil
        isPollingPaused = false
        clearRateLimitBackoff()
        lastError = nil
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    // MARK: - API Fetch

    /// - Parameter trigger: `.scheduled` debounces; `.automatic` still honours 429
    ///   backoff; `.manual` (Refresh) always runs. A manual that arrives during an
    ///   in-flight fetch sets a pending flag and runs exactly one trailing request.
    func fetchUsage(trigger: PollingBackoff.Trigger = .manual) async {
        if let usageFetchTask {
            if trigger == .manual {
                pendingManualUsageRefresh = true
            }
            await usageFetchTask.value
            // The owner of the task runs the trailing manual fetch if the flag is
            // still set once it clears the slot; recursing here can loop without a
            // suspension point while the slot still holds the finished task.
            return
        }

        if !trigger.skipsBackoff,
           PollingBackoff.shouldSkipForBackoff(until: rateLimitBackoffUntil) {
            return
        }
        if !trigger.skipsDebounce,
           PollingBackoff.shouldSkipScheduledPoll(lastSuccessfulFetch: lastUpdated) {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.pendingManualUsageRefresh = false
                await self.performFetchUsage()
            } while self.pendingManualUsageRefresh
        }
        usageFetchTask = task
        await task.value
        usageFetchTask = nil
        if pendingManualUsageRefresh {
            await fetchUsage(trigger: .manual)
        }
    }

    /// Backward-compatible wrapper used by older call sites and tests.
    func fetchUsage(force: Bool) async {
        await fetchUsage(trigger: force ? .manual : .scheduled)
    }

    private func performFetchUsage() async {
        guard loadCredentials() != nil else {
            lastError = "Not signed in"
            isAuthenticated = false
            return
        }

        do {
            guard let result = try await sendAuthorizedRequest(to: usageEndpoint) else {
                return
            }
            let (data, http) = result
            if http.statusCode == 429 {
                applyRateLimitBackoff(retryAfter: PollingBackoff.retryAfterSeconds(from: http))
                lastError = "Rate limited — backing off to \(Int(currentInterval))s"
                scheduleTimer()
                return
            }
            guard http.statusCode == 200 else {
                lastError = "HTTP \(http.statusCode)"
                return
            }
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            let reconciled = decoded.reconciled(with: usage)
            usage = reconciled
            lastError = nil
            lastUpdated = Date()
            historyService?.recordDataPoint(pct5h: pct5h, pct7d: pct7d)
            notificationService?.checkClaude(
                sessionPercent: (usage?.fiveHour?.utilization ?? 0),
                sevenDayPercent: (usage?.sevenDay?.utilization ?? 0),
                fablePercent: usage?.fableUtilization
            )
            snapshotStore?.update(
                provider: "claude",
                metrics: UsageSnapshotStore.claudeMetrics(for: reconciled)
            )
            // Reuse the bearer token that just succeeded for usage. No separate refresh.
            guard let accessToken = loadCredentials()?.accessToken else {
                if isRateLimitedBackoff || currentInterval != baseInterval {
                    clearRateLimitBackoff()
                    scheduleTimer()
                }
                return
            }
            let profileRateLimited = await fetchOAuthProfileIfNeeded(accessToken: accessToken)
            // Keep secondary (profile) 429 backoff; only clear after a clean full poll.
            if !profileRateLimited, isRateLimitedBackoff || currentInterval != baseInterval {
                clearRateLimitBackoff()
                scheduleTimer()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func applyRateLimitBackoff(retryAfter: TimeInterval?) {
        isRateLimitedBackoff = true
        currentInterval = PollingBackoff.backoffInterval(
            retryAfter: retryAfter,
            currentInterval: currentInterval
        )
        rateLimitBackoffUntil = Date().addingTimeInterval(currentInterval)
    }

    private func clearRateLimitBackoff() {
        isRateLimitedBackoff = false
        rateLimitBackoffUntil = nil
        currentInterval = baseInterval
    }

    @discardableResult
    private func fetchOAuthProfileIfNeeded(accessToken: String) async -> Bool {
        if let profileLastFetched,
           Date().timeIntervalSince(profileLastFetched) < Self.profileCacheInterval {
            return false
        }

        if let profileFetchTask {
            return await profileFetchTask.value
        }

        let generation = profileFetchGeneration &+ 1
        profileFetchGeneration = generation
        let task = Task { [weak self] in
            guard let self else { return false }
            return await self.performOAuthProfileFetch(accessToken: accessToken)
        }
        profileFetchTask = task
        let rateLimited = await task.value
        // Only clear if we still own the slot. A newer fetch or sign-out may have replaced it.
        if profileFetchGeneration == generation {
            profileFetchTask = nil
        }
        return rateLimited
    }

    /// Soft profile fetch: one-shot with the usage bearer token. Never refreshes, never mutates `lastError`, never expires the session.
    /// Returns `true` when the profile endpoint returned 429 and applied backoff.
    private func performOAuthProfileFetch(accessToken: String) async -> Bool {
        if let profileLastFetched,
           Date().timeIntervalSince(profileLastFetched) < Self.profileCacheInterval {
            return false
        }

        let wasAuthenticated = isAuthenticated

        do {
            let (data, http) = try await performAuthorizedRequest(
                token: accessToken,
                url: profileEndpoint
            )
            guard http.statusCode == 200 else {
                // Soft failure, including 401: leave profile nil and do not refresh.
                // A 429 still backs off the provider polls.
                if http.statusCode == 429 {
                    applyRateLimitBackoff(retryAfter: PollingBackoff.retryAfterSeconds(from: http))
                    scheduleTimer()
                    print("[ClaudeProfile] HTTP \(http.statusCode)")
                    return true
                }
                print("[ClaudeProfile] HTTP \(http.statusCode)")
                return false
            }
            // Drop the response if the user signed out while the request was in flight.
            guard wasAuthenticated, isAuthenticated, loadCredentials() != nil else {
                print("[ClaudeProfile] discarding response after sign-out")
                return false
            }
            let decoded = try JSONDecoder().decode(ClaudeProfileResponse.self, from: data)
            profile = decoded
            profileLastFetched = Date()
            return false
        } catch {
            print("[ClaudeProfile] \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Profile

    func fetchProfile() async {
        if let local = localProfileLoader() {
            accountEmail = local
            return
        }

        guard let result = try? await sendAuthorizedRequest(
            to: userinfoEndpoint,
            expireSessionOnAuthFailure: false
        ) else {
            return
        }
        let (data, http) = result
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let email = json["email"] as? String, !email.isEmpty {
            accountEmail = email
        } else if let name = json["name"] as? String, !name.isEmpty {
            accountEmail = name
        }
    }

    /// Try reading the email from Claude Code's local config as a fallback.
    nonisolated private static func loadLocalProfile() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any] else {
            return nil
        }
        if let email = account["emailAddress"] as? String, !email.isEmpty {
            return email
        }
        if let name = account["displayName"] as? String, !name.isEmpty {
            return name
        }
        return nil
    }

    // MARK: - Credential storage

    private func saveCredentials(_ credentials: StoredCredentials) throws {
        try credentialsStore.save(credentials)
    }

    private func loadCredentials() -> StoredCredentials? {
        credentialsStore.load(defaultScopes: Self.defaultOAuthScopes)
    }

    private func deleteCredentials() {
        credentialsStore.delete()
    }

    // MARK: - Authorized requests

    private func sendAuthorizedRequest(
        to url: URL,
        expireSessionOnAuthFailure: Bool = true
    ) async throws -> (Data, HTTPURLResponse)? {
        guard let initialCredentials = loadCredentials() else {
            lastError = "Not signed in"
            isAuthenticated = false
            return nil
        }

        if initialCredentials.needsRefresh() {
            let refreshResult = await refreshCredentials(force: true)
            if refreshResult != .success, initialCredentials.isExpired() {
                switch refreshResult {
                case .permanentFailure:
                    if expireSessionOnAuthFailure {
                        expireSession()
                    }
                case .transientFailure:
                    lastError = "Token refresh failed — will retry"
                case .success:
                    break
                }
                return nil
            }
        }

        let activeCredentials = loadCredentials() ?? initialCredentials

        var result = try await performAuthorizedRequest(
            token: activeCredentials.accessToken,
            url: url
        )

        if result.1.statusCode != 401 {
            return result
        }

        let refreshResult = await refreshCredentials(force: true)
        switch refreshResult {
        case .success:
            guard let refreshedCredentials = loadCredentials() else {
                if expireSessionOnAuthFailure {
                    expireSession()
                }
                return nil
            }

            result = try await performAuthorizedRequest(
                token: refreshedCredentials.accessToken,
                url: url
            )

            if result.1.statusCode == 401 {
                if expireSessionOnAuthFailure {
                    expireSession()
                }
                return nil
            }

            return result

        case .permanentFailure:
            if expireSessionOnAuthFailure {
                expireSession()
            }
            return nil

        case .transientFailure:
            lastError = "Token refresh failed — will retry"
            return nil
        }
    }

    private func performAuthorizedRequest(
        token: String,
        url: URL
    ) async throws -> (Data, HTTPURLResponse) {
        let timeout = url == usageEndpoint
            ? PollingBackoff.usageRequestTimeout
            : PollingBackoff.secondaryRequestTimeout
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func refreshCredentials(force: Bool) async -> RefreshResult {
        if let refreshTask {
            return await refreshTask.value
        }

        let task = Task { [weak self] in
            guard let self else { return RefreshResult.permanentFailure }
            return await self.performRefresh(force: force)
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh(force: Bool) async -> RefreshResult {
        guard let currentCredentials = loadCredentials(),
              let refreshToken = currentCredentials.refreshToken,
              refreshToken.isEmpty == false else {
            return .permanentFailure
        }

        if force == false, currentCredentials.needsRefresh() == false {
            return .success
        }

        var request = URLRequest(
            url: tokenEndpoint,
            timeoutInterval: PollingBackoff.secondaryRequestTimeout
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
        ]
        if currentCredentials.scopes.isEmpty == false {
            body["scope"] = currentCredentials.scopes.joined(separator: " ")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let http: HTTPURLResponse
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .transientFailure
            }
            data = responseData
            http = httpResponse
        } catch {
            return .transientFailure
        }

        guard http.statusCode == 200 else {
            if http.statusCode >= 400, http.statusCode < 500 {
                return .permanentFailure
            }
            return .transientFailure
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updatedCredentials = credentials(
                from: json,
                fallback: currentCredentials
              ) else {
            return .transientFailure
        }

        do {
            try saveCredentials(updatedCredentials)
        } catch {
            try? await Task.sleep(nanoseconds: 100_000_000)
            do {
                try saveCredentials(updatedCredentials)
            } catch {
                return .transientFailure
            }
        }

        isAuthenticated = true
        return .success
    }

    private func credentials(
        from json: [String: Any],
        fallback: StoredCredentials? = nil
    ) -> StoredCredentials? {
        guard let accessToken = json["access_token"] as? String, accessToken.isEmpty == false else {
            return nil
        }

        let scopeString = json["scope"] as? String
        let scopes = scopeString?
            .split(whereSeparator: \.isWhitespace)
            .map(String.init) ?? fallback?.scopes ?? Self.defaultOAuthScopes

        return StoredCredentials(
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? fallback?.refreshToken,
            expiresAt: Self.expirationDate(from: json["expires_in"]) ?? fallback?.expiresAt,
            scopes: scopes
        )
    }

    private static func expirationDate(from value: Any?) -> Date? {
        let seconds: TimeInterval?
        switch value {
        case let number as NSNumber:
            seconds = number.doubleValue
        case let number as Double:
            seconds = number
        case let number as Int:
            seconds = TimeInterval(number)
        case let string as String:
            seconds = TimeInterval(string)
        default:
            seconds = nil
        }

        guard let seconds else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    private func expireSession() {
        deleteCredentials()
        snapshotStore?.remove(provider: "claude")
        isAuthenticated = false
        usage = nil
        lastUpdated = nil
        accountEmail = nil
        profile = nil
        profileLastFetched = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        usageFetchTask?.cancel()
        usageFetchTask = nil
        profileFetchGeneration &+= 1
        profileFetchTask?.cancel()
        profileFetchTask = nil
        isPollingPaused = false
        clearRateLimitBackoff()
        lastError = "Session expired — please sign in again"
    }
}

// MARK: - Base64URL

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
