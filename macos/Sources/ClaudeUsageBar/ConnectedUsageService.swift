import Combine
import Foundation

@MainActor
final class ConnectedUsageService: ObservableObject {
    @Published private(set) var cursorUsage: CursorUsageResponse?
    @Published private(set) var openAIUsage: OpenAIUsageResponse?
    @Published private(set) var openAIResetCredits: OpenAIResetCreditsResponse?
    @Published private(set) var cursorError: String?
    @Published private(set) var openAIError: String?
    @Published private(set) var cursorLastUpdated: Date?
    @Published private(set) var openAILastUpdated: Date?
    @Published private(set) var isCursorConfigured = false
    @Published private(set) var isOpenAIConfigured = false

    private let session: URLSession
    private let cursorEndpoint: URL
    private let openAIUsageEndpoint: URL
    private let openAIResetCreditsEndpoint: URL
    private let credentialsStore: ConnectedServiceCredentialsStore
    private let environment: [String: String]
    private var timer: Timer?
    private var pollingMinutes: Int

    var hasAnyConfiguredService: Bool {
        isCursorConfigured || isOpenAIConfigured
    }

    var iconPrimaryUtilization: Double {
        (openAIUsage?.rateLimit?.primaryWindow?.usedPercent ?? 0) / 100
    }

    var iconSecondaryUtilization: Double {
        (cursorUsage?.planUsage?.totalPercentUsed ?? 0) / 100
    }

    init(
        session: URLSession = .shared,
        cursorEndpoint: URL = URL(string: "https://cursor.com/api/dashboard/get-current-period-usage")!,
        openAIUsageEndpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        openAIResetCreditsEndpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!,
        credentialsStore: ConnectedServiceCredentialsStore = ConnectedServiceCredentialsStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.session = session
        self.cursorEndpoint = cursorEndpoint
        self.openAIUsageEndpoint = openAIUsageEndpoint
        self.openAIResetCreditsEndpoint = openAIResetCreditsEndpoint
        self.credentialsStore = credentialsStore
        self.environment = environment

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
        _ = await (cursor, openAI)
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

    func clearCursorToken() {
        var credentials = credentialsStore.load()
        credentials.cursorSessionToken = nil
        try? credentialsStore.save(credentials)
        cursorUsage = nil
        cursorError = nil
        cursorLastUpdated = nil
        updateConfiguredState()
    }

    func clearOpenAIToken() {
        var credentials = credentialsStore.load()
        credentials.openAISessionToken = nil
        try? credentialsStore.save(credentials)
        openAIUsage = nil
        openAIResetCredits = nil
        openAIError = nil
        openAILastUpdated = nil
        updateConfiguredState()
    }

    func fetchCursorUsage() async {
        guard let token = cursorToken else { return }

        var request = URLRequest(url: cursorEndpoint)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/dashboard?tab=spending", forHTTPHeaderField: "Referer")
        request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")

        do {
            let data = try await responseData(for: request, serviceName: "Cursor")
            cursorUsage = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
            cursorError = nil
            cursorLastUpdated = Date()
        } catch {
            cursorError = error.localizedDescription
        }
    }

    func fetchOpenAIUsage() async {
        guard let token = openAIToken else { return }

        do {
            let usageData = try await openAIResponseData(
                endpoint: openAIUsageEndpoint,
                token: token
            )
            openAIUsage = try JSONDecoder().decode(OpenAIUsageResponse.self, from: usageData)
            openAIError = nil
            openAILastUpdated = Date()
        } catch {
            openAIError = error.localizedDescription
        }

        do {
            let creditData = try await openAIResponseData(
                endpoint: openAIResetCreditsEndpoint,
                token: token
            )
            openAIResetCredits = try JSONDecoder().decode(
                OpenAIResetCreditsResponse.self,
                from: creditData
            )
        } catch {
            if openAIUsage == nil {
                openAIError = error.localizedDescription
            }
        }
    }

    private func openAIResponseData(endpoint: URL, token: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await responseData(for: request, serviceName: "OpenAI")
    }

    private func responseData(for request: URLRequest, serviceName: String) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectedUsageError.invalidResponse(serviceName)
        }
        guard http.statusCode == 200 else {
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

    private var cursorToken: String? {
        credentialsStore.load().cursorSessionToken
            ?? environment["CURSOR_SESSION_TOKEN"].flatMap(ConnectedTokenNormalizer.cursor)
    }

    private var openAIToken: String? {
        credentialsStore.load().openAISessionToken
            ?? environment["OPENAI_SESSION_TOKEN"].flatMap(ConnectedTokenNormalizer.openAI)
    }

    private func updateConfiguredState() {
        isCursorConfigured = cursorToken != nil
        isOpenAIConfigured = openAIToken != nil
    }
}

enum ConnectedUsageError: LocalizedError {
    case invalidResponse(String)
    case http(String, Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let service):
            return "\(service) returned an invalid response"
        case .http(let service, let status):
            if status == 401 || status == 403 {
                return "\(service) session expired — update it in Settings"
            }
            return "\(service) HTTP \(status)"
        }
    }
}
