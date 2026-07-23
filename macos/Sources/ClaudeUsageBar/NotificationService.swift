import Foundation
@preconcurrency import UserNotifications

struct ThresholdAlert: Equatable {
    let provider: String
    let window: String
    let valueText: String
}

/// Pure logic: returns an alert when a percentage metric crosses its threshold.
func crossedPercentageThreshold(
    threshold: Int,
    previous: Double,
    current: Double,
    provider: String,
    window: String
) -> ThresholdAlert? {
    guard threshold > 0 else { return nil }
    let t = Double(threshold)
    guard current >= t, previous < t else { return nil }
    return ThresholdAlert(
        provider: provider,
        window: window,
        valueText: "\(Int(round(current)))%"
    )
}

/// Pure logic: returns an alert when a remaining-count metric drops to the threshold.
func crossedCountThreshold(
    threshold: Int,
    previous: Int,
    current: Int,
    provider: String,
    window: String
) -> ThresholdAlert? {
    guard threshold > 0 else { return nil }
    guard current <= threshold, previous > threshold else { return nil }
    let noun = current == 1 ? "credit" : "credits"
    return ThresholdAlert(
        provider: provider,
        window: window,
        valueText: "\(current) \(noun) remaining"
    )
}

private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
class NotificationService: ObservableObject {
    /// 0 = off, 5–100 = alert when window reaches this %.
    @Published private(set) var claudeSessionThreshold: Int
    @Published private(set) var claudeSevenDayThreshold: Int
    @Published private(set) var claudeFableThreshold: Int
    @Published private(set) var openAIWeeklyThreshold: Int
    /// 0 = off, 1–10 = alert when available reset credits drop to this count.
    @Published private(set) var openAIResetCreditsThreshold: Int
    @Published private(set) var cursorAPIThreshold: Int
    @Published private(set) var cursorAutoThreshold: Int
    @Published private(set) var cursorCreditThreshold: Int

    private var previousClaudeSession: Double?
    private var previousClaudeSevenDay: Double?
    private var previousClaudeFable: Double?
    private var previousOpenAIWeekly: Double?
    private var previousOpenAIResetCredits: Int?
    private var previousCursorAPI: Double?
    private var previousCursorAuto: Double?
    private var previousCursorCredit: Double?
    private let delegate = NotificationDelegate()

