import CryptoKit
import Foundation

/// RFC 4122 §4.3 name-based UUID (version 5, SHA-1).
enum UUIDv5 {
    static func make(namespace: UUID, name: String) -> UUID {
        var namespaceBytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: namespace.uuid) { buffer in
            for (index, byte) in buffer.enumerated() where index < 16 {
                namespaceBytes[index] = byte
            }
        }

        var material = Data(namespaceBytes)
        material.append(contentsOf: name.utf8)
        let digest = Insecure.SHA1.hash(data: material)
        var bytes = Array(digest.prefix(16))

        // Version 5
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        // RFC 4122 variant
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum OpenAIResetCreditRedemption {
    /// Shared with Android (#58 / #51). Do not change.
    static let namespace = UUID(uuidString: "1b5476e9-b78c-4c12-a16e-bd64b2431354")!

    static let consumeEndpoint = URL(
        string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume"
    )!

    static func requestID(accountID: String?, creditID: String) -> UUID {
        let account = accountID ?? "local"
        return UUIDv5.make(namespace: namespace, name: "\(account):\(creditID)")
    }

    static func request(
        endpoint: URL,
        token: String,
        accountID: String?,
        creditID: String
    ) -> URLRequest {
        let redeemRequestID = requestID(accountID: accountID, creditID: creditID)
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "Originator")
        if let accountID {
            request.setValue(accountID, forHTTPHeaderField: "Chatgpt-Account-Id")
        }

        let body: [String: String] = [
            "redeem_request_id": redeemRequestID.uuidString.lowercased(),
            "credit_id": creditID
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}

enum OpenAIResetCreditOutcome: String, Codable, Equatable {
    case reset
    case nothingToReset = "nothing_to_reset"
    case noCredit = "no_credit"
    case alreadyRedeemed = "already_redeemed"

    var userMessage: String {
        switch self {
        case .reset:
            return "Limits reset"
        case .nothingToReset:
            return "Nothing to reset yet"
        case .noCredit:
            return "No credit available"
        case .alreadyRedeemed:
            return "Already redeemed"
        }
    }
}

enum OpenAIResetCreditError: Error, Equatable {
    case inFlight
    case http(status: Int)
    case invalidResponse
}

@MainActor
final class OpenAIResetCreditRedeemer {
    private static let pendingAttemptKey = "openAIResetCreditPendingAttempt"

    private let session: URLSession
    private let defaults: UserDefaults
    private(set) var isRedeeming = false

    init(session: URLSession, defaults: UserDefaults) {
        self.session = session
        self.defaults = defaults
    }

    func redeem(
        token: String,
        accountID: String?,
        creditID: String
    ) async throws -> OpenAIResetCreditOutcome {
        guard !isRedeeming else {
            throw OpenAIResetCreditError.inFlight
        }

        isRedeeming = true
        defer { isRedeeming = false }

        let requestID = resolvedRequestID(accountID: accountID, creditID: creditID)
        persistPending(creditID: creditID, requestID: requestID)

        var request = OpenAIResetCreditRedemption.request(
            endpoint: OpenAIResetCreditRedemption.consumeEndpoint,
            token: token,
            accountID: accountID,
            creditID: creditID
        )
        // Prefer the persisted request id when retrying the same credit.
        if var body = requestBodyObject(from: request) {
            body["redeem_request_id"] = requestID.uuidString.lowercased()
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Pending attempt stays so a later call reuses the same request id.
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIResetCreditError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIResetCreditError.http(status: http.statusCode)
        }

        let decoded: ConsumeResponse
        do {
            decoded = try JSONDecoder().decode(ConsumeResponse.self, from: data)
        } catch {
            throw OpenAIResetCreditError.invalidResponse
        }

        clearPending()
        return decoded.code
    }

    private func resolvedRequestID(accountID: String?, creditID: String) -> UUID {
        if let pending = loadPending(), pending.creditID == creditID {
            return pending.requestID
        }
        return OpenAIResetCreditRedemption.requestID(accountID: accountID, creditID: creditID)
    }

    private func persistPending(creditID: String, requestID: UUID) {
        let attempt = PendingAttempt(creditID: creditID, requestID: requestID)
        if let data = try? JSONEncoder().encode(attempt) {
            defaults.set(data, forKey: Self.pendingAttemptKey)
        }
    }

    private func loadPending() -> PendingAttempt? {
        guard let data = defaults.data(forKey: Self.pendingAttemptKey) else {
            return nil
        }
        return try? JSONDecoder().decode(PendingAttempt.self, from: data)
    }

    private func clearPending() {
        defaults.removeObject(forKey: Self.pendingAttemptKey)
    }

    private func requestBodyObject(from request: URLRequest) -> [String: String]? {
        guard let body = request.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: String] else {
            return nil
        }
        return object
    }
}

private struct PendingAttempt: Codable, Equatable {
    let creditID: String
    let requestID: UUID
}

private struct ConsumeResponse: Codable {
    let code: OpenAIResetCreditOutcome
}
