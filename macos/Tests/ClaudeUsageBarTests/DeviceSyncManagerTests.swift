import CryptoKit
import XCTest
@testable import AgentUsageBar

@MainActor
final class DeviceSyncManagerTests: XCTestCase {
    func testHostSelectionPrefersTailnetAndKeepsLANAsAlt() {
        let hosts = DeviceSyncHostSelection.selectPairingHosts(
            from: [
                DeviceSyncNetworkInterface(name: "en0", address: "192.168.1.20"),
                DeviceSyncNetworkInterface(name: "utun4", address: "100.64.1.5")
            ]
        )

        XCTAssertEqual(hosts?.host, "100.64.1.5")
        XCTAssertEqual(hosts?.alt, "192.168.1.20")
    }

    func testHostSelectionFallsBackToLANWithoutAlt() {
        let hosts = DeviceSyncHostSelection.selectPairingHosts(
            from: [
                DeviceSyncNetworkInterface(name: "en0", address: "10.0.0.8"),
                DeviceSyncNetworkInterface(name: "lo0", address: "127.0.0.1")
            ]
        )

        XCTAssertEqual(hosts?.host, "10.0.0.8")
        XCTAssertNil(hosts?.alt)
    }

    func testSnapshotRouteSealsInMemoryDocumentAndUpdatesLastSeen() async throws {
        let fixture = try Self.sampleSnapshot()
        let harness = try makeHarness(snapshot: fixture)
        defer { harness.cleanup() }

        let response = await harness.manager.handle(
            try harness.request(method: "GET", path: "/v2/snapshot", prefix: "snapshot")
        )
        XCTAssertEqual(response.status, 200)
        let envelope = try JSONDecoder().decode(DeviceEncryptedEnvelope.self, from: response.body)
        let decrypted = try DeviceSyncCrypto.open(
            envelope,
            as: UsageSnapshot.self,
            sharedSecret: harness.secret,
            salt: harness.identity.desktopID,
            info: DeviceSyncCrypto.snapshotInfo
        )
        XCTAssertEqual(decrypted, fixture)
        XCTAssertNotNil(harness.manager.devices.first?.lastSeenAt)

        let json = try XCTUnwrap(String(data: try JSONEncoder.deviceSyncEncoder.encode(decrypted), encoding: .utf8))
        XCTAssertTrue(json.contains("\"version\":3"))
        XCTAssertTrue(json.contains("\"label\":\"plus\""))
        XCTAssertEqual(json, Self.sampleSnapshotJSON)
    }

    func testSnapshotRouteReturnsEmptyDocumentBeforeAnyFetch() async throws {
        let empty = UsageSnapshot(
            generatedAt: Self.sampleGeneratedAt,
            providers: [:]
        )
        let harness = try makeHarness(snapshot: empty)
        defer { harness.cleanup() }

        let response = await harness.manager.handle(
            try harness.request(method: "GET", path: "/v2/snapshot", prefix: "snapshot")
        )
        let envelope = try JSONDecoder().decode(DeviceEncryptedEnvelope.self, from: response.body)
        let decrypted = try DeviceSyncCrypto.open(
            envelope,
            as: UsageSnapshot.self,
            sharedSecret: harness.secret,
            salt: harness.identity.desktopID,
            info: DeviceSyncCrypto.snapshotInfo
        )
        XCTAssertEqual(decrypted.version, 3)
        XCTAssertEqual(decrypted.providers, [:])
        XCTAssertNil(decrypted.preferences)
    }

    func testSnapshotAuthFailuresMatchStatus() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        let unknown = await harness.manager.handle(
            LocalHTTPRequest(
                method: "GET",
                path: "/v2/snapshot",
                queryItems: [
                    "desktop": harness.identity.desktopID,
                    "device": "missing",
                    "ts": String(Int64(Date().timeIntervalSince1970)),
                    "proof": "nope"
                ],
                body: Data()
            )
        )
        XCTAssertEqual(unknown.status, 404)
        XCTAssertEqual(Self.errorMessage(unknown), "Unknown device.")

