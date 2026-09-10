import Combine
import Foundation

enum OpenAICredentialSource: Equatable {
    case pasted
    case codexCLI
    case environment
    case none
}

enum CursorCredentialSource: Equatable {
    case pasted
    case cursorCLI
    case environment
    case none
}

@MainActor
final class ConnectedUsageService: ObservableObject {
    @Published private(set) var cursorUsage: CursorUsageResponse?
    @Published private(set) var openAIUsage: OpenAIUsageResponse?
    @Published private(set) var openAIResetCredits: OpenAIResetCreditsResponse?
    @Published private(set) var elevenLabsUsage: ElevenLabsSubscriptionResponse?
    @Published private(set) var cursorError: String?
    @Published private(set) var openAIError: String?
    @Published private(set) var elevenLabsError: String?
    @Published private(set) var cursorLastUpdated: Date?
    @Published private(set) var openAILastUpdated: Date?
    @Published private(set) var elevenLabsLastUpdated: Date?
    @Published private(set) var isCursorConfigured = false
    @Published private(set) var isOpenAIConfigured = false
    @Published private(set) var isElevenLabsConfigured = false
    @Published private(set) var openAICredentialSource: OpenAICredentialSource = .none
    @Published private(set) var cursorCredentialSource: CursorCredentialSource = .none
    @Published private(set) var openAIAccountID: String?
    @Published private(set) var openAITokenExpiry: Date?
    @Published private(set) var cursorTokenExpiry: Date?
    @Published private(set) var cursorPlanInfo: CursorPlanInfoResponse?

    private let session: URLSession
    private let cursorEndpoint: URL
    private let openAIUsageEndpoint: URL
    private let openAIResetCreditsEndpoint: URL
    private let elevenLabsSubscriptionEndpoint: URL
    private let credentialsStore: ConnectedServiceCredentialsStore
    private let environment: [String: String]
    private let codexAuthLoader: () -> CodexCLICredentials?
    private let cursorKeychainRunner: CursorCLIKeychain.Runner
    private let planInfoInterval: TimeInterval
    private var lastCursorPlanInfoFetch: Date?
    private var isFetchingCursorPlanInfo = false
    private var openAIAccountIDCredentialIdentity: String?
    var snapshotStore: UsageSnapshotStore?
    var notificationService: NotificationService?
    private var timer: Timer?
    private var pollingMinutes: Int

    var hasAnyConfiguredService: Bool {
        isCursorConfigured || isOpenAIConfigured || isElevenLabsConfigured
    }

    init(
        session: URLSession = .shared,
        cursorEndpoint: URL = URL(string: "https://cursor.com/api/dashboard/get-current-period-usage")!,
        openAIUsageEndpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        openAIResetCreditsEndpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
        elevenLabsSubscriptionEndpoint: URL = URL(string: "https://api.elevenlabs.io/v1/user/subscription")!,
        credentialsStore: ConnectedServiceCredentialsStore = ConnectedServiceCredentialsStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        codexAuthLoader: (() -> CodexCLICredentials?)? = nil,
        cursorKeychainRunner: CursorCLIKeychain.Runner? = nil,
        planInfoInterval: TimeInterval = 3600
    ) {
        self.session = session
        self.cursorEndpoint = cursorEndpoint
        self.openAIUsageEndpoint = openAIUsageEndpoint
        self.openAIResetCreditsEndpoint = openAIResetCreditsEndpoint
        self.elevenLabsSubscriptionEndpoint = elevenLabsSubscriptionEndpoint
        self.credentialsStore = credentialsStore
        self.environment = environment
        self.codexAuthLoader = codexAuthLoader ?? {
            CodexAuthFile.load(environment: environment)
        }
        self.cursorKeychainRunner = cursorKeychainRunner ?? CursorCLIKeychain.defaultRunner
        self.planInfoInterval = planInfoInterval

        let storedMinutes = UserDefaults.standard.integer(forKey: "pollingMinutes")
        pollingMinutes = UsageService.pollingOptions.contains(storedMinutes)
            ? storedMinutes
            : UsageService.defaultPollingMinutes
        updateConfiguredState()
    }

    func startPolling() {
        updateConfiguredState()
        Task { await fetchAll() }
        scheduleTimer()
    }

    func updatePollingInterval(_ minutes: Int) {
        pollingMinutes = minutes
        scheduleTimer()
    }

    func fetchAll() async {
        updateConfiguredState()
        async let cursor: Void = fetchCursorUsage()
        async let openAI: Void = fetchOpenAIUsage()
        async let elevenLabs: Void = fetchElevenLabsUsage()
        _ = await (cursor, openAI, elevenLabs)
    }

