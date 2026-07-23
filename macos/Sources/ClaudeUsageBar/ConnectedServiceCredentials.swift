import Foundation

struct ConnectedServiceCredentials: Codable, Equatable {
    var openAISessionToken: String?
    var cursorSessionToken: String?

    var isEmpty: Bool {
        openAISessionToken?.isEmpty != false && cursorSessionToken?.isEmpty != false
    }
}

struct ConnectedServiceCredentialsStore {
    private let fileManager: FileManager
    let directoryURL: URL
    let credentialsFileURL: URL

    init(
        directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        self.credentialsFileURL = directoryURL.appendingPathComponent("service-credentials.json")
    }

    func save(_ credentials: ConnectedServiceCredentials) throws {
        if credentials.isEmpty {
            delete()
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: credentialsFileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsFileURL.path)
    }

    func load() -> ConnectedServiceCredentials {
        guard let data = try? Data(contentsOf: credentialsFileURL),
              let credentials = try? JSONDecoder().decode(ConnectedServiceCredentials.self, from: data) else {
            return ConnectedServiceCredentials()
        }
        return credentials
    }

    func delete() {
        try? fileManager.removeItem(at: credentialsFileURL)
    }
}

enum ConnectedTokenNormalizer {
    static func openAI(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let token = firstMatch(
            in: trimmed,
            pattern: #"(?i)authorization:\s*(?:bearer\s+)?([^'"\s\\]+)"#
        ) {
            return token
        }

        return trimmed.replacingOccurrences(
            of: #"(?i)^bearer\s+"#,
            with: "",
            options: .regularExpression
        )
    }

    static func cursor(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let token = firstMatch(
            in: trimmed,
            pattern: #"(?i)WorkosCursorSessionToken=([^;'"\\\s]+)"#
        ) {
            return token
        }

        return trimmed
    }

    private static func firstMatch(in input: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: input,
                range: NSRange(input.startIndex..., in: input)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: input) else {
            return nil
        }
        return String(input[range])
    }
}
