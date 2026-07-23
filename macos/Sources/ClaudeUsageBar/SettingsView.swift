import SwiftUI
import ServiceManagement

struct SettingsWindowContent: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var connectedService: ConnectedUsageService
    @State private var openAIToken = ""
    @State private var cursorToken = ""
    @State private var credentialMessage: String?

    var body: some View {
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

            Section("Notifications") {
                ThresholdSlider(
                    label: "5-hour window",
                    value: notificationService.threshold5h,
                    onChange: { notificationService.setThreshold5h($0) }
                )
                ThresholdSlider(
                    label: "7-day window",
                    value: notificationService.threshold7d,
                    onChange: { notificationService.setThreshold7d($0) }
                )
                ThresholdSlider(
                    label: "Extra usage",
                    value: notificationService.thresholdExtra,
                    onChange: { notificationService.setThresholdExtra($0) }
                )
            }

            Section("OpenAI / Codex") {
                Text("Use the bearer token from the Authorization header of a ChatGPT usage request. OpenAI API keys do not expose ChatGPT subscription limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField(
                    connectedService.isOpenAIConfigured
                        ? "Session token configured"
                        : "Bearer session token",
                    text: $openAIToken
                )

                HStack {
                    Button("Save Session Token") {
                        saveOpenAIToken()
                    }
                    .disabled(openAIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if connectedService.isOpenAIConfigured {
                        Button("Clear", role: .destructive) {
                            connectedService.clearOpenAIToken()
                        }
                    }
                }
            }

            Section("Cursor") {
                Text("Paste the WorkosCursorSessionToken cookie value from cursor.com. You can also paste a full Cookie header or copied cURL request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField(
                    connectedService.isCursorConfigured
                        ? "Session token configured"
                        : "WorkosCursorSessionToken",
                    text: $cursorToken
                )

                HStack {
                    Button("Save Session Token") {
                        saveCursorToken()
                    }
                    .disabled(cursorToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if connectedService.isCursorConfigured {
                        Button("Clear", role: .destructive) {
                            connectedService.clearCursorToken()
                        }
                    }
                }
            }

            if let credentialMessage {
                Text(credentialMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if service.isAuthenticated {
                Section("Anthropic Account") {
                    if let email = service.accountEmail {
                        ObfuscatedEmailRow(email: email)
                    }
                    Button("Sign Out") {
                        service.signOut()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            focusSettingsWindow()
        }
    }

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
