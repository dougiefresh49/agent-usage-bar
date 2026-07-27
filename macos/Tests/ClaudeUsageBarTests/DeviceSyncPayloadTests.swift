import CryptoKit
import XCTest
@testable import AgentUsageBar

final class DeviceSyncPayloadTests: XCTestCase {
    func testPairingQRCodeContainsHandshakeButNoCredentials() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let code = DevicePairingCode(
            sessionID: "session-123",
            host: "192.168.1.10",
            port: 48_321,
            desktopID: "desktop-123",
            desktopName: "Test Mac",
            desktopPublicKey: key.publicKey.x963Representation
        )

        let encoded = try code.encodedURLString()

        XCTAssertTrue(encoded.hasPrefix("agentusagebar://pair/v2?"))
        XCTAssertTrue(encoded.contains("session=session-123"))
        XCTAssertTrue(encoded.contains("host=192.168.1.10"))
        XCTAssertFalse(encoded.contains("openai-secret"))
    }

    func testBothDevicesDeriveSameConfirmationCodeAndEncryptionKey() throws {
        let desktopKey = P256.KeyAgreement.PrivateKey()
        let deviceKey = P256.KeyAgreement.PrivateKey()
        let desktopSecret = try desktopKey.sharedSecretFromKeyAgreement(with: deviceKey.publicKey)
        let deviceSecret = try deviceKey.sharedSecretFromKeyAgreement(with: desktopKey.publicKey)

        let desktopCode = DeviceSyncCrypto.confirmationCode(
            sharedSecret: desktopSecret,
            sessionID: "session"
        )
        let deviceCode = DeviceSyncCrypto.confirmationCode(
            sharedSecret: deviceSecret,
            sessionID: "session"
        )

        XCTAssertEqual(desktopCode, deviceCode)
        XCTAssertEqual(desktopCode.count, 6)

        let desktopDerived = DeviceSyncCrypto.key(
            sharedSecret: desktopSecret,
            salt: "session",
            info: DeviceSyncCrypto.pairingInfo
        ).withUnsafeBytes { Data($0) }
        let deviceDerived = DeviceSyncCrypto.key(
            sharedSecret: deviceSecret,
            salt: "session",
            info: DeviceSyncCrypto.pairingInfo
        ).withUnsafeBytes { Data($0) }
        XCTAssertEqual(desktopDerived, deviceDerived)
    }

    func testHKDFMatchesCrossPlatformProtocolVector() {
        let secret = Data(0..<32)
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: Data("session".utf8),
            info: DeviceSyncCrypto.pairingInfo,
            outputByteCount: 32
        )
        let hex = key.withUnsafeBytes {
            Data($0).map { String(format: "%02x", $0) }.joined()
        }

        XCTAssertEqual(
            hex,
            "3231269fb3db3487dedcd8abef9031471e1ee65e2a7b9efe2b69661955c4b964"
        )
    }

    func testDeviceLedgerRoundTripsWithPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceSyncStore(directoryURL: directory)
        let pendingSync = PendingDeviceSync(
            id: "sync-123",
            envelope: DeviceEncryptedEnvelope(
                nonce: "nonce",
                ciphertext: "ciphertext",
                tag: "tag"
            ),
            requestedAt: Date(timeIntervalSince1970: 1_750_000_100)
        )
        let device = PairedDevice(
            id: "phone",
            name: "Pixel",
            publicKey: Data(repeating: 1, count: 65).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_750_000_000),
            lastSeenAt: nil,
            revokedAt: nil,
            wipeAcknowledgedAt: nil,
            pendingSync: pendingSync,
            syncAcknowledgedAt: Date(timeIntervalSince1970: 1_750_000_200)
        )

        try store.saveDevices([device])

        XCTAssertEqual(store.loadDevices(), [device])
        let permissions = try FileManager.default.attributesOfItem(
            atPath: store.devicesURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testExistingDeviceLedgerDecodesWithoutSyncFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceSyncStore(directoryURL: directory)
        let json = """
        [{
          "id": "phone",
          "name": "Pixel",
          "publicKey": "AQ",
          "pairedAt": "2025-06-15T15:06:40Z"
        }]
        """
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: store.devicesURL)

        let device = try XCTUnwrap(store.loadDevices().first)

        XCTAssertEqual(device.id, "phone")
        XCTAssertNil(device.pendingSync)
        XCTAssertNil(device.syncAcknowledgedAt)
    }

    func testResyncEnvelopeUsesTrustedDeviceKeyAndHidesCredentials() throws {
        let desktopKey = P256.KeyAgreement.PrivateKey()
        let deviceKey = P256.KeyAgreement.PrivateKey()
        let desktopSecret = try desktopKey.sharedSecretFromKeyAgreement(
            with: deviceKey.publicKey
        )
        let deviceSecret = try deviceKey.sharedSecretFromKeyAgreement(
            with: desktopKey.publicKey
        )
        let payload = DeviceSyncPayload(
            connections: DeviceSyncConnections(
                openAISessionToken: "very-secret-token",
                cursorSessionToken: nil,
                elevenLabsAPIKey: nil
            )
        )
        let syncID = "sync-123"

        let envelope = try DeviceSyncCrypto.seal(
            payload,
            sharedSecret: desktopSecret,
            salt: syncID,
            info: DeviceSyncCrypto.resyncInfo
        )
        let encodedEnvelope = try JSONEncoder().encode(envelope)
        XCTAssertFalse(String(decoding: encodedEnvelope, as: UTF8.self).contains("very-secret-token"))

        let key = DeviceSyncCrypto.key(
            sharedSecret: deviceSecret,
            salt: syncID,
            info: DeviceSyncCrypto.resyncInfo
        )
        let nonce = try AES.GCM.Nonce(
            data: XCTUnwrap(Data(base64URLEncoded: envelope.nonce))
        )
        let box = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: XCTUnwrap(Data(base64URLEncoded: envelope.ciphertext)),
            tag: XCTUnwrap(Data(base64URLEncoded: envelope.tag))
        )
        let decrypted = try AES.GCM.open(box, using: key)
        let decoded = try JSONDecoder().decode(DeviceSyncPayload.self, from: decrypted)

        XCTAssertEqual(decoded, payload)
    }
}