        let stale = await harness.manager.handle(
            try harness.request(
                method: "GET",
                path: "/v2/snapshot",
                prefix: "snapshot",
                timestamp: Int64(Date().timeIntervalSince1970) - 120
            )
        )
        XCTAssertEqual(stale.status, 404)
        XCTAssertEqual(Self.errorMessage(stale), "Unknown device.")

        let badProof = await harness.manager.handle(
            try harness.request(method: "GET", path: "/v2/snapshot", prefix: "status")
        )
        XCTAssertEqual(badProof.status, 404)
        XCTAssertEqual(Self.errorMessage(badProof), "Device proof is invalid.")
    }

    func testSnapshotAndRedeemRejectRevokedDevice() async throws {
        let harness = try makeHarness(revoked: true)
        defer { harness.cleanup() }

        let snapshot = await harness.manager.handle(
            try harness.request(method: "GET", path: "/v2/snapshot", prefix: "snapshot")
        )
        XCTAssertEqual(snapshot.status, 404)
        XCTAssertEqual(Self.errorMessage(snapshot), "Device removed.")

        let redeem = await harness.manager.handle(
            try harness.redeemRequest(creditID: "crd_1")
        )
        XCTAssertEqual(redeem.status, 404)
        XCTAssertEqual(Self.errorMessage(redeem), "Device removed.")
    }

    func testRedeemRouteSealsOutcomeAndCallsRedeemer() async throws {
        var redeemed: [String] = []
        let harness = try makeHarness(redeemed: { id in
            redeemed.append(id)
            return .success(.reset)
        })
        defer { harness.cleanup() }

        let response = await harness.manager.handle(
            try harness.redeemRequest(creditID: "crd_soon")
        )
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(redeemed, ["crd_soon"])
        let envelope = try JSONDecoder().decode(DeviceEncryptedEnvelope.self, from: response.body)
        let result = try DeviceSyncCrypto.open(
            envelope,
            as: DeviceRedeemResult.self,
            sharedSecret: harness.secret,
            salt: harness.identity.desktopID,
            info: DeviceSyncCrypto.redeemInfo
        )
        XCTAssertEqual(result.outcome, "reset")
        XCTAssertEqual(result.message, "Limits reset")
        XCTAssertNil(result.error)
        XCTAssertNotNil(harness.manager.devices.first?.lastSeenAt)
    }

    func testRedeemRejectsBodyThatDoesNotOpen() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        let response = await harness.manager.handle(
            try harness.request(
                method: "POST",
                path: "/v2/redeem",
                prefix: "redeem",
                body: Data(#"{"nonce":"x","ciphertext":"y","tag":"z"}"#.utf8)
            )
        )
        XCTAssertEqual(response.status, 400)
        XCTAssertEqual(Self.errorMessage(response), "Could not decrypt the redeem request.")
        XCTAssertNil(harness.manager.devices.first?.lastSeenAt)
    }

    private struct Harness {
        let directory: URL
        let identity: DeviceSyncStore.Identity
        let secret: SharedSecret
        let deviceID: String
        let manager: DeviceSyncManager

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }

        func request(
            method: String,
            path: String,
            prefix: String,
            timestamp: Int64 = Int64(Date().timeIntervalSince1970),
            body: Data = Data()
        ) throws -> LocalHTTPRequest {
            let proof = DeviceSyncCrypto.authenticationProof(
                sharedSecret: secret,
                salt: identity.desktopID,
                info: DeviceSyncCrypto.statusInfo,
                message: "\(prefix):\(identity.desktopID):\(deviceID):\(timestamp)"
            )
            return LocalHTTPRequest(
                method: method,
                path: path,
                queryItems: [
                    "desktop": identity.desktopID,
                    "device": deviceID,
                    "ts": String(timestamp),
                    "proof": proof
                ],
                body: body
            )
        }

        func redeemRequest(creditID: String) throws -> LocalHTTPRequest {
            let timestamp = Int64(Date().timeIntervalSince1970)
            let envelope = try DeviceSyncCrypto.seal(
                DeviceRedeemRequest(creditId: creditID, requestedAtEpochSeconds: timestamp),
                sharedSecret: secret,
                salt: identity.desktopID,
                info: DeviceSyncCrypto.redeemInfo
            )
            return try request(
                method: "POST",
                path: "/v2/redeem",
                prefix: "redeem",
                timestamp: timestamp,
                body: try JSONEncoder.deviceSyncEncoder.encode(envelope)
            )
        }
    }

    private func makeHarness(
        snapshot: UsageSnapshot = UsageSnapshot(generatedAt: Date(), providers: [:]),
        redeemed: @escaping (String) async -> DeviceRedeemResult = { _ in
            .failure("The Mac has no OpenAI login.")
        },
        revoked: Bool = false
    ) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = DeviceSyncStore(directoryURL: directory)
        let identity = store.loadOrCreateIdentity()
        let deviceKey = P256.KeyAgreement.PrivateKey()
        let deviceID = "phone-1"
        try store.saveDevices([
            PairedDevice(
                id: deviceID,
                name: "Pixel",
                publicKey: deviceKey.publicKey.x963Representation.base64URLEncodedString(),
                pairedAt: Date(timeIntervalSince1970: 1_750_000_000),
                lastSeenAt: nil,
                revokedAt: revoked ? Date(timeIntervalSince1970: 1_750_000_100) : nil,
                wipeAcknowledgedAt: nil
            )
        ])
        let secret = try DeviceSyncCrypto.sharedSecret(
            desktopPrivateKey: identity.privateKey,
            devicePublicKey: deviceKey.publicKey.x963Representation
        )
        let manager = DeviceSyncManager(
            store: store,
            listNetworkInterfaces: { [] },
            snapshotProvider: { snapshot },
            redeemer: redeemed
        )
        return Harness(
            directory: directory,
            identity: identity,
            secret: secret,
            deviceID: deviceID,
            manager: manager
        )
    }

    private static func errorMessage(_ response: LocalHTTPResponse) -> String? {
        let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: String]
        return object?["error"]
    }

    private static let sampleGeneratedAt = ISO8601DateFormatter.deviceSync.date(
        from: "2026-09-10T16:53:46Z"
    )!

    private static func sampleSnapshot() throws -> UsageSnapshot {
        UsageSnapshot(
            generatedAt: sampleGeneratedAt,
            providers: [
                "openai": UsageSnapshotProvider(
                    updatedAt: ISO8601DateFormatter.deviceSync.date(
                        from: "2026-09-10T16:53:44Z"
                    )!,
                    metrics: [
                        UsageSnapshotMetric(
                            id: "primary",
                            label: "7-day window",
                            percentUsed: 43,
                            resetsAt: nil
                        )
                    ],
                    plan: UsageSnapshotPlan(label: "plus"),
                    credits: UsageSnapshotCredits(
                        available: 2,
                        items: [
                            UsageSnapshotCreditItem(
                                id: "crd_1",
                                expiresAt: ISO8601DateFormatter.deviceSync.date(
                                    from: "2026-09-20T00:00:00Z"
                                )!
                            )
                        ]
                    )
                )
            ]
        )
    }

    /// Compact sorted-keys JSON produced by `JSONEncoder.deviceSyncEncoder` for `sampleSnapshot()`.
    static let sampleSnapshotJSON = #"{"generatedAt":"2026-09-10T16:53:46Z","providers":{"openai":{"credits":{"available":2,"items":[{"expiresAt":"2026-09-20T00:00:00Z","id":"crd_1"}]},"metrics":[{"id":"primary","label":"7-day window","percentUsed":43}],"plan":{"label":"plus"},"updatedAt":"2026-09-10T16:53:44Z"}},"version":3}"#
}

private extension ISO8601DateFormatter {
    static let deviceSync: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
