import CryptoKit
import XCTest
@testable import AgentUsageBar

@MainActor
final class DeviceSyncManagerTests: XCTestCase {
    func testFingerprintChangeQueuesOneSyncPerTrustedDevice() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "DeviceSyncManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = DeviceSyncStore(directoryURL: directory)
        let trusted = PairedDevice(
            id: "phone-1",
            name: "Pixel",
            publicKey: P256.KeyAgreement.PrivateKey()
                .publicKey.x963Representation.base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_750_000_000),
            lastSeenAt: nil,
            revokedAt: nil,
            wipeAcknowledgedAt: nil
        )
        let revoked = PairedDevice(
            id: "phone-2",
            name: "Old",
            publicKey: P256.KeyAgreement.PrivateKey()
                .publicKey.x963Representation.base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_750_000_100),
            lastSeenAt: nil,
            revokedAt: Date(timeIntervalSince1970: 1_750_000_200),
            wipeAcknowledgedAt: nil
        )
        try? store.saveDevices([trusted, revoked])

        let manager = DeviceSyncManager(
            store: store,
            defaults: defaults,
            makeRotationPayload: {
                DeviceSyncPayload(
                    connections: DeviceSyncConnections(
                        codexAccessToken: "codex-access",
                        codexAccountId: "acct",
                        cursorAccessToken: "cursor-access"
                    )
                )
            },
            listNetworkInterfaces: { [] }
        )

        manager.noteCredentialFingerprint("fingerprint-a")

        let afterFirst = manager.devices
        XCTAssertNotNil(afterFirst.first { $0.id == "phone-1" }?.pendingSync)
        XCTAssertNil(afterFirst.first { $0.id == "phone-2" }?.pendingSync)
        XCTAssertEqual(
            defaults.string(forKey: DeviceSyncManager.credentialFingerprintDefaultsKey),
            "fingerprint-a"
        )
    }

    func testUnchangedFingerprintQueuesNoSync() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "DeviceSyncManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = DeviceSyncStore(directoryURL: directory)
        let trusted = PairedDevice(
            id: "phone-1",
            name: "Pixel",
            publicKey: P256.KeyAgreement.PrivateKey()
                .publicKey.x963Representation.base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_750_000_000),
            lastSeenAt: nil,
            revokedAt: nil,
            wipeAcknowledgedAt: nil
        )
        try? store.saveDevices([trusted])

        var buildCount = 0
        let manager = DeviceSyncManager(
            store: store,
            defaults: defaults,
            makeRotationPayload: {
                buildCount += 1
                return DeviceSyncPayload(
                    connections: DeviceSyncConnections(codexAccessToken: "token")
                )
            },
            listNetworkInterfaces: { [] }
        )

        manager.noteCredentialFingerprint("same")
        let firstSyncID = manager.devices.first?.pendingSync?.id
        XCTAssertEqual(buildCount, 1)

        manager.noteCredentialFingerprint("same")
        XCTAssertEqual(buildCount, 1)
        XCTAssertEqual(manager.devices.first?.pendingSync?.id, firstSyncID)
    }

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

    func testCLICredentialFingerprintIsStableAndIgnoresMissingTokens() {
        let both = DeviceSyncManager.cliCredentialFingerprint(
            codexAccessToken: "codex",
            cursorAccessToken: "cursor"
        )
        let again = DeviceSyncManager.cliCredentialFingerprint(
            codexAccessToken: "codex",
            cursorAccessToken: "cursor"
        )
        let codexOnly = DeviceSyncManager.cliCredentialFingerprint(
            codexAccessToken: "codex",
            cursorAccessToken: nil
        )

        XCTAssertEqual(both, again)
        XCTAssertEqual(both.count, 64)
        XCTAssertNotEqual(both, codexOnly)
    }
}
