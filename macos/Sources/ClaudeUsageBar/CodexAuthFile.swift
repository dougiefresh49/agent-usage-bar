import Foundation

struct CodexCLICredentials: Equatable {
    let accessToken: String
    let accountId: String?
    let lastRefresh: Date?
}

enum CodexAuthFile {
    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CodexCLICredentials? {
        let authURL = authFileURL(environment: environment, home: home)
        guard let data = try? Data(contentsOf: authURL) else {
            return nil
        }
        guard let file = try? JSONDecoder().decode(AuthFileContents.self, from: data) else {
            return nil
        }
        guard file.authMode == "chatgpt" else {
            return nil
        }
        guard let accessToken = file.tokens?.accessToken?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken.isEmpty == false else {
            return nil
        }

        let accountId = file.tokens?.accountId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAccountId = (accountId?.isEmpty == false) ? accountId : nil

        return CodexCLICredentials(
            accessToken: accessToken,
            accountId: normalizedAccountId,
            lastRefresh: parseLastRefresh(file.lastRefresh)
        )
    }

    private static func authFileURL(environment: [String: String], home: URL) -> URL {
        if let codexHome = environment["CODEX_HOME"] {
            return URL(fileURLWithPath: codexHome, isDirectory: true)
                .appendingPathComponent("auth.json")
        }
        return home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    private static func parseLastRefresh(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else { return nil }
        return fractionalSecondsFormatter.date(from: value)
            ?? internetDateTimeFormatter.date(from: value)
    }

    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct AuthFileContents: Decodable {
    let authMode: String?
    let tokens: Tokens?
    let lastRefresh: String?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case tokens
        case lastRefresh = "last_refresh"
    }

    struct Tokens: Decodable {
        let accessToken: String?
        let accountId: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }
}
