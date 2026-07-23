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
                .task {
                    // Auto-mark existing users as setup-complete
                    if service.isAuthenticated && !UserDefaults.standard.bool(forKey: "setupComplete") {
                        UserDefaults.standard.set(true, forKey: "setupComplete")
                    }
                    historyService.loadHistory()
                    service.historyService = historyService
                    service.notificationService = notificationService

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
        if service.isAuthenticated {
            return renderIcon(pct5h: service.pct5h, pct7d: service.pct7d)
        }
        if connectedService.hasAnyConfiguredService {
            return renderIcon(
                pct5h: connectedService.iconPrimaryUtilization,
                pct7d: connectedService.iconSecondaryUtilization
            )
        }
        return renderUnauthenticatedIcon()
    }
}
