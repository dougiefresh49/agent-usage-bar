import Foundation
import notify

/// Listens for Darwin notifications posted by external tools (e.g. the ai-usage
/// agent skill runs `notifyutil -p com.agentusagebar.refresh`) and triggers an
/// on-demand usage refresh, throttled so scripted callers can't hammer the
/// provider APIs.
@MainActor
final class RefreshRequestListener {
    static let notificationName = "com.agentusagebar.refresh"
    static let minimumInterval: TimeInterval = 120

    private var token: Int32 = 0
    private var isRegistered = false
    private var lastHonored: Date?
    private let onRefresh: () -> Void
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init, onRefresh: @escaping () -> Void) {
        self.now = now
        self.onRefresh = onRefresh
    }

    func start() {
        guard !isRegistered else { return }
        let status = notify_register_dispatch(
            Self.notificationName,
            &token,
            DispatchQueue.main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.handleRequest()
            }
        }
        isRegistered = status == NOTIFY_STATUS_OK
    }

    /// Returns true when the request was honored (not throttled).
    @discardableResult
    func handleRequest() -> Bool {
        let current = now()
        if let lastHonored, current.timeIntervalSince(lastHonored) < Self.minimumInterval {
            return false
        }
        lastHonored = current
        onRefresh()
        return true
    }

    deinit {
        if isRegistered {
            notify_cancel(token)
        }
    }
}