    func saveCursorToken(_ rawToken: String) throws {
        guard let token = ConnectedTokenNormalizer.cursor(rawToken) else { return }
        var credentials = credentialsStore.load()
        credentials.cursorSessionToken = token
        try credentialsStore.save(credentials)
        updateConfiguredState()
        cursorError = nil
    }

    func saveOpenAIToken(_ rawToken: String) throws {
        guard let token = ConnectedTokenNormalizer.openAI(rawToken) else { return }
        var credentials = credentialsStore.load()
        credentials.openAISessionToken = token
        try credentialsStore.save(credentials)
        updateConfiguredState()
        openAIError = nil
    }

    func saveElevenLabsAPIKey(_ rawKey: String) throws {
        guard let key = ConnectedTokenNormalizer.elevenLabs(rawKey) else { return }
        var credentials = credentialsStore.load()
        credentials.elevenLabsAPIKey = key
        try credentialsStore.save(credentials)
        updateConfiguredState()
        elevenLabsError = nil
    }

    func clearCursorToken() {
        var credentials = credentialsStore.load()
        credentials.cursorSessionToken = nil
        try? credentialsStore.save(credentials)
        cursorError = nil
        updateConfiguredState()
        if isCursorConfigured {
            Task { await fetchCursorUsage() }
        } else {
            snapshotStore?.remove(provider: "cursor")
            cursorUsage = nil
            cursorLastUpdated = nil
            cursorPlanInfo = nil
            lastCursorPlanInfoFetch = nil
            cursorTokenExpiry = nil
        }
    }

    func clearOpenAIToken() {
        var credentials = credentialsStore.load()
        credentials.openAISessionToken = nil
        try? credentialsStore.save(credentials)
        openAIError = nil
        updateConfiguredState()
        if isOpenAIConfigured {
            Task { await fetchOpenAIUsage() }
        } else {
            snapshotStore?.remove(provider: "openai")
            openAIUsage = nil
            openAIResetCredits = nil
            openAILastUpdated = nil
            openAIAccountID = nil
            openAITokenExpiry = nil
        }
    }

    func clearElevenLabsAPIKey() {
        var credentials = credentialsStore.load()
        credentials.elevenLabsAPIKey = nil
        try? credentialsStore.save(credentials)
        snapshotStore?.remove(provider: "elevenlabs")
        elevenLabsUsage = nil
        elevenLabsError = nil
        elevenLabsLastUpdated = nil
        updateConfiguredState()
    }

    func deviceSyncCredentials() -> ConnectedServiceCredentials {
        ConnectedServiceCredentials(
            openAISessionToken: openAIToken,
            cursorSessionToken: cursorToken,
            elevenLabsAPIKey: elevenLabsAPIKey
        )
    }

    func fetchCursorUsage() async {
        updateConfiguredState()
        guard let resolved = resolveCursorCredential() else { return }

        do {
            let decoded: CursorUsageResponse
            if resolved.source == .cursorCLI {
                let request = CursorConnectAPI.request(
                    method: CursorConnectAPI.getCurrentPeriodUsage,
                    token: resolved.token
                )
                let data = try await responseData(
                    for: request,
                    serviceName: "Cursor",
                    unauthorizedMessage: Self.cursorCLIUnauthorizedMessage
                )
                decoded = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
                await fetchCursorPlanInfoIfNeeded(token: resolved.token)
            } else {
                cursorPlanInfo = nil
                lastCursorPlanInfoFetch = nil
                var request = URLRequest(url: cursorEndpoint)
                request.httpMethod = "POST"
                request.httpBody = Data("{}".utf8)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
                request.setValue("https://cursor.com/dashboard?tab=spending", forHTTPHeaderField: "Referer")
                request.setValue("WorkosCursorSessionToken=\(resolved.token)", forHTTPHeaderField: "Cookie")
                let data = try await responseData(for: request, serviceName: "Cursor")
                decoded = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
            }

            cursorUsage = decoded
            cursorError = nil
            cursorLastUpdated = Date()
            snapshotStore?.update(
                provider: "cursor",
                metrics: UsageSnapshotStore.cursorMetrics(for: decoded)
            )
            notificationService?.checkCursor(
                apiPercent: decoded.planUsage?.apiPercentUsed,
                autoPercent: decoded.planUsage?.autoPercentUsed,
                creditPercent: decoded.spendLimitUsage?.utilization
            )
        } catch {
            cursorError = error.localizedDescription
        }
    }

