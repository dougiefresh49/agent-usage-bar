import Foundation

struct CursorCLICredentials: Equatable {
    let accessToken: String
}

enum CursorCLIKeychain {
    typealias Runner = (_ executable: String, _ arguments: [String]) throws -> String

    private static let service = "cursor-access-token"
    private static let account = "cursor-user"
    private static let securityPath = "/usr/bin/security"
    private static let timeoutSeconds: TimeInterval = 3

    static func load(runner: Runner = defaultRunner) -> CursorCLICredentials? {
        let token: String
        do {
            token = try runner(
                securityPath,
                ["find-generic-password", "-s", service, "-a", account, "-w"]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }

        guard token.isEmpty == false else { return nil }
        return CursorCLICredentials(accessToken: token)
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
