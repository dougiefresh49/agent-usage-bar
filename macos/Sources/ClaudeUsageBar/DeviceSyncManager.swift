import CryptoKit
import Foundation

struct PairedDevice: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    let publicKey: String
    let pairedAt: Date
    var lastSeenAt: Date?
    var revokedAt: Date?
    var wipeAcknowledgedAt: Date?

    var isRevoked: Bool { revokedAt != nil }

    var fingerprint: String {
        guard let data = Data(base64URLEncoded: publicKey) else { return "Unknown" }
        return SHA256.hash(data: data)
            .prefix(6)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
    }
}

struct PendingDevicePair: Equatable {
    let sessionID: String
    let deviceID: String
    let deviceName: String
    let publicKey: Data
    let confirmationCode: String
}

struct DevicePairingTransfer {
    let sessionID: String
    let urlString: String
    let expiresAt: Date
}

@MainActor
final class DeviceSyncManager: ObservableObject {
    @Published private(set) var devices: [PairedDevice] = []
    @Published private(set) var pendingPair: PendingDevicePair?
    @Published private(set) var completedSessionID: String?
    @Published private(set) var serverMessage: String?

    private struct PairingSession {
        let id: String
        let payload: DeviceSyncPayload
        let expiresAt: Date
        var request: PendingDevicePair?
        var approved = false
    }

    private let store: DeviceSyncStore
    private let desktopID: String
    private let privateKey: P256.KeyAgreement.PrivateKey
    private var sessions: [String: PairingSession] = [:]
    private var server: LocalDeviceSyncServer?

    init(store: DeviceSyncStore = DeviceSyncStore()) {
        self.store = store
        let identity = store.loadOrCreateIdentity()
        desktopID = identity.desktopID
        privateKey = identity.privateKey
        devices = store.loadDevices()
    }

    func startServer() {
        guard server == nil else { return }
        let server = LocalDeviceSyncServer { [weak self] request in
            guard let self else {
                return LocalHTTPResponse(status: 404, body: Data())
            }
            return await self.handle(request)
        }
        do {
            try server.start()
            self.server = server
            serverMessage = nil
        } catch {
            serverMessage = error.localizedDescription
        }
    }

    func beginPairing(payload: DeviceSyncPayload) throws -> DevicePairingTransfer {
        startServer()
        guard server != nil else { throw DeviceSyncError.serverUnavailable }
        guard let host = localIPv4Address() else {
            throw DeviceSyncError.localNetworkUnavailable
        }

        let sessionID = UUID().uuidString.lowercased()
        let expiresAt = Date().addingTimeInterval(DeviceSyncPayload.validityDuration)
        sessions[sessionID] = PairingSession(
            id: sessionID,
            payload: payload,
            expiresAt: expiresAt
        )
        pendingPair = nil
        completedSessionID = nil

        let code = DevicePairingCode(
            sessionID: sessionID,
            host: host,
            port: LocalDeviceSyncServer.port,
            desktopID: desktopID,
            desktopName: Host.current().localizedName ?? "Mac",
            desktopPublicKey: privateKey.publicKey.x963Representation
        )
        return DevicePairingTransfer(
            sessionID: sessionID,
            urlString: try code.encodedURLString(),
            expiresAt: expiresAt
        )
    }

    func approvePendingPair() {
        guard let pendingPair,
              var session = sessions[pendingPair.sessionID],
              session.expiresAt > Date() else {
            return
        }
        session.approved = true
        sessions[pendingPair.sessionID] = session
    }

    func rejectPendingPair() {
        guard let pendingPair else { return }
        sessions.removeValue(forKey: pendingPair.sessionID)
        self.pendingPair = nil
    }

    func cancelPairing(sessionID: String) {
        sessions.removeValue(forKey: sessionID)
        if pendingPair?.sessionID == sessionID {
            pendingPair = nil
        }
    }