    init() {
        claudeSessionThreshold = Self.load(
            "notificationThresholdClaudeSession",
            legacyKeys: ["notificationThreshold5h"]
        )
        claudeSevenDayThreshold = Self.load(
            "notificationThresholdClaudeSevenDay",
            legacyKeys: ["notificationThreshold7d"]
        )
        claudeFableThreshold = Self.load("notificationThresholdClaudeFable")
        openAIWeeklyThreshold = Self.load("notificationThresholdOpenAIWeekly")
        openAIResetCreditsThreshold = Self.load("notificationThresholdOpenAIResetCredits")
        cursorAPIThreshold = Self.load("notificationThresholdCursorAPI")
        cursorAutoThreshold = Self.load("notificationThresholdCursorAuto")
        cursorCreditThreshold = Self.load("notificationThresholdCursorCredit")
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = delegate
        }
    }

    func setClaudeSessionThreshold(_ value: Int) {
        claudeSessionThreshold = clampPercent(value)
        persist(claudeSessionThreshold, key: "notificationThresholdClaudeSession")
        previousClaudeSession = nil
        if claudeSessionThreshold > 0 { requestPermission() }
    }

    func setClaudeSevenDayThreshold(_ value: Int) {
        claudeSevenDayThreshold = clampPercent(value)
        persist(claudeSevenDayThreshold, key: "notificationThresholdClaudeSevenDay")
        previousClaudeSevenDay = nil
        if claudeSevenDayThreshold > 0 { requestPermission() }
    }

    func setClaudeFableThreshold(_ value: Int) {
        claudeFableThreshold = clampPercent(value)
        persist(claudeFableThreshold, key: "notificationThresholdClaudeFable")
        previousClaudeFable = nil
        if claudeFableThreshold > 0 { requestPermission() }
    }

    func setOpenAIWeeklyThreshold(_ value: Int) {
        openAIWeeklyThreshold = clampPercent(value)
        persist(openAIWeeklyThreshold, key: "notificationThresholdOpenAIWeekly")
        previousOpenAIWeekly = nil
        if openAIWeeklyThreshold > 0 { requestPermission() }
    }

    func setOpenAIResetCreditsThreshold(_ value: Int) {
        openAIResetCreditsThreshold = clampCount(value)
        persist(openAIResetCreditsThreshold, key: "notificationThresholdOpenAIResetCredits")
        previousOpenAIResetCredits = nil
        if openAIResetCreditsThreshold > 0 { requestPermission() }
    }

    func setCursorAPIThreshold(_ value: Int) {
        cursorAPIThreshold = clampPercent(value)
        persist(cursorAPIThreshold, key: "notificationThresholdCursorAPI")
        previousCursorAPI = nil
        if cursorAPIThreshold > 0 { requestPermission() }
    }

    func setCursorAutoThreshold(_ value: Int) {
        cursorAutoThreshold = clampPercent(value)
        persist(cursorAutoThreshold, key: "notificationThresholdCursorAuto")
        previousCursorAuto = nil
        if cursorAutoThreshold > 0 { requestPermission() }
    }

    func setCursorCreditThreshold(_ value: Int) {
        cursorCreditThreshold = clampPercent(value)
        persist(cursorCreditThreshold, key: "notificationThresholdCursorCredit")
        previousCursorCredit = nil
        if cursorCreditThreshold > 0 { requestPermission() }
    }

    func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkClaude(sessionPercent: Double, sevenDayPercent: Double, fablePercent: Double?) {
        let session = sessionPercent
        let sevenDay = sevenDayPercent
        let fable = fablePercent ?? 0

        let prevSession = previousClaudeSession ?? 0
        let prevSevenDay = previousClaudeSevenDay ?? 0
        let prevFable = previousClaudeFable ?? 0

        defer {
            previousClaudeSession = session
            previousClaudeSevenDay = sevenDay
            if fablePercent != nil {
                previousClaudeFable = fable
            }
        }

        var alerts = [ThresholdAlert]()
        if let alert = crossedPercentageThreshold(
            threshold: claudeSessionThreshold,
            previous: prevSession,
            current: session,
            provider: "Claude",
            window: "Session"
        ) {
            alerts.append(alert)
        }
        if let alert = crossedPercentageThreshold(
            threshold: claudeSevenDayThreshold,
            previous: prevSevenDay,
            current: sevenDay,
            provider: "Claude",
            window: "Seven-day"
        ) {
            alerts.append(alert)
        }
        if fablePercent != nil, let alert = crossedPercentageThreshold(
            threshold: claudeFableThreshold,
            previous: prevFable,
            current: fable,
            provider: "Claude",
            window: "Fable"
        ) {
            alerts.append(alert)
        }

        for alert in alerts {
            sendNotification(alert)
        }
    }

    func checkOpenAI(weeklyPercent: Double?, resetCreditsRemaining: Int?) {
        var alerts = [ThresholdAlert]()

        if let weeklyPercent {
            let previous = previousOpenAIWeekly ?? 0
            defer { previousOpenAIWeekly = weeklyPercent }
            if let alert = crossedPercentageThreshold(
                threshold: openAIWeeklyThreshold,
                previous: previous,
                current: weeklyPercent,
                provider: "Codex",
                window: "Weekly usage"
            ) {
                alerts.append(alert)
            }
        }

        if let resetCreditsRemaining {
            let previous = previousOpenAIResetCredits ?? (openAIResetCreditsThreshold + 1)
            defer { previousOpenAIResetCredits = resetCreditsRemaining }
            if let alert = crossedCountThreshold(
                threshold: openAIResetCreditsThreshold,
                previous: previous,
                current: resetCreditsRemaining,
                provider: "Codex",
                window: "Reset credits"
            ) {
                alerts.append(alert)
            }
        }

        for alert in alerts {
            sendNotification(alert)
        }
    }

    func checkCursor(apiPercent: Double?, autoPercent: Double?, creditPercent: Double?) {
        var alerts = [ThresholdAlert]()

        if let apiPercent {
            let previous = previousCursorAPI ?? 0
            defer { previousCursorAPI = apiPercent }
            if let alert = crossedPercentageThreshold(
                threshold: cursorAPIThreshold,
                previous: previous,
                current: apiPercent,
                provider: "Cursor",
                window: "API"
            ) {
                alerts.append(alert)
            }
        }

        if let autoPercent {
            let previous = previousCursorAuto ?? 0
            defer { previousCursorAuto = autoPercent }
            if let alert = crossedPercentageThreshold(
                threshold: cursorAutoThreshold,
                previous: previous,
                current: autoPercent,
                provider: "Cursor",
                window: "Auto"
            ) {
                alerts.append(alert)
            }
        }

        if let creditPercent {
            let previous = previousCursorCredit ?? 0
            defer { previousCursorCredit = creditPercent }
            if let alert = crossedPercentageThreshold(
                threshold: cursorCreditThreshold,
                previous: previous,
                current: creditPercent,
                provider: "Cursor",
                window: "Credit"
            ) {
                alerts.append(alert)
            }
        }

        for alert in alerts {
            sendNotification(alert)
        }
    }

    private func sendNotification(_ alert: ThresholdAlert) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[Notification] \(alert.provider) \(alert.window): \(alert.valueText) (no bundle – skipped)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(alert.provider) Usage"
        if alert.valueText.hasSuffix("%") {
            content.body = "\(alert.window) usage has reached \(alert.valueText)"
        } else {
            content.body = "\(alert.window): \(alert.valueText)"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage-\(alert.provider)-\(alert.window)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] Failed to deliver: \(error)")
            } else {
                print("[Notification] Delivered: \(alert.provider) \(alert.window) \(alert.valueText)")
            }
        }
    }

    private func persist(_ value: Int, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func clampPercent(_ value: Int) -> Int {
        max(0, min(100, value))
    }

    private func clampCount(_ value: Int) -> Int {
        max(0, min(10, value))
    }

    private static func load(_ key: String, legacyKeys: [String] = []) -> Int {
        if UserDefaults.standard.object(forKey: key) != nil {
            return max(0, min(100, UserDefaults.standard.integer(forKey: key)))
        }
        for legacy in legacyKeys {
            if UserDefaults.standard.object(forKey: legacy) != nil {
                return max(0, min(100, UserDefaults.standard.integer(forKey: legacy)))
            }
        }
        return 0
    }
}