    func fetchOpenAIUsage() async {
        updateConfiguredState()
        guard let resolved = resolveOpenAICredential() else { return }

        let unauthorizedMessage = resolved.source == .codexCLI
            ? Self.openAICLIUnauthorizedMessage
            : nil
        let accountId = resolved.accountId ?? openAIAccountID

        do {
            let usageData = try await openAIResponseData(
                endpoint: openAIUsageEndpoint,
                token: resolved.token,
                accountId: accountId,
                unauthorizedMessage: unauthorizedMessage
            )
            let decoded = try JSONDecoder().decode(OpenAIUsageResponse.self, from: usageData)
            openAIUsage = decoded
            if let discovered = resolved.accountId ?? decoded.accountId {
                openAIAccountID = discovered
            }
            openAIError = nil
            openAILastUpdated = Date()
            snapshotStore?.update(
                provider: "openai",
                metrics: UsageSnapshotStore.openAIMetrics(for: decoded)
            )
        } catch {
            openAIError = error.localizedDescription
        }

        do {
            let creditData = try await openAIResponseData(
                endpoint: openAIResetCreditsEndpoint,
                token: resolved.token,
                accountId: resolved.accountId ?? openAIAccountID,
                unauthorizedMessage: unauthorizedMessage
            )
            openAIResetCredits = try JSONDecoder().decode(
                OpenAIResetCreditsResponse.self,
                from: creditData
            )
            if let openAIUsage {
                snapshotStore?.update(
                    provider: "openai",
                    metrics: UsageSnapshotStore.openAIMetrics(
                        for: openAIUsage,
                        resetCredits: openAIResetCredits
                    )
                )
            }
        } catch {
            if openAIUsage == nil {
                openAIError = error.localizedDescription
            }
        }

        if openAIUsage != nil || openAIResetCredits != nil {
            notifyOpenAIUsage()
        }
    }

    private func notifyOpenAIUsage() {
        let resetCreditsRemaining = openAIResetCredits?.availableCount
            ?? openAIResetCredits.map { $0.credits.filter(\.isAvailable).count }
            ?? openAIUsage?.rateLimitResetCredits?.applicableAvailableCount
            ?? openAIUsage?.rateLimitResetCredits?.availableCount
        notificationService?.checkOpenAI(
            weeklyPercent: openAIUsage?.rateLimit?.weeklyWindow?.usedPercent,
            resetCreditsRemaining: resetCreditsRemaining
        )
    }