    func removeDevice(_ device: PairedDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].revokedAt = Date()
        persistDevices()
    }

    func forgetDevice(_ device: PairedDevice) {
        devices.removeAll { $0.id == device.id }
        persistDevices()
    }

    private func handle(_ request: LocalHTTPRequest) async -> LocalHTTPResponse {
        switch (request.method, request.path) {
        case ("POST", "/v2/pair"):
            return handlePairStart(request)
        case ("GET", "/v2/pair"):
            return handlePairPoll(request)
        case ("GET", "/v2/status"):
            return handleStatus(request)
        case ("POST", "/v2/status/ack"):
            return handleWipeAcknowledgement(request)
        default:
            return LocalHTTPResponse(status: 404, body: Data())
        }
    }

    private func handlePairStart(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard let pairRequest = try? JSONDecoder().decode(DevicePairRequest.self, from: request.body),
              var session = sessions[pairRequest.sessionID],
              session.expiresAt > Date(),
              let publicKey = Data(base64URLEncoded: pairRequest.publicKey),
              let sharedSecret = try? DeviceSyncCrypto.sharedSecret(
                desktopPrivateKey: privateKey,
                devicePublicKey: publicKey
              ) else {
            return .json(["error": "Pairing request is invalid or expired."], status: 410)
        }

        let pending = PendingDevicePair(
            sessionID: pairRequest.sessionID,
            deviceID: pairRequest.deviceID,
            deviceName: String(pairRequest.deviceName.prefix(80)),
            publicKey: publicKey,
            confirmationCode: DeviceSyncCrypto.confirmationCode(
                sharedSecret: sharedSecret,
                sessionID: pairRequest.sessionID
            )
        )
        session.request = pending
        sessions[pairRequest.sessionID] = session
        pendingPair = pending
        return .json(
            DevicePairStartResponse(
                status: "pending",
                confirmationCode: pending.confirmationCode
            ),
            status: 202
        )
    }

    private func handlePairPoll(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard let sessionID = request.queryItems["session"],
              let deviceID = request.queryItems["device"],
              let suppliedProof = request.queryItems["proof"],
              let session = sessions[sessionID],
              session.expiresAt > Date(),
              let pending = session.request,
              pending.deviceID == deviceID else {
            return .json(
                DevicePairPollResponse(
                    status: "expired",
                    desktopID: nil,
                    desktopName: nil,
                    envelope: nil,
                    message: "Pairing request expired."
                ),
                status: 410
            )
        }

        guard let sharedSecret = try? DeviceSyncCrypto.sharedSecret(
            desktopPrivateKey: privateKey,
            devicePublicKey: pending.publicKey
        ), suppliedProof == DeviceSyncCrypto.authenticationProof(
            sharedSecret: sharedSecret,
            salt: sessionID,
            info: DeviceSyncCrypto.pairingInfo,
            message: "poll:\(sessionID):\(deviceID)"
        ) else {
            return .json(["error": "Pairing proof is invalid."], status: 404)
        }

        guard session.approved else {
            return .json(
                DevicePairPollResponse(
                    status: "pending",
                    desktopID: nil,
                    desktopName: nil,
                    envelope: nil,
                    message: nil
                ),
                status: 202
            )
        }

        do {
            let envelope = try DeviceSyncCrypto.seal(
                session.payload,
                sharedSecret: sharedSecret,
                salt: sessionID,
                info: DeviceSyncCrypto.pairingInfo
            )
            let device = PairedDevice(
                id: pending.deviceID,
                name: pending.deviceName,
                publicKey: pending.publicKey.base64URLEncodedString(),
                pairedAt: Date(),
                lastSeenAt: Date(),
                revokedAt: nil,
                wipeAcknowledgedAt: nil
            )
            devices.removeAll { $0.id == device.id }
            devices.append(device)
            persistDevices()
            sessions.removeValue(forKey: sessionID)
            pendingPair = nil
            completedSessionID = sessionID
            return .json(
                DevicePairPollResponse(
                    status: "approved",
                    desktopID: desktopID,
                    desktopName: Host.current().localizedName ?? "Mac",
                    envelope: envelope,
                    message: nil
                )
            )
        } catch {
            return .json(["error": "Could not encrypt the transfer."], status: 400)
        }
    }

    private func handleStatus(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard let deviceID = request.queryItems["device"],
              let claimedDesktopID = request.queryItems["desktop"],
              let timestampString = request.queryItems["ts"],
              let timestamp = Int64(timestampString),
              abs(Int64(Date().timeIntervalSince1970) - timestamp) <= 60,
              let suppliedProof = request.queryItems["proof"],
              claimedDesktopID == desktopID,
              let index = devices.firstIndex(where: { $0.id == deviceID }),
              let publicKey = Data(base64URLEncoded: devices[index].publicKey) else {
            return .json(["error": "Unknown device."], status: 404)
        }

        do {
            let secret = try DeviceSyncCrypto.sharedSecret(
                desktopPrivateKey: privateKey,
                devicePublicKey: publicKey
            )
            let expectedProof = DeviceSyncCrypto.authenticationProof(
                sharedSecret: secret,
                salt: desktopID,
                info: DeviceSyncCrypto.statusInfo,
                message: "status:\(desktopID):\(deviceID):\(timestamp)"
            )
            guard suppliedProof == expectedProof else {
                return .json(["error": "Device proof is invalid."], status: 404)
            }
            devices[index].lastSeenAt = Date()
            let command = DeviceStatusCommand(
                action: devices[index].isRevoked ? "wipe" : "none",
                issuedAtEpochSeconds: Int64(Date().timeIntervalSince1970)
            )
            let envelope = try DeviceSyncCrypto.seal(
                command,
                sharedSecret: secret,
                salt: desktopID,
                info: DeviceSyncCrypto.statusInfo
            )
            persistDevices()
            return .json(envelope)
        } catch {
            return .json(["error": "Could not create device status."], status: 400)
        }
    }

    private func handleWipeAcknowledgement(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard let acknowledgement = try? JSONDecoder().decode(
            DeviceWipeAcknowledgement.self,
            from: request.body
        ),
        acknowledgement.desktopID == desktopID,
        abs(Int64(Date().timeIntervalSince1970) - acknowledgement.timestamp) <= 60,
        let index = devices.firstIndex(where: {
            $0.id == acknowledgement.deviceID && $0.isRevoked
        }),
        let publicKey = Data(base64URLEncoded: devices[index].publicKey),
        let secret = try? DeviceSyncCrypto.sharedSecret(
            desktopPrivateKey: privateKey,
            devicePublicKey: publicKey
        ) else {
            return .json(["error": "Unknown device acknowledgement."], status: 404)
        }
        let expectedProof = DeviceSyncCrypto.authenticationProof(
            sharedSecret: secret,
            salt: desktopID,
            info: DeviceSyncCrypto.statusInfo,
            message: "wipe-ack:\(desktopID):\(acknowledgement.deviceID):\(acknowledgement.timestamp)"
        )
        guard acknowledgement.proof == expectedProof else {
            return .json(["error": "Acknowledgement proof is invalid."], status: 404)
        }
        devices[index].lastSeenAt = Date()
        devices[index].wipeAcknowledgedAt = Date()
        persistDevices()
        return .json(["status": "acknowledged"])
    }

    private func persistDevices() {
        devices.sort { $0.pairedAt > $1.pairedAt }
        try? store.saveDevices(devices)
    }
}

