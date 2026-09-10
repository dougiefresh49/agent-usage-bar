import SwiftUI
import ServiceManagement

private enum SettingsTab: Hashable {
    case general
    case providers
    case appearance
    case notifications
    case devices
}

struct SettingsWindowContent: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var connectedService: ConnectedUsageService
    @ObservedObject var deviceSyncManager: DeviceSyncManager
    @State private var selectedTab: SettingsTab = .general
    @State private var openAIToken = ""
    @State private var cursorToken = ""
    @State private var elevenLabsAPIKey = ""
    @State private var credentialMessage: String?
    @AppStorage(UsagePresentationDefaults.menuBarProviderKey)
    private var menuBarProviderRaw = UsagePresentationDefaults.menuBarProvider.rawValue
    @AppStorage(UsagePresentationDefaults.menuBarStyleKey)
    private var menuBarStyleRaw = UsagePresentationDefaults.menuBarStyle.rawValue
    @AppStorage(UsagePresentationDefaults.menuBarPrimaryMetricKey)
    private var menuBarPrimaryMetricID = UsagePresentationMetrics.claudeFiveHourID
    @AppStorage(UsagePresentationDefaults.menuBarSecondaryMetricKey)
    private var menuBarSecondaryMetricID = UsagePresentationMetrics.claudeSevenDayID
    @AppStorage(UsagePresentationDefaults.detailStyleKey)
    private var detailStyleRaw = UsagePresentationDefaults.detailStyle.rawValue
    @AppStorage(UsagePresentationDefaults.textSizeKey)
    private var usageTextSizeRaw = UsagePresentationDefaults.textSize.rawValue
    @AppStorage(UsagePresentationDefaults.fillModeKey)
    private var fillModeRaw = UsagePresentationDefaults.fillMode.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            providersTab
                .tabItem { Label("Providers", systemImage: "cpu") }
                .tag(SettingsTab.providers)

            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)

            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)

            DevicesSettingsView(
                service: service,
                notificationService: notificationService,
                deviceSyncManager: deviceSyncManager
            )
            .tabItem { Label("Devices", systemImage: "laptopcomputer.and.iphone") }
            .tag(SettingsTab.devices)
        }
        .frame(width: 520, height: 560)
        .onAppear {
            focusSettingsWindow()
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("General") {
                LaunchAtLoginToggle()

                Picker("Polling Interval", selection: Binding(
                    get: { service.pollingMinutes },
                    set: {
                        service.updatePollingInterval($0)
                        connectedService.updatePollingInterval($0)
                    }
                )) {
                    ForEach(UsageService.pollingOptions, id: \.self) { mins in
                        Text(pollingOptionLabel(for: mins))
                            .tag(mins)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersionString)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section("Appearance") {
                Picker("Preferred Provider", selection: menuBarProviderBinding) {
                    ForEach(UsageProvider.allCases) { provider in
                        Text(provider.settingsName)
                            .tag(provider.rawValue)
                    }
                }

                Picker("Menu Bar Style", selection: $menuBarStyleRaw) {
                    ForEach(MenuBarVisualizationStyle.allCases) { style in
                        Text(style.displayName)
                            .tag(style.rawValue)
                    }
                }

                Picker("Primary Stat", selection: primaryMetricBinding) {
                    ForEach(menuBarMetricOptions) { metric in
                        Text(metric.label)
                            .tag(metric.id)
                    }
                }

                Picker("Secondary Stat", selection: secondaryMetricBinding) {
                    ForEach(menuBarMetricOptions.filter { $0.id != primaryMetricBinding.wrappedValue }) { metric in
                        Text(metric.label)
                            .tag(metric.id)
                    }
                }

                Picker("Provider Details", selection: $detailStyleRaw) {
                    ForEach(DetailVisualizationStyle.allCases) { style in
                        Text(style.displayName)
                            .tag(style.rawValue)
                    }
                }

                Picker("Usage Display", selection: $fillModeRaw) {
                    ForEach(UsageFillMode.allCases) { mode in
                        Text(mode.displayName)
                            .tag(mode.rawValue)
                    }
                }

                Picker("Usage Text Size", selection: $usageTextSizeRaw) {
                    ForEach(UsageTextSize.allCases) { size in
                        Text(size.displayName)
                            .tag(size.rawValue)
                    }
                }

                Text("Text size applies to the overview and provider details. Large uses two overview columns for readability.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Preferred Provider controls the menu bar and single-provider desktop widgets. Provider Details also controls the widget visualization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Orbit is used in provider details and desktop widgets; the menu bar stays readable with bars or a split capsule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Fill shows what you have used: bars grow and the headline reads \"31% used\". Drain shows what is left: bars shrink and the headline reads \"69% left\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Providers

    private var providersTab: some View {
        Form {
            Section("Claude") {
                if service.claudeCredentialSource != .none {
                    Text(claudeCredentialStatusText(
                        source: service.claudeCredentialSource,
                        expiry: service.claudeCodeTokenExpiry
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let email = service.accountEmail {
                    ObfuscatedEmailRow(email: email)
                }

                DisclosureGroup(claudeAppSignInDisclosureTitle(source: service.claudeCredentialSource)) {
                    if service.hasStoredAppOAuth {
                        if service.claudeCredentialSource == .claudeCode {
                            Text("This app's own sign-in is also stored and not in use.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Sign Out") {
                            service.signOut()
                        }
                    } else if service.isAwaitingCode {
                        CodeEntryView(service: service)
                    } else {
                        Button("Sign in with Anthropic") {
                            service.startOAuthFlow()
                        }
                    }
                }
            }

            Section("OpenAI / Codex") {
                Text(openAICredentialStatusText(
                    source: connectedService.openAICredentialSource,
                    expiry: connectedService.openAITokenExpiry,
                    hasStoredPastedToken: connectedService.hasStoredOpenAIToken
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                DisclosureGroup(openAIPastedTokenDisclosureTitle(source: connectedService.openAICredentialSource)) {
                    Text("Use the bearer token from the Authorization header of a ChatGPT usage request. OpenAI API keys do not expose ChatGPT subscription limits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CredentialSecureField(
                        title: connectedService.hasStoredOpenAIToken
                            ? "Session token configured"
                            : "Bearer session token",
                        text: $openAIToken
                    )

                    HStack {
                        Button("Save Session Token") {
                            saveOpenAIToken()
                        }
                        .disabled(openAIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if connectedService.hasStoredOpenAIToken {
                            Button("Clear", role: .destructive) {
                                connectedService.clearOpenAIToken()
                            }
                        }
                    }
                }
            }

            Section("Cursor") {
                Text(cursorCredentialStatusText(
                    source: connectedService.cursorCredentialSource,
                    expiry: connectedService.cursorTokenExpiry,
                    hasStoredPastedToken: connectedService.hasStoredCursorToken
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                DisclosureGroup(cursorPastedTokenDisclosureTitle(source: connectedService.cursorCredentialSource)) {
                    Text("Paste the WorkosCursorSessionToken cookie value from cursor.com. You can also paste a full Cookie header or copied cURL request.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CredentialSecureField(
                        title: connectedService.hasStoredCursorToken
                            ? "Session token configured"
                            : "WorkosCursorSessionToken",
                        text: $cursorToken
                    )

                    HStack {
                        Button("Save Session Token") {
                            saveCursorToken()
                        }
                        .disabled(cursorToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if connectedService.hasStoredCursorToken {
                            Button("Clear", role: .destructive) {
                                connectedService.clearCursorToken()
                            }
                        }
                    }
                }
            }

            Section("ElevenLabs") {
                Text("Add an ElevenLabs API key that can access the user subscription endpoint. The key is sent only to api.elevenlabs.io and saved locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                CredentialSecureField(
                    title: connectedService.isElevenLabsConfigured
                        ? "API key configured"
                        : "ElevenLabs API key",
                    text: $elevenLabsAPIKey
                )

                HStack {
                    Button("Save API Key") {
                        saveElevenLabsAPIKey()
                    }
                    .disabled(
                        elevenLabsAPIKey
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )

                    if connectedService.isElevenLabsConfigured {
                        Button("Clear", role: .destructive) {
                            connectedService.clearElevenLabsAPIKey()
                        }
                    }
                }
            }

            if let credentialMessage {
                Section {
                    Text(credentialMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Notifications

    private var notificationsTab: some View {
        Form {
            if !service.isAuthenticated
                && !connectedService.isOpenAIConfigured
                && !connectedService.isCursorConfigured {
                Section {
                    Text("Connect a provider in Providers to configure alert thresholds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if service.isAuthenticated {
                Section("Claude") {
                    ThresholdSlider(
                        label: "Session usage",
                        value: notificationService.claudeSessionThreshold,
                        onChange: { notificationService.setClaudeSessionThreshold($0) }
                    )
                    ThresholdSlider(
                        label: "Seven-day usage",
                        value: notificationService.claudeSevenDayThreshold,
                        onChange: { notificationService.setClaudeSevenDayThreshold($0) }
                    )
                    ThresholdSlider(
                        label: "Fable usage",
                        value: notificationService.claudeFableThreshold,
                        onChange: { notificationService.setClaudeFableThreshold($0) }
                    )
                }
            }

            if connectedService.isOpenAIConfigured {
                Section("Codex") {
                    ThresholdSlider(
                        label: "Weekly usage limits",
                        value: notificationService.openAIWeeklyThreshold,
                        onChange: { notificationService.setOpenAIWeeklyThreshold($0) }
                    )
                    CountThresholdSlider(
                        label: "Reset credits",
                        value: notificationService.openAIResetCreditsThreshold,
                        onChange: { notificationService.setOpenAIResetCreditsThreshold($0) }
                    )
                }
            }

            if connectedService.isCursorConfigured {
                Section("Cursor") {
                    ThresholdSlider(
                        label: "API usage",
                        value: notificationService.cursorAPIThreshold,
                        onChange: { notificationService.setCursorAPIThreshold($0) }
                    )
                    ThresholdSlider(
                        label: "Auto usage",
                        value: notificationService.cursorAutoThreshold,
                        onChange: { notificationService.setCursorAutoThreshold($0) }
                    )
                    ThresholdSlider(
                        label: "Credit",
                        value: notificationService.cursorCreditThreshold,
                        onChange: { notificationService.setCursorCreditThreshold($0) }
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func saveOpenAIToken() {
        do {
            try connectedService.saveOpenAIToken(openAIToken)
            openAIToken = ""
            credentialMessage = "OpenAI session token saved locally."
            Task { await connectedService.fetchOpenAIUsage() }
        } catch {
            credentialMessage = "Could not save OpenAI token: \(error.localizedDescription)"
        }
    }

    private func saveCursorToken() {
        do {
            try connectedService.saveCursorToken(cursorToken)
            cursorToken = ""
            credentialMessage = "Cursor session token saved locally."
            Task { await connectedService.fetchCursorUsage() }
        } catch {
            credentialMessage = "Could not save Cursor token: \(error.localizedDescription)"
        }
    }

    private func saveElevenLabsAPIKey() {
        do {
            try connectedService.saveElevenLabsAPIKey(elevenLabsAPIKey)
            elevenLabsAPIKey = ""
            credentialMessage = "ElevenLabs API key saved locally."
            Task { await connectedService.fetchElevenLabsUsage() }
        } catch {
            credentialMessage = "Could not save ElevenLabs API key: \(error.localizedDescription)"
        }
    }

    // MARK: - Appearance bindings

    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, !build.isEmpty, build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    private var selectedMenuBarProvider: UsageProvider {
        UsageProvider(rawValue: menuBarProviderRaw)
            ?? UsagePresentationDefaults.menuBarProvider
    }

    private var menuBarMetricOptions: [UsagePresentationMetric] {
        UsagePresentationMetrics.metrics(
            for: selectedMenuBarProvider,
            claude: service,
            connectedService: connectedService
        )
    }

    private var menuBarProviderBinding: Binding<String> {
        Binding(
            get: { selectedMenuBarProvider.rawValue },
            set: { rawValue in
                guard let provider = UsageProvider(rawValue: rawValue) else { return }
                menuBarProviderRaw = provider.rawValue
                let metrics = UsagePresentationMetrics.metrics(
                    for: provider,
                    claude: service,
                    connectedService: connectedService
                )
                let defaults = UsagePresentationMetrics.defaults(
                    for: provider,
                    available: metrics
                )
                menuBarPrimaryMetricID = defaults.primary
                menuBarSecondaryMetricID = defaults.secondary
            }
        )
    }

    private var primaryMetricBinding: Binding<String> {
        Binding(
            get: {
                resolvedMetricID(
                    stored: menuBarPrimaryMetricID,
                    fallback: UsagePresentationMetrics.defaults(
                        for: selectedMenuBarProvider,
                        available: menuBarMetricOptions
                    ).primary
                )
            },
            set: { newValue in
                menuBarPrimaryMetricID = newValue
                if menuBarSecondaryMetricID == newValue {
                    menuBarSecondaryMetricID = menuBarMetricOptions
                        .first(where: { $0.id != newValue })?.id ?? newValue
                }
            }
        )
    }

    private var secondaryMetricBinding: Binding<String> {
        Binding(
            get: {
                let defaults = UsagePresentationMetrics.defaults(
                    for: selectedMenuBarProvider,
                    available: menuBarMetricOptions
                )
                let fallback = defaults.secondary == primaryMetricBinding.wrappedValue
                    ? menuBarMetricOptions.first(where: { $0.id != primaryMetricBinding.wrappedValue })?.id ?? defaults.secondary
                    : defaults.secondary
                return resolvedMetricID(stored: menuBarSecondaryMetricID, fallback: fallback)
            },
            set: { menuBarSecondaryMetricID = $0 }
        )
    }

    private func resolvedMetricID(stored: String, fallback: String) -> String {
        menuBarMetricOptions.contains(where: { $0.id == stored })
            ? stored
            : fallback
    }
}

@MainActor
private func focusSettingsWindow() {
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.last(where: { $0.isVisible && $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}

struct LaunchAtLoginToggle: View {
    @StateObject private var model: LaunchAtLoginModel
    private let controlSize: ControlSize
    private let useSwitchStyle: Bool

    init(
        controlSize: ControlSize = .regular,
        useSwitchStyle: Bool = false,
        bundleURL: URL = Bundle.main.bundleURL
    ) {
        _model = StateObject(
            wrappedValue: LaunchAtLoginModel(bundleURL: bundleURL)
        )
        self.controlSize = controlSize
        self.useSwitchStyle = useSwitchStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            toggle

            if let message = model.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var toggle: some View {
        let baseToggle = Toggle("Launch at Login", isOn: Binding(
            get: { model.isEnabled },
            set: { model.setEnabled($0) }
        ))
        .disabled(!model.isSupported)
        .controlSize(controlSize)

        if useSwitchStyle {
            baseToggle.toggleStyle(.switch)
        } else {
            baseToggle
        }
    }
}

@MainActor
final class LaunchAtLoginModel: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isSupported: Bool
    @Published private(set) var message: String?

    init(bundleURL: URL = Bundle.main.bundleURL) {
        isSupported = supportsLaunchAtLoginManagement(appURL: bundleURL)

        guard isSupported else {
            message = "Install the app in Applications to manage launch at login."
            return
        }

        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = enabled
            message = nil
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
            message = "Could not update launch at login."
        }
    }
}

func supportsLaunchAtLoginManagement(
    appURL: URL = Bundle.main.bundleURL,
    installDirectories: [URL] = launchAtLoginInstallDirectories()
) -> Bool {
    let normalizedAppURL = appURL.resolvingSymlinksInPath().standardizedFileURL

    return installDirectories.contains { directory in
        let normalizedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let directoryPath = normalizedDirectory.path
        let appPath = normalizedAppURL.path

        return appPath == directoryPath || appPath.hasPrefix(directoryPath + "/")
    }
}

func launchAtLoginInstallDirectories(fileManager: FileManager = .default) -> [URL] {
    [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
    ]
}

/// Bordered secure field so credential inputs stay visible in grouped Form sections.
private struct CredentialSecureField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        SecureField(title, text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.28), lineWidth: 1)
            )
    }
}

private struct ThresholdSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        LabeledContent {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: 0...100,
                step: 5
            )
        } label: {
            Text(label)
            Text(value > 0 ? "\(value)%" : "Off")
                .foregroundStyle(.secondary)
        }
        .alignmentGuide(.firstTextBaseline) { d in
            d[VerticalAlignment.center]
        }
    }
}

private struct CountThresholdSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        LabeledContent {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: 0...10,
                step: 1
            )
        } label: {
            Text(label)
            Text(value > 0 ? "≤ \(value)" : "Off")
                .foregroundStyle(.secondary)
        }
        .alignmentGuide(.firstTextBaseline) { d in
            d[VerticalAlignment.center]
        }
    }
}

private struct ObfuscatedEmailRow: View {
    let email: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            emailLabel

            Spacer(minLength: 0)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? "Hide email" : "Show email")
            .accessibilityLabel(isRevealed ? "Hide email" : "Show email")
        }
    }

    @ViewBuilder
    private var emailLabel: some View {
        if isRevealed {
            Text(email)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
        } else {
            Text(obfuscateEmail(email))
                .textSelection(.disabled)
                .foregroundStyle(.primary)
        }
    }
}

/// Masks an email for display, e.g. `doug@example.com` → `d•••@e••••••.com`.
func obfuscateEmail(_ email: String) -> String {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let atIndex = trimmed.firstIndex(of: "@") else {
        return String(repeating: "•", count: max(trimmed.count, 4))
    }

    let local = String(trimmed[..<atIndex])
    let domain = String(trimmed[trimmed.index(after: atIndex)...])

    return "\(obfuscateLocalPart(local))@\(obfuscateDomainPart(domain))"
}

private func obfuscateLocalPart(_ local: String) -> String {
    guard let first = local.first else { return "••••" }
    if local.count == 1 { return String(first) }
    return String(first) + String(repeating: "•", count: max(local.count - 1, 3))
}

private func obfuscateDomainPart(_ domain: String) -> String {
    guard !domain.isEmpty else { return "••••" }

    let parts = domain.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 2 else {
        guard let first = domain.first else { return "••••" }
        return String(first) + String(repeating: "•", count: max(domain.count - 1, 3))
    }

    let tld = parts.last!
    let nameParts = parts.dropLast()
    let maskedName = nameParts.map { part -> String in
        guard let first = part.first else { return "•" }
        if part.count == 1 { return String(first) }
        return String(first) + String(repeating: "•", count: max(part.count - 1, 3))
    }.joined(separator: ".")

    return "\(maskedName).\(tld)"
}

func claudeCredentialStatusText(
    source: ClaudeCredentialSource,
    expiry: Date?,
    now: Date = Date()
) -> String {
    switch source {
    case .claudeCode:
        var text: String
        if let expiry, expiry > now {
            text = "Using Claude Code login (expires in \(credentialExpiryLabel(from: now, to: expiry)))"
        } else {
            text = "Claude Code login expired. Run any claude command to refresh."
        }
        return text
    case .appOAuth:
        return "Using this app's sign-in"
    case .none:
        return ""
    }
}

func claudeAppSignInDisclosureTitle(source: ClaudeCredentialSource) -> String {
    switch source {
    case .claudeCode:
        return "Use this app's sign-in instead"
    case .appOAuth:
        return "Manage this app's sign-in"
    case .none:
        return "Sign in with Anthropic"
    }
}

func openAICredentialStatusText(
    source: OpenAICredentialSource,
    expiry: Date?,
    now: Date = Date(),
    hasStoredPastedToken: Bool = false
) -> String {
    switch source {
    case .pasted:
        return "Using pasted token"
    case .codexCLI:
        return cliCredentialStatusText(
            label: "Using Codex CLI login",
            expiry: expiry,
            now: now,
            hasStoredPastedToken: hasStoredPastedToken
        )
    case .environment:
        return "Using environment variable"
    case .none:
        return "Run `codex login` to connect without pasting a token."
    }
}

/// Disclosure label for the pasted-token controls, following the active source: the pasted
/// token is managed when it is in use, offered as an alternative when a CLI or environment
/// credential is in use, and plainly offered when nothing is connected.
func pastedTokenDisclosureTitle(isPasted: Bool, hasOtherSource: Bool) -> String {
    if isPasted {
        return "Manage pasted token"
    }
    return hasOtherSource ? "Use a pasted token instead" : "Use a pasted token"
}

func openAIPastedTokenDisclosureTitle(source: OpenAICredentialSource) -> String {
    pastedTokenDisclosureTitle(isPasted: source == .pasted, hasOtherSource: source != .none)
}

func cursorPastedTokenDisclosureTitle(source: CursorCredentialSource) -> String {
    pastedTokenDisclosureTitle(isPasted: source == .pasted, hasOtherSource: source != .none)
}

func cursorCredentialStatusText(
    source: CursorCredentialSource,
    expiry: Date?,
    now: Date = Date(),
    hasStoredPastedToken: Bool = false
) -> String {
    switch source {
    case .pasted:
        return "Using pasted token"
    case .cursorCLI:
        return cliCredentialStatusText(
            label: "Using Cursor CLI login",
            expiry: expiry,
            now: now,
            hasStoredPastedToken: hasStoredPastedToken
        )
    case .environment:
        return "Using environment variable"
    case .none:
        return "Run `cursor-agent login` to connect without pasting a token."
    }
}

private func cliCredentialStatusText(
    label: String,
    expiry: Date?,
    now: Date,
    hasStoredPastedToken: Bool
) -> String {
    var text = label
    if let expiry, expiry > now {
        text += " (expires in \(credentialExpiryLabel(from: now, to: expiry)))"
    }
    if hasStoredPastedToken {
        text += ". A pasted token is also stored and not in use."
    }
    return text
}

func credentialExpiryLabel(from now: Date, to expiry: Date) -> String {
    let remaining = max(0, expiry.timeIntervalSince(now))
    let days = Int(remaining / 86_400)
    if days > 0 {
        return "\(days)d"
    }
    let hours = Int(remaining / 3_600)
    if hours > 0 {
        return "\(hours)h"
    }
    let minutes = Int(remaining / 60)
    return "\(minutes)m"
}
