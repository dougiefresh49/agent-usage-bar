import XCTest
@testable import AgentUsageBar

@MainActor
final class UsageSnapshotStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var defaultsSuite: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageSnapshotStoreTests-\(UUID().uuidString)")
        defaultsSuite = "UsageSnapshotStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: defaultsSuite)
        super.tearDown()
    }

    private func readSnapshot(_ store: UsageSnapshotStore) throws -> UsageSnapshot {
        let data = try Data(contentsOf: store.fileURL)
        return try UsageSnapshotStore.makeDecoder().decode(UsageSnapshot.self, from: data)
    }

    func testUpdateWritesProviderMetricsToDisk() throws {
        let now = Date(timeIntervalSince1970: 1_753_000_000)
        let store = UsageSnapshotStore(directory: directory, now: { now })

        store.update(provider: "claude", metrics: [
            UsageSnapshotMetric(id: "five_hour", label: "5-hour window", percentUsed: 28, resetsAt: nil)
        ])

        let snapshot = try readSnapshot(store)
        XCTAssertEqual(snapshot.version, 2)
        XCTAssertEqual(snapshot.providers.count, 1)
        XCTAssertEqual(snapshot.providers["claude"]?.metrics.first?.percentUsed, 28)
    }

    func testUpdatesMergeAcrossProvidersAndRemoveDeletes() throws {
        let store = UsageSnapshotStore(directory: directory)

        store.update(provider: "claude", metrics: [
            UsageSnapshotMetric(id: "five_hour", label: "5-hour window", percentUsed: 28, resetsAt: nil)
        ])
        store.update(provider: "openai", metrics: [
            UsageSnapshotMetric(id: "primary", label: "7-day window", percentUsed: 70, resetsAt: nil)
        ])

        var snapshot = try readSnapshot(store)
        XCTAssertEqual(Set(snapshot.providers.keys), ["claude", "openai"])

        store.remove(provider: "openai")
        snapshot = try readSnapshot(store)
        XCTAssertEqual(Set(snapshot.providers.keys), ["claude"])
    }

    func testNewStoreLoadsExistingSnapshotFromDisk() throws {
        let first = UsageSnapshotStore(directory: directory)
        first.update(provider: "cursor", metrics: [
            UsageSnapshotMetric(id: "models", label: "First-party models", percentUsed: 10, resetsAt: nil)
        ])

        let second = UsageSnapshotStore(directory: directory)
        second.update(provider: "claude", metrics: [
            UsageSnapshotMetric(id: "five_hour", label: "5-hour window", percentUsed: 28, resetsAt: nil)
        ])

        let snapshot = try readSnapshot(second)
        XCTAssertEqual(Set(snapshot.providers.keys), ["claude", "cursor"])
    }

    func testClaudeMetricsSkipAbsentOptionalBuckets() {
        let usage = UsageResponse(
            fiveHour: UsageBucket(utilization: 28, resetsAt: nil),
            sevenDay: UsageBucket(utilization: 21, resetsAt: nil),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )

        let metrics = UsageSnapshotStore.claudeMetrics(for: usage)
        XCTAssertEqual(metrics.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(metrics.first?.percentUsed, 28)
    }

    func testMirrorsSnapshotAndAppearancePreferencesForWidget() throws {
        let widgetDirectory = directory.appendingPathComponent("Widget")
        defaults.set("elevenLabs", forKey: UsagePresentationDefaults.menuBarProviderKey)
        defaults.set("orbit", forKey: UsagePresentationDefaults.detailStyleKey)
        var reloadCount = 0
        let store = UsageSnapshotStore(
            directory: directory,
            widgetDirectory: widgetDirectory,
            defaults: defaults,
            reloadWidgets: { reloadCount += 1 }
        )

        store.update(provider: "elevenlabs", metrics: [
            UsageSnapshotMetric(
                id: "remaining",
                label: "Credits remaining",
                percentUsed: nil,
                count: 159_602,
                resetsAt: nil
            )
        ])

        let widgetData = try Data(
            contentsOf: widgetDirectory.appendingPathComponent("usage-snapshot.json")
        )
        let snapshot = try UsageSnapshotStore.makeDecoder().decode(
            UsageSnapshot.self,
            from: widgetData
        )
        XCTAssertEqual(snapshot.preferences?.preferredProvider, "elevenLabs")
        XCTAssertEqual(snapshot.preferences?.detailStyle, "orbit")
        XCTAssertEqual(snapshot.providers["elevenlabs"]?.metrics.first?.count, 159_602)
        XCTAssertEqual(reloadCount, 1)
    }

    func testOpenAIMetricsIncludeResetCreditCount() {
        let usage = OpenAIUsageResponse(
            email: nil,
            planType: nil,
            rateLimit: nil,
            codeReviewRateLimit: nil,
            additionalRateLimits: nil,
            credits: nil,
            spendControl: nil,
            rateLimitResetCredits: OpenAIResetCreditSummary(
                availableCount: 2,
                applicableAvailableCount: 1
            )
        )

        let metrics = UsageSnapshotStore.openAIMetrics(for: usage)

        XCTAssertEqual(metrics.first(where: { $0.id == "reset_credits" })?.count, 1)
    }
}

@MainActor
final class RefreshRequestListenerTests: XCTestCase {
    func testThrottlesRequestsWithinMinimumInterval() {
        var now = Date(timeIntervalSince1970: 1_753_000_000)
        var refreshCount = 0
        let listener = RefreshRequestListener(now: { now }) { refreshCount += 1 }

        XCTAssertTrue(listener.handleRequest())
        XCTAssertFalse(listener.handleRequest())
        XCTAssertEqual(refreshCount, 1)

        now = now.addingTimeInterval(RefreshRequestListener.minimumInterval - 1)
        XCTAssertFalse(listener.handleRequest())
        XCTAssertEqual(refreshCount, 1)

        now = now.addingTimeInterval(2)
        XCTAssertTrue(listener.handleRequest())
        XCTAssertEqual(refreshCount, 2)
    }
}
