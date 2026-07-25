import CryptoKit
import Foundation

struct DeviceSyncGeneral: Codable, Equatable {
    let pollingMinutes: Int
}

struct DeviceSyncAppearance: Codable, Equatable {
    let preferredProvider: String
    let menuBarStyle: String
    let primaryMetric: String
    let secondaryMetric: String
    let detailStyle: String
    let textSize: String
}

struct DeviceSyncNotifications: Codable, Equatable {
    let claudeSession: Int
    let claudeSevenDay: Int
    let claudeFable: Int
    let openAIWeekly: Int
    let openAIResetCredits: Int
    let cursorAPI: Int
    let cursorAuto: Int
    let cursorCredit: Int
}

struct DeviceSyncConnections: Codable, Equatable {
    let openAISessionToken: String?
    let cursorSessionToken: String?
    let elevenLabsAPIKey: String?

    var count: Int {
        [openAISessionToken, cursorSessionToken, elevenLabsAPIKey]
            .compactMap { $0 }
            .count
    }
}

struct DeviceSyncPayload: Codable, Equatable {
    static let currentVersion = 1
    static let validityDuration: TimeInterval = 10 * 60

    let version: Int
    let issuedAtEpochSeconds: Int64
    let expiresAtEpochSeconds: Int64
    let general: DeviceSyncGeneral?
    let appearance: DeviceSyncAppearance?
    let notifications: DeviceSyncNotifications?
    let connections: DeviceSyncConnections?

    init(
        issuedAt: Date = Date(),
        general: DeviceSyncGeneral? = nil,
        appearance: DeviceSyncAppearance? = nil,
        notifications: DeviceSyncNotifications? = nil,
        connections: DeviceSyncConnections? = nil
    ) {
        version = Self.currentVersion
        issuedAtEpochSeconds = Int64(issuedAt.timeIntervalSince1970)
        expiresAtEpochSeconds = Int64(
            issuedAt.addingTimeInterval(Self.validityDuration).timeIntervalSince1970
        )
        self.general = general
        self.appearance = appearance
        self.notifications = notifications
        self.connections = connections
    }
}

struct DevicePairingCode: Equatable {
    static let currentVersion = 2

    let sessionID: String
    let host: String
    let port: UInt16
    let desktopID: String
    let desktopName: String
    let desktopPublicKey: Data

    func encodedURLString() throws -> String {
        var components = URLComponents()
        components.scheme = "agentusagebar"
        components.host = "pair"
        components.path = "/v2"
        components.queryItems = [
            URLQueryItem(name: "v", value: String(Self.currentVersion)),
            URLQueryItem(name: "session", value: sessionID),
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "desktop", value: desktopID),
            URLQueryItem(name: "name", value: desktopName),
            URLQueryItem(name: "key", value: desktopPublicKey.base64URLEncodedString())
        ]
        guard let value = components.string else {
            throw DeviceSyncError.invalidCode
        }
        return value
    }
}

struct DevicePairRequest: Codable {
    let sessionID: String
    let deviceID: String
    let deviceName: String
    let publicKey: String
}

struct DevicePairStartResponse: Codable {
    let status: String
    let confirmationCode: String
}

struct DevicePairPollResponse: Codable {
    let status: String
    let desktopID: String?
    let desktopName: String?
    let envelope: DeviceEncryptedEnvelope?
    let message: String?
}

struct DeviceEncryptedEnvelope: Codable, Equatable {
    let nonce: String
    let ciphertext: String
    let tag: String
}

struct DeviceStatusCommand: Codable {
    let action: String
    let issuedAtEpochSeconds: Int64
}

struct DeviceWipeAcknowledgement: Codable {
    let desktopID: String
    let deviceID: String
    let timestamp: Int64
    let proof: String
}

enum DeviceSyncCrypto {
    static let pairingInfo = Data("agentusagebar-device-pair-v2".utf8)
    static let statusInfo = Data("agentusagebar-device-status-v2".utf8)

    static func sharedSecret(
        desktopPrivateKey: P256.KeyAgreement.PrivateKey,
        devicePublicKey: Data
    ) throws -> SharedSecret {
        let publicKey = try P256.KeyAgreement.PublicKey(x963Representation: devicePublicKey)
        return try desktopPrivateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }

    static func key(
        sharedSecret: SharedSecret,
        salt: String,
        info: Data
    ) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(salt.utf8),
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    static func confirmationCode(sharedSecret: SharedSecret, sessionID: String) -> String {
        let key = key(sharedSecret: sharedSecret, salt: sessionID, info: pairingInfo)
        let bytes = key.withUnsafeBytes { Data($0) }
        let number = bytes.prefix(4).reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        } % 1_000_000
        return String(format: "%06u", number)
    }

    static func authenticationProof(
        sharedSecret: SharedSecret,
        salt: String,
        info: Data,
        message: String
    ) -> String {
        let symmetricKey = key(sharedSecret: sharedSecret, salt: salt, info: info)
        return Data(
            HMAC<SHA256>.authenticationCode(
                for: Data(message.utf8),
                using: symmetricKey
            )
        ).base64URLEncodedString()
    }

    static func seal<T: Encodable>(
        _ value: T,
        sharedSecret: SharedSecret,
        salt: String,
        info: Data
    ) throws -> DeviceEncryptedEnvelope {
        let data = try JSONEncoder.deviceSyncEncoder.encode(value)
        let symmetricKey = key(sharedSecret: sharedSecret, salt: salt, info: info)
        let box = try AES.GCM.seal(data, using: symmetricKey)
        return DeviceEncryptedEnvelope(
            nonce: Data(box.nonce).base64URLEncodedString(),
            ciphertext: box.ciphertext.base64URLEncodedString(),
            tag: box.tag.base64URLEncodedString()
        )
    }
}

enum DeviceSyncError: LocalizedError {
    case invalidCode
    case codeTooLarge
    case localNetworkUnavailable
    case serverUnavailable
    case pairingExpired
    case unknownDevice

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "This is not a valid Agent Usage Bar device code."
        case .codeTooLarge:
            return "Could not create the pairing QR code."
        case .localNetworkUnavailable:
            return "Connect this Mac and phone to the same local network and try again."
        case .serverUnavailable:
            return "Could not start secure device pairing on this Mac."
        case .pairingExpired:
            return "This pairing request expired. Generate a new QR code."
        case .unknownDevice:
            return "This device is not registered with this Mac."
        }
    }
}

extension JSONEncoder {
    static let deviceSyncEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }
}