    func fetchElevenLabsUsage() async {
        guard let apiKey = elevenLabsAPIKey else { return }

        var request = URLRequest(url: elevenLabsSubscriptionEndpoint)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let data = try await responseData(for: request, serviceName: "ElevenLabs")
            let decoded = try JSONDecoder().decode(
                ElevenLabsSubscriptionResponse.self,
                from: data
            )
            elevenLabsUsage = decoded
            elevenLabsError = nil
            elevenLabsLastUpdated = Date()
            snapshotStore?.update(
                provider: "elevenlabs",
                metrics: UsageSnapshotStore.elevenLabsMetrics(for: decoded)
            )
        } catch {
            elevenLabsError = error.localizedDescription
        }
    }

    private func fetchCursorPlanInfoIfNeeded(token: String) async {
        let now = Date()
        if isFetchingCursorPlanInfo {
            return
        }
        if let lastCursorPlanInfoFetch,
           now.timeIntervalSince(lastCursorPlanInfoFetch) < planInfoInterval {
            return
        }

        isFetchingCursorPlanInfo = true
        lastCursorPlanInfoFetch = now
        defer { isFetchingCursorPlanInfo = false }

        do {
            let request = CursorConnectAPI.request(
                method: CursorConnectAPI.getPlanInfo,
                token: token
            )
            let data = try await responseData(
                for: request,
                serviceName: "Cursor",
                unauthorizedMessage: Self.cursorCLIUnauthorizedMessage
            )
            cursorPlanInfo = try JSONDecoder().decode(CursorPlanInfoResponse.self, from: data)
        } catch {
            // Soft failure: usage still stands without plan info.
        }
    }

    private func openAIResponseData(
        endpoint: URL,
        token: String,
        accountId: String?,
        unauthorizedMessage: String?
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "Originator")
        if let accountId, accountId.isEmpty == false {
            request.setValue(accountId, forHTTPHeaderField: "Chatgpt-Account-Id")
        }
        return try await responseData(
            for: request,
            serviceName: "OpenAI",
            unauthorizedMessage: unauthorizedMessage
        )
    }

    private func responseData(
        for request: URLRequest,
        serviceName: String,
        unauthorizedMessage: String? = nil
    ) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectedUsageError.invalidResponse(serviceName)
        }
        guard http.statusCode == 200 else {
            if (http.statusCode == 401 || http.statusCode == 403),
               let unauthorizedMessage {
                throw ConnectedUsageError.unauthorized(unauthorizedMessage)
            }
            throw ConnectedUsageError.http(serviceName, http.statusCode)
        }
        return data
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(pollingMinutes * 60)
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.fetchAll() }
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// Pasted or environment tokens only. Device sync stays on the v1 fields until #53.
    private var cursorToken: String? {
        credentialsStore.load().cursorSessionToken
            ?? environment["CURSOR_SESSION_TOKEN"].flatMap(ConnectedTokenNormalizer.cursor)
    }

    /// Pasted or environment tokens only. Device sync stays on the v1 fields until #53.
    private var openAIToken: String? {
        credentialsStore.load().openAISessionToken
            ?? environment["OPENAI_SESSION_TOKEN"].flatMap(ConnectedTokenNormalizer.openAI)
    }

    private var elevenLabsAPIKey: String? {
        credentialsStore.load().elevenLabsAPIKey
            ?? environment["ELEVENLABS_API_KEY"].flatMap(ConnectedTokenNormalizer.elevenLabs)
    }

    private func resolveOpenAICredential() -> ResolvedOpenAICredential? {
        if let pasted = credentialsStore.load().openAISessionToken {
            return ResolvedOpenAICredential(
                token: pasted,
                source: .pasted,
                accountId: nil,
                expiry: nil
            )
        }
        if let cli = codexAuthLoader() {
            return ResolvedOpenAICredential(
                token: cli.accessToken,
                source: .codexCLI,
                accountId: cli.accountId,
                expiry: JWTClaims.expiry(of: cli.accessToken)
            )
        }
        if let env = environment["OPENAI_SESSION_TOKEN"].flatMap(ConnectedTokenNormalizer.openAI) {
            return ResolvedOpenAICredential(
                token: env,
                source: .environment,
                accountId: nil,
                expiry: nil
            )
        }
        return nil
    }

    private func resolveCursorCredential() -> ResolvedCursorCredential? {
        if let pasted = credentialsStore.load().cursorSessionToken {
            return ResolvedCursorCredential(token: pasted, source: .pasted, expiry: nil)
        }
        if let cli = CursorCLIKeychain.load(runner: cursorKeychainRunner) {
            return ResolvedCursorCredential(
                token: cli.accessToken,
                source: .cursorCLI,
                expiry: JWTClaims.expiry(of: cli.accessToken)
            )
        }
        if let env = environment["CURSOR_SESSION_TOKEN"].flatMap(ConnectedTokenNormalizer.cursor) {
            return ResolvedCursorCredential(token: env, source: .environment, expiry: nil)
        }
        return nil
    }

    private func updateConfiguredState() {
        if let openAI = resolveOpenAICredential() {
            isOpenAIConfigured = true
            openAICredentialSource = openAI.source
            openAITokenExpiry = openAI.source == .codexCLI ? openAI.expiry : nil
            let identity = "\(openAI.source)|\(openAI.token)"
            if identity != openAIAccountIDCredentialIdentity {
                openAIAccountIDCredentialIdentity = identity
                openAIAccountID = openAI.accountId
            } else if let accountId = openAI.accountId {
                openAIAccountID = accountId
            }
        } else {
            isOpenAIConfigured = false
            openAICredentialSource = .none
            openAITokenExpiry = nil
            openAIAccountID = nil
            openAIAccountIDCredentialIdentity = nil
        }

        if let cursor = resolveCursorCredential() {
            isCursorConfigured = true
            cursorCredentialSource = cursor.source
            cursorTokenExpiry = cursor.source == .cursorCLI ? cursor.expiry : nil
        } else {
            isCursorConfigured = false
            cursorCredentialSource = .none
            cursorTokenExpiry = nil
            cursorPlanInfo = nil
            lastCursorPlanInfoFetch = nil
        }

        isElevenLabsConfigured = elevenLabsAPIKey != nil
    }

    private static let openAICLIUnauthorizedMessage =
        "Codex login expired. Run any codex command or `codex login` to refresh."
    private static let cursorCLIUnauthorizedMessage =
        "Cursor CLI login expired. Run `cursor-agent login`."
}

private struct ResolvedOpenAICredential {
    let token: String
    let source: OpenAICredentialSource
    let accountId: String?
    let expiry: Date?
}

private struct ResolvedCursorCredential {
    let token: String
    let source: CursorCredentialSource
    let expiry: Date?
}

enum ConnectedUsageError: LocalizedError {
    case invalidResponse(String)
    case http(String, Int)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let service):
            return "\(service) returned an invalid response"
        case .unauthorized(let message):
            return message
        case .http(let service, let status):
            if status == 401 || status == 403 {
                if service == "ElevenLabs" {
                    return "ElevenLabs API key was rejected — update it in Settings"
                }
                return "\(service) session expired — update it in Settings"
            }
            return "\(service) HTTP \(status)"
        }
    }
}
