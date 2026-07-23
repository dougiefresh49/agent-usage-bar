import SwiftUI

@main
struct AgentUsageBarApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var historyService = UsageHistoryService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var appUpdater = AppUpdater()
    @StateObject private var connectedService = ConnectedUsageService()
    @State private var snapshotStore: UsageSnapshotStore?
    @State private var refreshListener: RefreshRequestListener?
    @AppStorage(UsagePresentationDefaults.menuBarProviderKey)
    private var menuBarProviderRaw = UsagePresentationDefaults.menuBarProvider.rawValue
    @AppStorage(UsagePresentationDefaults.menuBarStyleKey)
    private var menuBarStyleRaw = UsagePresentationDefaults.menuBarStyle.rawValue
    @AppStorage(UsagePresentationDefaults.menuBarPrimaryMetricKey)
    private var menuBarPrimaryMetricID = UsagePresentationMetrics.claudeFiveHourID
    @AppStorage(UsagePresentationDefaults.menuBarSecondaryMetricKey)
    private var menuBarSecondaryMetricID = UsagePresentationMetrics.claudeSevenDayID

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                service: service,
                historyService: historyService,
                notificationService: notificationService,
                appUpdater: appUpdater,
                connectedService: connectedService
            )
        } label: {
            Image(nsImage: menuBarIcon)
                .accessibilityLabel(menuBarAccessibilityLabel)
                .task {
                    // Auto-mark existing users as setup-complete
                    if service.isAuthenticated && !UserDefaults.standard.bool(forKey: "setupComplete") {
                        UserDefaults.standard.set(true, forKey: "setupComplete")
                    }
                    historyService.loadHistory()
                    service.historyService = historyService
                    service.notificationService = notificationService
                    connectedService.notificationService = notificationService

                    let store = snapshotStore ?? UsageSnapshotStore()
                    snapshotStore = store
                    service.snapshotStore = store
                    connectedService.snapshotStore = store

                    if refreshListener == nil {
                        let listener = RefreshRequestListener { [weak service, weak connectedService] in
                            Task { @MainActor in
                                if let service, service.isAuthenticated {
                                    await service.fetchUsage()
                                }
                                await connectedService?.fetchAll()
                            }
                        }
                        listener.start()
                        refreshListener = listener
                    }

                    service.startPolling()
                    connectedService.startPolling()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowContent(
                service: service,
                notificationService: notificationService,
                connectedService: connectedService
            )
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }

    private var menuBarIcon: NSImage {
        renderMenuBarIcon(
            provider: menuBarProvider,
            metrics: menuBarMetrics,
            style: menuBarStyle,
            isConfigured: isMenuBarProviderConfigured
        )
    }

    private var menuBarProvider: UsageProvider {
        UsageProvider(rawValue: menuBarProviderRaw)
            ?? UsagePresentationDefaults.menuBarProvider
    }

    private var menuBarStyle: MenuBarVisualizationStyle {
        MenuBarVisualizationStyle(rawValue: menuBarStyleRaw)
            ?? UsagePresentationDefaults.menuBarStyle
    }

    private var menuBarMetrics: [UsagePresentationMetric] {
        let available = UsagePresentationMetrics.metrics(
            for: menuBarProvider,
            claude: service,
            connectedService: connectedService
        )
        return UsagePresentationMetrics.resolvedPair(
            provider: menuBarProvider,
            primaryID: menuBarPrimaryMetricID,
            secondaryID: menuBarSecondaryMetricID,
            available: available
        )
    }

    private var isMenuBarProviderConfigured: Bool {
        switch menuBarProvider {
        case .claude: return service.isAuthenticated
        case .openAI: return connectedService.isOpenAIConfigured
        case .cursor: return connectedService.isCursorConfigured
        case .elevenLabs: return connectedService.isElevenLabsConfigured
        }
    }

    private var menuBarAccessibilityLabel: String {
        let values = menuBarMetrics
            .map { "\($0.label) \($0.accessibilityValue)" }
            .joined(separator: ", ")
        return values.isEmpty
            ? "\(menuBarProvider.settingsName) usage unavailable"
            : "\(menuBarProvider.settingsName), \(values)"
    }
}
