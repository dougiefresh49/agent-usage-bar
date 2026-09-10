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

    func testResyncEnvelopeUsesTrustedDeviceKey() throws {
        let desktopKey = P256.KeyAgreement.PrivateKey()
        let deviceKey = P256.KeyAgreement.PrivateKey()
        let desktopSecret = try desktopKey.sharedSecretFromKeyAgreement(
            with: deviceKey.publicKey
        )
        let deviceSecret = try deviceKey.sharedSecretFromKeyAgreement(
            with: desktopKey.publicKey
        )
        let payload = DeviceSyncPayload(
            general: DeviceSyncGeneral(pollingMinutes: 5)
        )
        let syncID = "sync-123"

        let envelope = try DeviceSyncCrypto.seal(
            payload,
            sharedSecret: desktopSecret,
            salt: syncID,
            info: DeviceSyncCrypto.resyncInfo
        )

        let decoded = try DeviceSyncCrypto.open(
            envelope,
            as: DeviceSyncPayload.self,
            sharedSecret: deviceSecret,
            salt: syncID,
            info: DeviceSyncCrypto.resyncInfo
        )

        XCTAssertEqual(decoded, payload)
        XCTAssertNil(decoded.connections)
    }

    func testPairingPayloadBuiltByTheSheetCarriesNoConnections() throws {
        let payload = DeviceSyncPayload(
            general: DeviceSyncGeneral(pollingMinutes: 5),
            appearance: DeviceSyncAppearance(
                preferredProvider: "claude",
                menuBarStyle: "bar",
                primaryMetric: "five_hour",
                secondaryMetric: "seven_day",
                detailStyle: "orbit",
                textSize: "medium"
            ,
                fillMode: "drain"
            ),
            notifications: DeviceSyncNotifications(
                claudeSession: 80,
                claudeSevenDay: 80,
                claudeFable: 80,
                openAIWeekly: 80,
                openAIResetCredits: 1,
                cursorAPI: 80,
                cursorAuto: 80,
                cursorCredit: 80
            )
        )
        let encoded = try JSONEncoder.deviceSyncEncoder.encode(payload)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertNil(payload.connections)
        XCTAssertNil(object["connections"])
        XCTAssertEqual(payload.appearance?.fillMode, "drain")
        XCTAssertEqual(payload.version, 1)
    }

    func testPayloadVersionStaysOneWithoutV2Fields() throws {
        let payload = DeviceSyncPayload(
            connections: DeviceSyncConnections(
                openAISessionToken: "session",
                cursorSessionToken: nil,
                elevenLabsAPIKey: nil
            )
        )
        let encoded = try JSONEncoder.deviceSyncEncoder.encode(payload)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(DeviceSyncPayload.currentVersion, 2)
    }

    func testPayloadVersionIsTwoWhenV2FieldPresent() throws {
        let payload = DeviceSyncPayload(
            connections: DeviceSyncConnections(
                openAISessionToken: "session",
                codexAccessToken: "codex-access",
                codexAccountId: "acct-1",
                cursorAccessToken: "cursor-access"
            )
        )
        let encoded = try JSONEncoder.deviceSyncEncoder.encode(payload)
        let decoded = try JSONDecoder().decode(DeviceSyncPayload.self, from: encoded)

        XCTAssertEqual(payload.version, 2)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.connections?.codexAccessToken, "codex-access")
        XCTAssertEqual(decoded.connections?.codexAccountId, "acct-1")
        XCTAssertEqual(decoded.connections?.cursorAccessToken, "cursor-access")
        XCTAssertEqual(decoded.connections?.count, 4)
    }

    func testV2PayloadRoundTripsThroughEnvelopeCrypto() throws {
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
                codexAccessToken: "codex-secret",
                codexAccountId: "acct",
                cursorAccessToken: "cursor-secret"
            )
        )

        let envelope = try DeviceSyncCrypto.seal(
            payload,
            sharedSecret: desktopSecret,
            salt: "sync-v2",
            info: DeviceSyncCrypto.resyncInfo
        )
        let encodedEnvelope = try JSONEncoder().encode(envelope)
        let envelopeText = String(decoding: encodedEnvelope, as: UTF8.self)
        XCTAssertFalse(envelopeText.contains("codex-secret"))
        XCTAssertFalse(envelopeText.contains("cursor-secret"))

        let key = DeviceSyncCrypto.key(
            sharedSecret: deviceSecret,
            salt: "sync-v2",
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
        XCTAssertEqual(decoded.version, 2)
    }

    func testPairingCodeIncludesAltWhenProvided() throws {
        let key = P256.KeyAgreement.PrivateKey()
        let code = DevicePairingCode(
            sessionID: "session-123",
            host: "100.64.1.5",
            port: 48_321,
            desktopID: "desktop-123",
            desktopName: "Test Mac",
            desktopPublicKey: key.publicKey.x963Representation,
            alt: "192.168.1.10"
        )

        let encoded = try code.encodedURLString()

        XCTAssertTrue(encoded.contains("host=100.64.1.5"))
        XCTAssertTrue(encoded.contains("alt=192.168.1.10"))
    }
}
