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
        XCTAssertEqual(snapshot.version, 3)
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

    func testInactiveClaudeSessionClearsResetBeforeWidgetSnapshot() {
        let previous = UsageResponse(
            fiveHour: UsageBucket(
                utilization: 28,
                resetsAt: "2026-03-05T18:00:00Z"
            ),
            sevenDay: nil,
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        let current = UsageResponse(
            fiveHour: UsageBucket(utilization: 0, resetsAt: nil),
            sevenDay: nil,
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )

        let reconciled = current.reconciled(
            with: previous,
            now: Date(timeIntervalSince1970: 1_772_731_000)
        )
        let metrics = UsageSnapshotStore.claudeMetrics(for: reconciled)

        XCTAssertEqual(metrics.first?.id, "five_hour")
        XCTAssertEqual(metrics.first?.percentUsed, 0)
        XCTAssertNil(metrics.first?.resetsAt)
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

    func testReloadKindsMatchEveryWidgetConfiguration() {
        XCTAssertEqual(UsageSnapshotStore.widgetKinds, [
            "com.local.AgentUsageBar.Widget.ProviderDetails",
            "com.local.AgentUsageBar.Widget.ProviderSnapshot",
            "com.local.AgentUsageBar.Widget.ProviderGrid",
            "com.local.AgentUsageBar.Widget.Overview",
        ])
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

    func testV3FieldsRoundTripAndCurrentSnapshotMatchesMemory() throws {
        let now = Date(timeIntervalSince1970: 1_757_521_026)
        let store = UsageSnapshotStore(directory: directory, now: { now })
        let plan = UsageSnapshotPlan(label: "plus")
        let credits = UsageSnapshotCredits(
            available: 1,
            items: [
                UsageSnapshotCreditItem(
                    id: "crd_1",
                    expiresAt: Date(timeIntervalSince1970: 1_758_384_000)
                )
            ]
        )

        store.update(
            provider: "openai",
            metrics: [
                UsageSnapshotMetric(id: "primary", label: "7-day window", percentUsed: 43, resetsAt: nil)
            ],
            plan: plan,
            credits: credits
        )

        let fromDisk = try readSnapshot(store)
        XCTAssertEqual(fromDisk.version, 3)
        XCTAssertEqual(fromDisk.providers["openai"]?.plan, plan)
        XCTAssertEqual(fromDisk.providers["openai"]?.credits, credits)
        XCTAssertNil(fromDisk.providers["openai"]?.error)
        XCTAssertEqual(store.currentSnapshot(), fromDisk)
    }

    func testV2DocumentDecodesWithNilPlanCreditsAndError() throws {
        let json = """
        {
          "version": 2,
          "generatedAt": "2026-09-10T16:53:46Z",
          "providers": {
            "claude": {
              "updatedAt": "2026-09-10T16:53:44Z",
              "metrics": [
                {"id": "five_hour", "label": "5-hour window", "percentUsed": 28}
              ]
            }
          }
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(
            to: directory.appendingPathComponent("usage-snapshot.json")
        )

        let decoded = try UsageSnapshotStore.makeDecoder().decode(
            UsageSnapshot.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.version, 2)
        XCTAssertNil(decoded.providers["claude"]?.plan)
        XCTAssertNil(decoded.providers["claude"]?.credits)
        XCTAssertNil(decoded.providers["claude"]?.error)

        let store = UsageSnapshotStore(directory: directory)
        XCTAssertEqual(store.currentSnapshot().providers["claude"]?.metrics.first?.percentUsed, 28)
        XCTAssertNil(store.currentSnapshot().providers["claude"]?.plan)
        XCTAssertEqual(store.currentSnapshot().version, 3)
    }

    func testFailedUpdateKeepsLastGoodMetricsAndUpdatedAt() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let store = UsageSnapshotStore(directory: directory, now: { now })
        store.update(
            provider: "openai",
            metrics: [
                UsageSnapshotMetric(id: "primary", label: "7-day window", percentUsed: 70, resetsAt: nil)
            ],
            plan: UsageSnapshotPlan(label: "plus")
        )
        let updatedAt = try XCTUnwrap(store.currentSnapshot().providers["openai"]?.updatedAt)

        now = Date(timeIntervalSince1970: 2_000)
        store.update(provider: "openai", error: "OpenAI session expired — update it in Settings")

        let snapshot = store.currentSnapshot()
        XCTAssertEqual(snapshot.providers["openai"]?.metrics.first?.percentUsed, 70)
        XCTAssertEqual(snapshot.providers["openai"]?.plan?.label, "plus")
        XCTAssertEqual(
            snapshot.providers["openai"]?.error,
            "OpenAI session expired — update it in Settings"
        )
        XCTAssertEqual(snapshot.providers["openai"]?.updatedAt, updatedAt)
        XCTAssertEqual(snapshot.generatedAt, now)
    }

    func testEmptyCurrentSnapshotBeforeAnyWrite() {
        let now = Date(timeIntervalSince1970: 1_757_521_026)
        let store = UsageSnapshotStore(directory: directory, now: { now })
        let snapshot = store.currentSnapshot()

        XCTAssertEqual(snapshot.version, 3)
        XCTAssertEqual(snapshot.generatedAt, now)
        XCTAssertEqual(snapshot.providers, [:])
        XCTAssertNil(snapshot.preferences)
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