struct DeviceSyncStore {
    struct Identity {
        let desktopID: String
        let privateKey: P256.KeyAgreement.PrivateKey
    }

    private let fileManager: FileManager
    let directoryURL: URL
    let identityURL: URL
    let devicesURL: URL

    init(
        directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        identityURL = directoryURL.appendingPathComponent("device-sync-identity.json")
        devicesURL = directoryURL.appendingPathComponent("paired-devices.json")
    }

    func loadOrCreateIdentity() -> Identity {
        struct StoredIdentity: Codable {
            let desktopID: String
            let privateKey: String
        }

        if let data = try? Data(contentsOf: identityURL),
           let stored = try? JSONDecoder().decode(StoredIdentity.self, from: data),
           let keyData = Data(base64URLEncoded: stored.privateKey),
           let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: keyData) {
            return Identity(desktopID: stored.desktopID, privateKey: key)
        }

        let identity = Identity(
            desktopID: UUID().uuidString.lowercased(),
            privateKey: P256.KeyAgreement.PrivateKey()
        )
        try? ensureDirectory()
        let stored = StoredIdentity(
            desktopID: identity.desktopID,
            privateKey: identity.privateKey.rawRepresentation.base64URLEncodedString()
        )
        if let data = try? JSONEncoder.deviceSyncEncoder.encode(stored) {
            try? data.write(to: identityURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: identityURL.path)
        }
        return identity
    }

    func loadDevices() -> [PairedDevice] {
        guard let data = try? Data(contentsOf: devicesURL),
              let devices = try? JSONDecoder.deviceSyncDecoder.decode([PairedDevice].self, from: data) else {
            return []
        }
        return devices
    }

    func saveDevices(_ devices: [PairedDevice]) throws {
        try ensureDirectory()
        let data = try JSONEncoder.deviceSyncEncoder.encode(devices)
        try data.write(to: devicesURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: devicesURL.path)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }
}

private extension JSONDecoder {
    static let deviceSyncDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private func localIPv4Address() -> String? {
    var address: String?
    var interfaces: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
    defer { freeifaddrs(interfaces) }

    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let interface = pointer.pointee
        guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
        let name = String(cString: interface.ifa_name)
        guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            interface.ifa_addr,
            socklen_t(interface.ifa_addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        if result == 0 {
            let candidate = String(cString: hostname)
            guard !candidate.hasPrefix("169.254.") else { continue }
            if address == nil || name.hasPrefix("en") {
                address = candidate
            }
            if name == "en0" { break }
        }
    }
    return address
}
