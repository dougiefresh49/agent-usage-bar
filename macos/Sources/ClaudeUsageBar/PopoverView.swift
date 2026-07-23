import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var connectedService: ConnectedUsageService
    @AppStorage("setupComplete") private var setupComplete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !setupComplete && !service.isAuthenticated {
                SetupView(
                    service: service,
                    notificationService: notificationService,
                    connectedService: connectedService,
                    onComplete: { setupComplete = true }
                )
            } else {
                Text("AI Usage")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        claudeView
                        Divider()
                        OpenAIUsageView(service: connectedService)
                        Divider()
                        CursorUsageView(service: connectedService)
                    }
                }

                footer
            }
        }
        .padding()
        .frame(width: 370)
        .frame(maxHeight: 720)
    }

    @ViewBuilder
    private var claudeView: some View {
        ProviderHeader(name: "Claude", systemImage: "sparkles")

        if service.isAuthenticated {
            UsageBucketRow(label: "5-Hour Window", bucket: service.usage?.fiveHour)
            UsageBucketRow(label: "7-Day Window", bucket: service.usage?.sevenDay)

            if let opus = service.usage?.sevenDayOpus, opus.utilization != nil {
                UsageBucketRow(label: "Opus (7 day)", bucket: opus)
            }
            if let sonnet = service.usage?.sevenDaySonnet, sonnet.utilization != nil {
                UsageBucketRow(label: "Sonnet (7 day)", bucket: sonnet)
            }
            ForEach(service.usage?.scopedModelLimits ?? []) { limit in
                UsageValueRow(
                    label: scopedLimitLabel(limit),
                    percent: limit.percent,
                    resetDate: limit.resetsAtDate
                )
            }

            if let extra = service.usage?.extraUsage,
               extra.usedCredits != nil || extra.monthlyLimit != nil {
                ExtraUsageRow(extra: extra)
            }

            DisclosureGroup("Usage history") {
                UsageChartView(historyService: historyService)
                    .padding(.top, 4)
            }
            .font(.caption)
        } else {
            if service.isAwaitingCode {
                CodeEntryView(service: service)
            } else {
                Text("Connect Claude to view account limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Sign in with Claude") {
                    service.startOAuthFlow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        if let error = service.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            if let updaterError = appUpdater.lastError {
                Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                if let latestUpdated {
                    Text("Updated \(latestUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                settingsButton
                Spacer()
                Button("Refresh") {
                    Task {
                        async let claude: Void = service.isAuthenticated
                            ? service.fetchUsage()
                            : ()
                        async let connected: Void = connectedService.fetchAll()
                        _ = await (claude, connected)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                if appUpdater.isConfigured {
                    Button("Check for Updates…") {
                        appUpdater.checkForUpdates()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(!appUpdater.canCheckForUpdates)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var latestUpdated: Date? {
        [
            service.lastUpdated,
            connectedService.openAILastUpdated,
            connectedService.cursorLastUpdated
        ]
        .compactMap { $0 }
        .max()
    }

    private func scopedLimitLabel(_ limit: ClaudeUsageLimit) -> String {
        let model = limit.scope?.model?.displayName ?? "Model"
        switch limit.group {
        case "weekly":
            return "\(model) (7 day)"
        case "session":
            return "\(model) (session)"
        case let group?:
            return "\(model) (\(group.replacingOccurrences(of: "_", with: " ")))"
        case nil:
            return model
        }
    }

    private var settingsButton: some View {
        SettingsLink {
            Text("Settings…")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}

private struct ProviderHeader: View {
    let name: String
    let systemImage: String

    var body: some View {
        Label(name, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OpenAIUsageView: View {
    @ObservedObject var service: ConnectedUsageService

    var body: some View {
        ProviderHeader(name: "OpenAI / Codex", systemImage: "circle.hexagongrid")

        if !service.isOpenAIConfigured {
            configurePrompt("Add a ChatGPT session token in Settings.")
        } else if let usage = service.openAIUsage {
            UsageValueRow(
                label: windowLabel(usage.rateLimit?.primaryWindow, fallback: "Primary Window"),
                percent: usage.rateLimit?.primaryWindow?.usedPercent,
                resetDate: usage.rateLimit?.primaryWindow?.resetDate
            )

            if let secondary = usage.rateLimit?.secondaryWindow {
                UsageValueRow(
                    label: windowLabel(secondary, fallback: "Secondary Window"),
                    percent: secondary.usedPercent,
                    resetDate: secondary.resetDate
                )
            }

            ForEach(usage.additionalRateLimits ?? []) { additional in
                if let window = additional.rateLimit?.primaryWindow {
                    UsageValueRow(
                        label: additional.label ?? additional.type ?? "Additional Limit",
                        percent: window.usedPercent,
                        resetDate: window.resetDate
                    )
                }
            }

            let announcements = service.openAIResetCredits?.credits.filter(\.isAvailable) ?? []
            if !announcements.isEmpty {
                DisclosureGroup("Announcements (\(announcements.count))") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(announcements) { credit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(credit.title ?? "Available reset")
                                    .font(.caption.weight(.medium))
                                if let description = credit.description {
                                    Text(description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let expiry = credit.expiresAtDate {
                                    Text("Expires \(expiry, style: .relative)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        } else {
            loadingOrError(service.openAIError)
        }

        if let error = service.openAIError, service.openAIUsage != nil {
            errorLabel(error)
        }
    }

    private func windowLabel(_ window: OpenAIUsageWindow?, fallback: String) -> String {
        guard let seconds = window?.limitWindowSeconds else { return fallback }
        let hours = Int(seconds / 3_600)
        if hours > 0, hours % 24 == 0 {
            return "\(hours / 24)-Day Window"
        }
        return "\(hours)-Hour Window"
    }
}

private struct CursorUsageView: View {
    @ObservedObject var service: ConnectedUsageService

    var body: some View {
        ProviderHeader(name: "Cursor", systemImage: "cursorarrow.rays")

        if !service.isCursorConfigured {
            configurePrompt("Add a Cursor session token in Settings.")
        } else if let usage = service.cursorUsage {
            UsageValueRow(
                label: "First-Party Models",
                percent: usage.planUsage?.autoPercentUsed,
                resetDate: usage.billingCycleEndDate
            )
            UsageValueRow(
                label: "API",
                percent: usage.planUsage?.apiPercentUsed,
                resetDate: usage.billingCycleEndDate
            )

            if let spend = usage.spendLimitUsage,
               let used = spend.spent,
               let limit = spend.individualLimit {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("On-Demand")
                            .font(.subheadline)
                        Spacer()
                        Text("\(UsageMoney.minorUnits(used)) / \(UsageMoney.minorUnits(limit))")
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                    ProgressView(value: (spend.utilization ?? 0) / 100, total: 1)
                        .tint(colorForPct((spend.utilization ?? 0) / 100))
                }
            }
        } else {
            loadingOrError(service.cursorError)
        }

        if let error = service.cursorError, service.cursorUsage != nil {
            errorLabel(error)
        }
    }
}

private struct UsageValueRow: View {
    let label: String
    let percent: Double?
    let resetDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(percent.map { "\(Int(round($0)))%" } ?? "—")
                    .font(.subheadline)
                    .monospacedDigit()
            }
            ProgressView(value: (percent ?? 0) / 100, total: 1)
                .tint(colorForPct((percent ?? 0) / 100))
            if let resetDate {
                Text("Resets \(resetDate, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func configurePrompt(_ text: String) -> some View {
    HStack {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        SettingsLink {
            Text("Configure")
        }
        .font(.caption)
        .buttonStyle(.borderless)
    }
}

@ViewBuilder
private func loadingOrError(_ error: String?) -> some View {
    if let error {
        errorLabel(error)
    } else {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Loading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private func errorLabel(_ error: String) -> some View {
    Label(error, systemImage: "exclamationmark.triangle")
        .font(.caption)
        .foregroundStyle(.red)
}

// MARK: - Setup (first launch)

private struct SetupView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var connectedService: ConnectedUsageService
    var onComplete: () -> Void

    var body: some View {
        Text("Welcome")
            .font(.headline)
        Text("Configure your preferences to get started.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        Divider()

        LaunchAtLoginToggle(controlSize: .small, useSwitchStyle: true)

        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SetupThresholdSlider(
                label: "5-hour window",
                value: notificationService.threshold5h,
                onChange: { notificationService.setThreshold5h($0) }
            )
            SetupThresholdSlider(
                label: "7-day window",
                value: notificationService.threshold7d,
                onChange: { notificationService.setThreshold7d($0) }
            )
            SetupThresholdSlider(
                label: "Extra usage",
                value: notificationService.thresholdExtra,
                onChange: { notificationService.setThresholdExtra($0) }
            )
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text("Polling Interval")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { service.pollingMinutes },
                set: {
                    service.updatePollingInterval($0)
                    connectedService.updatePollingInterval($0)
                }
            )) {
                ForEach(UsageService.pollingOptions, id: \.self) { mins in
                    Text(localizedPollingInterval(for: mins, locale: .autoupdatingCurrent))
                        .tag(mins)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isDiscouragedPollingOption(service.pollingMinutes) {
                Text("Frequent polling may cause rate limiting")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }

        Divider()

        Button("Get Started") {
            onComplete()
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)

        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Subviews

private struct CodeEntryView: View {
    @ObservedObject var service: UsageService
    @State private var code = ""

    var body: some View {
        Text("Paste the code from your browser:")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        HStack(spacing: 4) {
            TextField("code#state", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { submit() }
            Button {
                if let str = NSPasteboard.general.string(forType: .string) {
                    code = str.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
        }

        HStack {
            Button("Cancel") {
                service.isAwaitingCode = false
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Submit") { submit() }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty)
        }
    }

    private func submit() {
        let value = code
        Task { await service.submitOAuthCode(value) }
    }
}

private struct UsageBucketRow: View {
    let label: String
    let bucket: UsageBucket?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(percentageText)
                    .font(.subheadline)
                    .monospacedDigit()
            }
            ProgressView(value: (bucket?.utilization ?? 0) / 100.0, total: 1.0)
                .tint(colorForPct((bucket?.utilization ?? 0) / 100.0))
            if let resetDate = bucket?.resetsAtDate {
                Text("Resets \(resetDate, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var percentageText: String {
        guard let pct = bucket?.utilization else { return "—" }
        return "\(Int(round(pct)))%"
    }
}

private struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extra Usage")
                .font(.subheadline)
            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                HStack {
                    Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    if let pct = extra.utilization {
                        Text("\(Int(round(pct)))%")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                ProgressView(value: (extra.utilization ?? 0) / 100.0, total: 1.0)
                    .tint(.blue)
            }
        }
    }
}

private struct SetupThresholdSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text(value > 0 ? "\(value)%" : "Off")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: 0...100,
                step: 5
            )
            .controlSize(.small)
        }
    }
}

private func colorForPct(_ pct: Double) -> Color {
    switch pct {
    case ..<0.60: return .green
    case 0.60..<0.80: return .yellow
    default: return .red
    }
}
