import Foundation

struct ClaudeCodeCredentials: Equatable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?
}

enum ClaudeCodeKeychain {
    typealias Runner = (_ executable: String, _ arguments: [String]) throws -> String

    private static let service = "Claude Code-credentials"
    private static let securityPath = "/usr/bin/security"
    private static let timeoutSeconds: TimeInterval = 3

    static func load(runner: Runner = defaultRunner) -> ClaudeCodeCredentials? {
        let raw: String
        do {
            raw = try runner(
                securityPath,
                ["find-generic-password", "-s", service, "-w"]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }

        guard raw.isEmpty == false,
              let data = raw.data(using: .utf8),
              let document = try? JSONDecoder().decode(KeychainDocument.self, from: data),
              let oauth = document.claudeAiOauth else {
            return nil
        }

        let accessToken = oauth.accessToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let accessToken, accessToken.isEmpty == false else {
            return nil
        }

        return ClaudeCodeCredentials(
            accessToken: accessToken,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: oauth.subscriptionType,
            rateLimitTier: oauth.rateLimitTier
        )
    }

    static func defaultRunner(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 1)
            return ""
        }

        guard process.terminationStatus == 0 else { return "" }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Declares only the Claude Code OAuth fields we read so a refresh token and the
/// `mcpOAuth` blob are never materialised into a Swift value.
private struct KeychainDocument: Decodable {
    let claudeAiOauth: OAuth?

    struct OAuth: Decodable {
        let accessToken: String?
        let expiresAt: Double?
        let subscriptionType: String?
        let rateLimitTier: String?
    }
}
