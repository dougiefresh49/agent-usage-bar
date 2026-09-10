import Combine
import CryptoKit
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
    /// True when a pasted OpenAI token is in the store, even if CLI login is the active source.
    @Published private(set) var hasStoredOpenAIToken = false
    /// True when a pasted Cursor token is in the store, even if CLI login is the active source.
    @Published private(set) var hasStoredCursorToken = false
    @Published private(set) var cursorPlanInfo: CursorPlanInfoResponse?
    /// Last Use reset result for the popover; the view clears it after a few seconds.
    @Published var resetCreditOutcome: (message: String, at: Date)?
    /// Mirrors `resetCreditRedeemer.isRedeeming` as published state so SwiftUI re-renders around a redemption.
    @Published private(set) var isRedeemingResetCredit = false

    let resetCreditRedeemer: OpenAIResetCreditRedeemer

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
    private var isPollingPaused = false
    private var cursorBackoffUntil: Date?
    private(set) var openAIBackoffUntil: Date?
    private var elevenLabsBackoffUntil: Date?
    private var cursorBackoffInterval: TimeInterval?
    private(set) var openAIBackoffInterval: TimeInterval?
    private var elevenLabsBackoffInterval: TimeInterval?
    private var cursorFetchTask: Task<Void, Never>?
    private var openAIFetchTask: Task<Void, Never>?
    private var elevenLabsFetchTask: Task<Void, Never>?
    private var pendingManualCursorRefresh = false
    private var pendingManualOpenAIRefresh = false
    private var pendingManualElevenLabsRefresh = false
    private let lowPowerModeEnabled: () -> Bool
    private var lastWakeAt: Date?

    /// Incremented once at the end of each full `fetchAll`, success or failure.
    @Published private(set) var pollCompletionCount: UInt = 0

    /// Timer cadence currently scheduled (includes low-power doubling).
    var effectivePollingInterval: TimeInterval {
        PollingBackoff.pollingInterval(
            minutes: pollingMinutes,
            isLowPower: lowPowerModeEnabled()
        )
    }

    /// Interval last installed on the polling timer; nil when no timer is scheduled.
    /// Test seam for low-power reschedule (distinct from the dynamic `effectivePollingInterval`).
    private(set) var installedPollingInterval: TimeInterval?

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
        planInfoInterval: TimeInterval = 3600,
        resetCreditRedeemer: OpenAIResetCreditRedeemer? = nil,
        lowPowerModeEnabled: @escaping () -> Bool = {
            ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    ) {
        self.session = session
        self.resetCreditRedeemer = resetCreditRedeemer
            ?? OpenAIResetCreditRedeemer(session: session, defaults: .standard)
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
        self.lowPowerModeEnabled = lowPowerModeEnabled

        let storedMinutes = UserDefaults.standard.integer(forKey: "pollingMinutes")
        pollingMinutes = UsageService.pollingOptions.contains(storedMinutes)
            ? storedMinutes
            : UsageService.defaultPollingMinutes
        updateConfiguredState()
    }

    func startPolling() {
        isPollingPaused = false
        updateConfiguredState()
        Task { await fetchAll(trigger: .automatic) }
        scheduleTimer()
    }

    func pausePolling() {
        isPollingPaused = true
        timer?.invalidate()
        timer = nil
        installedPollingInterval = nil
    }

    func handleWake() {
        let now = Date()
        if let lastWakeAt, now.timeIntervalSince(lastWakeAt) < 2 { return }
        lastWakeAt = now
        let wasPaused = isPollingPaused
        isPollingPaused = false
        Task {
            await fetchAll(trigger: .automatic)
            if wasPaused || timer == nil {
                scheduleTimer()
            }
        }
    }

    /// Call when Low Power Mode flips so the timer picks up the doubled (or restored) interval.
    func rescheduleForPowerState() {
        scheduleTimer()
    }

    func updatePollingInterval(_ minutes: Int) {
        pollingMinutes = minutes
        scheduleTimer()
    }

    /// Popover-open path: refresh providers whose last successful fetch is older than `interval`.
    func refreshIfStale(olderThan interval: TimeInterval) async {
        updateConfiguredState()
        let now = Date()
        if isCursorConfigured {
            let stale = cursorLastUpdated.map { now.timeIntervalSince($0) > interval } ?? true
            if stale { await fetchCursorUsage(trigger: .automatic) }
        }
        if isOpenAIConfigured {
            let stale = openAILastUpdated.map { now.timeIntervalSince($0) > interval } ?? true
            if stale { await fetchOpenAIUsage(trigger: .automatic) }
        }
        if isElevenLabsConfigured {
            let stale = elevenLabsLastUpdated.map { now.timeIntervalSince($0) > interval } ?? true
            if stale { await fetchElevenLabsUsage(trigger: .automatic) }
        }
        pollCompletionCount &+= 1
    }

    func fetchAll(trigger: PollingBackoff.Trigger = .manual) async {
        updateConfiguredState()
        async let cursor: Void = fetchCursorUsage(trigger: trigger)
        async let openAI: Void = fetchOpenAIUsage(trigger: trigger)
        async let elevenLabs: Void = fetchElevenLabsUsage(trigger: trigger)
        _ = await (cursor, openAI, elevenLabs)
        pollCompletionCount &+= 1
    }

    func fetchAll(force: Bool) async {
        await fetchAll(trigger: force ? .manual : .scheduled)
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

    func fetchCursorUsage(trigger: PollingBackoff.Trigger = .manual) async {
        if let cursorFetchTask {
            if trigger == .manual {
                pendingManualCursorRefresh = true
            }
            await cursorFetchTask.value
            // The task owner runs the trailing manual fetch; no recursion here.
            return
        }

        if !trigger.skipsBackoff,
           PollingBackoff.shouldSkipForBackoff(until: cursorBackoffUntil) {
            return
        }
        if !trigger.skipsDebounce,
           PollingBackoff.shouldSkipScheduledPoll(lastSuccessfulFetch: cursorLastUpdated) {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.pendingManualCursorRefresh = false
                await self.performFetchCursorUsage()
            } while self.pendingManualCursorRefresh
        }
        cursorFetchTask = task
        await task.value
        cursorFetchTask = nil
        if pendingManualCursorRefresh {
            await fetchCursorUsage(trigger: .manual)
        }
    }

    func fetchCursorUsage(force: Bool) async {
        await fetchCursorUsage(trigger: force ? .manual : .scheduled)
    }

    private func performFetchCursorUsage() async {
        updateConfiguredState()
        guard let resolved = resolveCursorCredential() else { return }

        do {
            let decoded: CursorUsageResponse
            if resolved.source == .cursorCLI {
                var request = CursorConnectAPI.request(
                    method: CursorConnectAPI.getCurrentPeriodUsage,
                    token: resolved.token
                )
                request.timeoutInterval = PollingBackoff.usageRequestTimeout
                let data = try await responseData(
                    for: request,
                    serviceName: "Cursor",
                    unauthorizedMessage: Self.cursorCLIUnauthorizedMessage
                )
                decoded = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
                let planRateLimited = await fetchCursorPlanInfoIfNeeded(token: resolved.token)
                cursorUsage = decoded
                cursorError = nil
                cursorLastUpdated = Date()
                if !planRateLimited {
                    clearBackoff(provider: .cursor)
                }
                snapshotStore?.update(
                    provider: "cursor",
                    metrics: UsageSnapshotStore.cursorMetrics(for: decoded),
                    plan: cursorSnapshotPlan(from: decoded)
                )
                notificationService?.checkCursor(
                    apiPercent: decoded.planUsage?.apiPercentUsed,
                    autoPercent: decoded.planUsage?.autoPercentUsed,
                    creditPercent: decoded.spendLimitUsage?.utilization
                )
            } else {
                cursorPlanInfo = nil
                lastCursorPlanInfoFetch = nil
                var request = URLRequest(
                    url: cursorEndpoint,
                    timeoutInterval: PollingBackoff.usageRequestTimeout
                )
                request.httpMethod = "POST"
                request.httpBody = Data("{}".utf8)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
                request.setValue("https://cursor.com/dashboard?tab=spending", forHTTPHeaderField: "Referer")
                request.setValue("WorkosCursorSessionToken=\(resolved.token)", forHTTPHeaderField: "Cookie")
                let data = try await responseData(for: request, serviceName: "Cursor")
                decoded = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
                cursorUsage = decoded
                cursorError = nil
                cursorLastUpdated = Date()
                clearBackoff(provider: .cursor)
                snapshotStore?.update(
                    provider: "cursor",
                    metrics: UsageSnapshotStore.cursorMetrics(for: decoded),
                    plan: cursorSnapshotPlan(from: decoded)
                )
                notificationService?.checkCursor(
                    apiPercent: decoded.planUsage?.apiPercentUsed,
                    autoPercent: decoded.planUsage?.autoPercentUsed,
                    creditPercent: decoded.spendLimitUsage?.utilization
                )
            }
        } catch let error as ConnectedUsageError {
            if case .rateLimited(_, let retryAfter) = error {
                applyBackoff(provider: .cursor, retryAfter: retryAfter)
            }
            cursorError = error.localizedDescription
            writeCursorSnapshotError()
        } catch {
            cursorError = error.localizedDescription
            writeCursorSnapshotError()
        }
    }

    func fetchOpenAIUsage(trigger: PollingBackoff.Trigger = .manual) async {
        if let openAIFetchTask {
            if trigger == .manual {
                pendingManualOpenAIRefresh = true
            }
            await openAIFetchTask.value
            // The task owner runs the trailing manual fetch; no recursion here.
            return
        }

        if !trigger.skipsBackoff,
           PollingBackoff.shouldSkipForBackoff(until: openAIBackoffUntil) {
            return
        }
        if !trigger.skipsDebounce,
           PollingBackoff.shouldSkipScheduledPoll(lastSuccessfulFetch: openAILastUpdated) {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.pendingManualOpenAIRefresh = false
                await self.performFetchOpenAIUsage()
            } while self.pendingManualOpenAIRefresh
        }
        openAIFetchTask = task
        await task.value
        openAIFetchTask = nil
        if pendingManualOpenAIRefresh {
            await fetchOpenAIUsage(trigger: .manual)
        }
    }

    func fetchOpenAIUsage(force: Bool) async {
        await fetchOpenAIUsage(trigger: force ? .manual : .scheduled)
    }

    private func performFetchOpenAIUsage() async {
        updateConfiguredState()
        guard let resolved = resolveOpenAICredential() else { return }

        let unauthorizedMessage = resolved.source == .codexCLI
            ? Self.openAICLIUnauthorizedMessage
            : nil
        let accountId = resolved.accountId ?? openAIAccountID
        let requestCredentialIdentity = Self.openAICredentialIdentity(
            source: resolved.source,
            token: resolved.token
        )

        var usageSucceededThisInvocation = false
        do {
            let usageData = try await openAIResponseData(
                endpoint: openAIUsageEndpoint,
                token: resolved.token,
                accountId: accountId,
                unauthorizedMessage: unauthorizedMessage,
                timeout: PollingBackoff.usageRequestTimeout
            )
            let decoded = try JSONDecoder().decode(OpenAIUsageResponse.self, from: usageData)
            // Spark rule: model-specific `additional_rate_limits` stay on the decoded
            // value as extra rows; primary/secondary windows come only from `rate_limit`.
            openAIUsage = decoded
            usageSucceededThisInvocation = true
            if requestCredentialIdentity == currentOpenAICredentialIdentity(),
               let discovered = resolved.accountId ?? decoded.accountId {
                openAIAccountID = discovered
            }
            openAIError = nil
            openAILastUpdated = Date()
            writeOpenAISnapshot()
        } catch let error as ConnectedUsageError {
            if case .rateLimited(_, let retryAfter) = error {
                applyBackoff(provider: .openAI, retryAfter: retryAfter)
            }
            openAIError = error.localizedDescription
            writeOpenAISnapshotError()
            // Stop the provider poll after the first 429; do not hit credits while backing off.
            if case .rateLimited = error {
                return
            }
        } catch {
            openAIError = error.localizedDescription
            writeOpenAISnapshotError()
        }

        var creditsRateLimited = false
        do {
            let creditData = try await openAIResponseData(
                endpoint: openAIResetCreditsEndpoint,
                token: resolved.token,
                accountId: resolved.accountId ?? openAIAccountID,
                unauthorizedMessage: unauthorizedMessage,
                timeout: PollingBackoff.secondaryRequestTimeout
            )
            openAIResetCredits = try JSONDecoder().decode(
                OpenAIResetCreditsResponse.self,
                from: creditData
            )
            if openAIUsage != nil {
                writeOpenAISnapshot()
            }
        } catch let error as ConnectedUsageError {
            if case .rateLimited(_, let retryAfter) = error {
                applyBackoff(provider: .openAI, retryAfter: retryAfter)
                creditsRateLimited = true
            }
            if openAIUsage == nil {
                openAIError = error.localizedDescription
            }
        } catch {
            if openAIUsage == nil {
                openAIError = error.localizedDescription
            }
        }

        // Clear only when this invocation's usage succeeded and credits were not 429.
        // A stale prior `openAIUsage` must not clear backoff after a failed usage retry.
        if usageSucceededThisInvocation, !creditsRateLimited {
            clearBackoff(provider: .openAI)
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

    /// Available `codex_rate_limits` credits, soonest expiry first; credits without an expiry sort last.
    var availableResetCredits: [OpenAIResetCredit] {
        (openAIResetCredits?.credits ?? [])
            .filter { $0.isAvailable && $0.resetType == Self.codexRateLimitsResetType }
            .sorted { lhs, rhs in
                switch (lhs.expiresAtDate, rhs.expiresAtDate) {
                case let (left?, right?): return left < right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return false
                }
            }
    }

    /// The credit Use reset spends next: the soonest-expiring available one.
    var nextResetCredit: OpenAIResetCredit? {
        availableResetCredits.first
    }

    /// Redeems the soonest-expiring credit, then refreshes Codex usage to confirm the reset landed.
    /// One redemption at a time; a second call while one is in flight returns without a message.
    func redeemNextResetCredit() async {
        guard !resetCreditRedeemer.isRedeeming, !isRedeemingResetCredit else { return }
        guard let credit = nextResetCredit else {
            resetCreditOutcome = (OpenAIResetCreditOutcome.noCredit.userMessage, Date())
            return
        }
        guard resolveOpenAICredential() != nil else {
            resetCreditOutcome = ("Codex is not connected.", Date())
            return
        }

        let result = await redeemResetCredit(id: credit.id)
        if let message = result.message, result.error == nil {
            resetCreditOutcome = (message, Date())
        } else if let error = result.error {
            resetCreditOutcome = (Self.popoverMessage(forDeviceRedeemError: error), Date())
        }
    }

    /// Redeems a specific credit for the phone endpoint (and the popover wrapper).
    /// One redemption at a time; a second call returns the in-flight error.
    func redeemResetCredit(id: String) async -> DeviceRedeemResult {
        guard let resolved = resolveOpenAICredential() else {
            return .failure("The Mac has no OpenAI login.")
        }
        if resetCreditRedeemer.isRedeeming || isRedeemingResetCredit {
            return .failure("A redeem is already in progress on the Mac.")
        }

        isRedeemingResetCredit = true
        defer { isRedeemingResetCredit = false }

        let updatedBefore = openAILastUpdated
        do {
            let outcome = try await resetCreditRedeemer.redeem(
                token: resolved.token,
                accountID: resolved.accountId ?? openAIAccountID,
                creditID: id
            )
            switch outcome {
            case .reset, .alreadyRedeemed:
                await fetchOpenAIUsage()
                let advanced: Bool
                if let after = openAILastUpdated {
                    advanced = updatedBefore.map { after > $0 } ?? true
                } else {
                    advanced = false
                }
                if advanced && openAIError == nil {
                    return .success(outcome)
                }
                return .failure(Self.resetUnconfirmedMessage)
            case .nothingToReset, .noCredit:
                return .success(outcome)
            }
        } catch {
            return .failure(Self.deviceRedeemErrorMessage(error))
        }
    }

    static let resetUnconfirmedMessage =
        "The reset was applied, but Codex could not confirm the new limits. Refresh to check."

    private static let codexRateLimitsResetType = "codex_rate_limits"

    /// Map endpoint/contract strings back to the popover copy for the Mac UI.
    private static func popoverMessage(forDeviceRedeemError error: String) -> String {
        if error == "The Mac has no OpenAI login." {
            return "Codex is not connected."
        }
        if error == "A redeem is already in progress on the Mac." {
            return "A redemption is already in progress."
        }
        if error.hasPrefix("OpenAI returned "), error.hasSuffix(".") {
            let status = error.dropFirst("OpenAI returned ".count).dropLast()
            if status != "an invalid response" {
                return "Codex HTTP \(status)"
            }
            return "Codex returned an invalid response"
        }
        return error
    }

    private func writeOpenAISnapshot() {
        guard let openAIUsage else { return }
        snapshotStore?.update(
            provider: "openai",
            metrics: UsageSnapshotStore.openAIMetrics(
                for: openAIUsage,
                resetCredits: openAIResetCredits
            ),
            plan: openAIUsage.planType.map { UsageSnapshotPlan(label: $0) },
            credits: openAISnapshotCredits()
        )
    }

    private func openAISnapshotCredits() -> UsageSnapshotCredits? {
        let items = availableResetCredits.map {
            UsageSnapshotCreditItem(id: $0.id, expiresAt: $0.expiresAtDate)
        }
        if items.isEmpty, openAIResetCredits == nil {
            return nil
        }
        return UsageSnapshotCredits(available: items.count, items: items)
    }

    private func writeOpenAISnapshotError() {
        guard let openAIError else { return }
        snapshotStore?.update(provider: "openai", error: openAIError)
    }

    private func writeCursorSnapshotError() {
        guard let cursorError else { return }
        snapshotStore?.update(provider: "cursor", error: cursorError)
    }

    private func writeElevenLabsSnapshotError() {
        guard let elevenLabsError else { return }
        snapshotStore?.update(provider: "elevenlabs", error: elevenLabsError)
    }

    private func cursorSnapshotPlan(from usage: CursorUsageResponse) -> UsageSnapshotPlan? {
        let info = cursorPlanInfo?.planInfo
        let renewsAt = Self.millisecondDate(from: info?.billingCycleEnd) ?? usage.billingCycleEndDate
        let plan = UsageSnapshotPlan(
            label: info?.planName,
            priceText: info?.price,
            renewsAt: renewsAt,
            includedAmountCents: info?.includedAmountCents
        )
        if plan.label == nil,
           plan.priceText == nil,
           plan.renewsAt == nil,
           plan.includedAmountCents == nil {
            return nil
        }
        return plan
    }

    private static func millisecondDate(from value: String?) -> Date? {
        guard let value, let milliseconds = Double(value) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private static func deviceRedeemErrorMessage(_ error: Error) -> String {
        switch error as? OpenAIResetCreditError {
        case .inFlight?:
            return "A redeem is already in progress on the Mac."
        case .http(let status)?:
            return "OpenAI returned \(status)."
        case .invalidResponse?:
            return "OpenAI returned an invalid response."
        case nil:
            return error.localizedDescription
        }
    }

    func fetchElevenLabsUsage(trigger: PollingBackoff.Trigger = .manual) async {
        if let elevenLabsFetchTask {
            if trigger == .manual {
                pendingManualElevenLabsRefresh = true
            }
            await elevenLabsFetchTask.value
            // The task owner runs the trailing manual fetch; no recursion here.
            return
        }

        if !trigger.skipsBackoff,
           PollingBackoff.shouldSkipForBackoff(until: elevenLabsBackoffUntil) {
            return
        }
        if !trigger.skipsDebounce,
           PollingBackoff.shouldSkipScheduledPoll(lastSuccessfulFetch: elevenLabsLastUpdated) {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.pendingManualElevenLabsRefresh = false
                await self.performFetchElevenLabsUsage()
            } while self.pendingManualElevenLabsRefresh
        }
        elevenLabsFetchTask = task
        await task.value
        elevenLabsFetchTask = nil
        if pendingManualElevenLabsRefresh {
            await fetchElevenLabsUsage(trigger: .manual)
        }
    }

    func fetchElevenLabsUsage(force: Bool) async {
        await fetchElevenLabsUsage(trigger: force ? .manual : .scheduled)
    }

    private func performFetchElevenLabsUsage() async {
        guard let apiKey = elevenLabsAPIKey else { return }

        var request = URLRequest(
            url: elevenLabsSubscriptionEndpoint,
            timeoutInterval: PollingBackoff.usageRequestTimeout
        )
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
            clearBackoff(provider: .elevenLabs)
            snapshotStore?.update(
                provider: "elevenlabs",
                metrics: UsageSnapshotStore.elevenLabsMetrics(for: decoded),
                plan: decoded.tier.map { UsageSnapshotPlan(label: $0) }
            )
        } catch let error as ConnectedUsageError {
            if case .rateLimited(_, let retryAfter) = error {
                applyBackoff(provider: .elevenLabs, retryAfter: retryAfter)
            }
            elevenLabsError = error.localizedDescription
            writeElevenLabsSnapshotError()
        } catch {
            elevenLabsError = error.localizedDescription
            writeElevenLabsSnapshotError()
        }
    }

    /// Returns `true` when plan info hit a 429 and applied provider backoff.
    @discardableResult
    private func fetchCursorPlanInfoIfNeeded(token: String) async -> Bool {
        let now = Date()
        if isFetchingCursorPlanInfo {
            return false
        }
        if let lastCursorPlanInfoFetch,
           now.timeIntervalSince(lastCursorPlanInfoFetch) < planInfoInterval {
            return false
        }

        isFetchingCursorPlanInfo = true
        lastCursorPlanInfoFetch = now
        defer { isFetchingCursorPlanInfo = false }

        do {
            var request = CursorConnectAPI.request(
                method: CursorConnectAPI.getPlanInfo,
                token: token
            )
            request.timeoutInterval = PollingBackoff.secondaryRequestTimeout
            let data = try await responseData(
                for: request,
                serviceName: "Cursor",
                unauthorizedMessage: Self.cursorCLIUnauthorizedMessage
            )
            cursorPlanInfo = try JSONDecoder().decode(CursorPlanInfoResponse.self, from: data)
            return false
        } catch let error as ConnectedUsageError {
            if case .rateLimited(_, let retryAfter) = error {
                applyBackoff(provider: .cursor, retryAfter: retryAfter)
                return true
            }
            return false
        } catch {
            return false
        }
    }

    private func openAIResponseData(
        endpoint: URL,
        token: String,
        accountId: String?,
        unauthorizedMessage: String?,
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
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
            if http.statusCode == 429 {
                throw ConnectedUsageError.rateLimited(
                    serviceName,
                    PollingBackoff.retryAfterSeconds(from: http)
                )
            }
            if (http.statusCode == 401 || http.statusCode == 403),
               let unauthorizedMessage {
                throw ConnectedUsageError.unauthorized(unauthorizedMessage)
            }
            throw ConnectedUsageError.http(serviceName, http.statusCode)
        }
        return data
    }

    private enum BackoffProvider {
        case cursor, openAI, elevenLabs
    }

    private func applyBackoff(provider: BackoffProvider, retryAfter: TimeInterval?) {
        let base = PollingBackoff.pollingInterval(
            minutes: pollingMinutes,
            isLowPower: lowPowerModeEnabled()
        )
        let current: TimeInterval
        switch provider {
        case .cursor: current = cursorBackoffInterval ?? base
        case .openAI: current = openAIBackoffInterval ?? base
        case .elevenLabs: current = elevenLabsBackoffInterval ?? base
        }
        let delay = PollingBackoff.backoffInterval(
            retryAfter: retryAfter,
            currentInterval: current
        )
        let until = Date().addingTimeInterval(delay)
        switch provider {
        case .cursor:
            cursorBackoffInterval = delay
            cursorBackoffUntil = until
        case .openAI:
            openAIBackoffInterval = delay
            openAIBackoffUntil = until
        case .elevenLabs:
            elevenLabsBackoffInterval = delay
            elevenLabsBackoffUntil = until
        }
    }

    private func clearBackoff(provider: BackoffProvider) {
        switch provider {
        case .cursor:
            cursorBackoffInterval = nil
            cursorBackoffUntil = nil
        case .openAI:
            openAIBackoffInterval = nil
            openAIBackoffUntil = nil
        case .elevenLabs:
            elevenLabsBackoffInterval = nil
            elevenLabsBackoffUntil = nil
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        installedPollingInterval = nil
        guard !isPollingPaused else { return }
        let interval = effectivePollingInterval
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPollingPaused else { return }
                Task { await self.fetchAll(trigger: .scheduled) }
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        installedPollingInterval = interval
    }

    /// Pasted or environment tokens only.
    private var elevenLabsAPIKey: String? {
        credentialsStore.load().elevenLabsAPIKey
            ?? environment["ELEVENLABS_API_KEY"].flatMap(ConnectedTokenNormalizer.elevenLabs)
    }

    private func resolveOpenAICredential() -> ResolvedOpenAICredential? {
        if let cli = codexAuthLoader() {
            return ResolvedOpenAICredential(
                token: cli.accessToken,
                source: .codexCLI,
                accountId: cli.accountId,
                expiry: JWTClaims.expiry(of: cli.accessToken)
            )
        }
        if let pasted = credentialsStore.load().openAISessionToken {
            return ResolvedOpenAICredential(
                token: pasted,
                source: .pasted,
                accountId: nil,
                expiry: nil
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
        if let cli = CursorCLIKeychain.load(runner: cursorKeychainRunner) {
            return ResolvedCursorCredential(
                token: cli.accessToken,
                source: .cursorCLI,
                expiry: JWTClaims.expiry(of: cli.accessToken)
            )
        }
        if let pasted = credentialsStore.load().cursorSessionToken {
            return ResolvedCursorCredential(token: pasted, source: .pasted, expiry: nil)
        }
        if let env = environment["CURSOR_SESSION_TOKEN"].flatMap(ConnectedTokenNormalizer.cursor) {
            return ResolvedCursorCredential(token: env, source: .environment, expiry: nil)
        }
        return nil
    }

    private func updateConfiguredState() {
        let stored = credentialsStore.load()
        hasStoredOpenAIToken = stored.openAISessionToken != nil
        hasStoredCursorToken = stored.cursorSessionToken != nil

        if let openAI = resolveOpenAICredential() {
            isOpenAIConfigured = true
            openAICredentialSource = openAI.source
            openAITokenExpiry = openAI.source == .codexCLI ? openAI.expiry : nil
            let identity = Self.openAICredentialIdentity(source: openAI.source, token: openAI.token)
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

    private func currentOpenAICredentialIdentity() -> String? {
        guard let openAI = resolveOpenAICredential() else { return nil }
        return Self.openAICredentialIdentity(source: openAI.source, token: openAI.token)
    }

    /// Source plus a SHA-256 of the token so an in-flight response can tell whether the
    /// credential that started the request is still current, without keeping the raw token.
    private static func openAICredentialIdentity(source: OpenAICredentialSource, token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return "\(source)|\(hash)"
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
    case rateLimited(String, TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let service):
            return "\(service) returned an invalid response"
        case .unauthorized(let message):
            return message
        case .rateLimited(let service, _):
            return "\(service) rate limited"
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
