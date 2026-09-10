import XCTest
@testable import AgentUsageBar

final class CodexAuthFileTests: XCTestCase {
    private var tempHome: URL!
    private var tempCodexHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-home-\(UUID().uuidString)", isDirectory: true)
        tempCodexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempCodexHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
        try? FileManager.default.removeItem(at: tempCodexHome)
        try super.tearDownWithError()
    }

    func testLoadHappyPathFromDefaultCodexHome() throws {
        let authDir = tempHome.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: authDir, withIntermediateDirectories: true)
        try writeAuthFile(
            at: authDir.appendingPathComponent("auth.json"),
            authMode: "chatgpt",
            accessToken: "access-token-1",
            accountId: "acct-123",
            lastRefresh: "2026-09-04T02:39:09.977682Z"
        )

        let credentials = CodexAuthFile.load(environment: [:], home: tempHome)

        XCTAssertEqual(credentials?.accessToken, "access-token-1")
        XCTAssertEqual(credentials?.accountId, "acct-123")
        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(credentials?.lastRefresh, expected.date(from: "2026-09-04T02:39:09.977682Z"))
    }

    func testLoadUsesCODEX_HOMEOverride() throws {
        try writeAuthFile(
            at: tempCodexHome.appendingPathComponent("auth.json"),
            authMode: "chatgpt",
            accessToken: "override-token",
            accountId: "acct-override",
            lastRefresh: "2026-09-04T02:39:09.977682Z"
        )
        let defaultDir = tempHome.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)
        try writeAuthFile(
            at: defaultDir.appendingPathComponent("auth.json"),
            authMode: "chatgpt",
            accessToken: "default-token",
            accountId: "acct-default",
            lastRefresh: "2026-09-04T02:39:09.977682Z"
        )

        let credentials = CodexAuthFile.load(
            environment: ["CODEX_HOME": tempCodexHome.path],
            home: tempHome
        )

        XCTAssertEqual(credentials?.accessToken, "override-token")
        XCTAssertEqual(credentials?.accountId, "acct-override")
    }

    func testLoadReturnsNilForAPIKeyAuthMode() throws {
        try writeAuthFile(
            at: tempCodexHome.appendingPathComponent("auth.json"),
            authMode: "apikey",
            accessToken: "should-not-load",
            accountId: "acct-1",
            lastRefresh: "2026-09-04T02:39:09.977682Z"
        )

        let credentials = CodexAuthFile.load(
            environment: ["CODEX_HOME": tempCodexHome.path],
            home: tempHome
        )

        XCTAssertNil(credentials)
    }

    func testLoadReturnsNilWhenFileIsMissing() {
        let credentials = CodexAuthFile.load(
            environment: ["CODEX_HOME": tempCodexHome.path],
            home: tempHome
        )

        XCTAssertNil(credentials)
    }

    func testLoadReturnsNilForMalformedJSON() throws {
        let authURL = tempCodexHome.appendingPathComponent("auth.json")
        try Data("{ not json".utf8).write(to: authURL)

        let credentials = CodexAuthFile.load(
            environment: ["CODEX_HOME": tempCodexHome.path],
            home: tempHome
        )

        XCTAssertNil(credentials)
    }

    func testLoadIgnoresRefreshTokenField() throws {
        let authURL = tempCodexHome.appendingPathComponent("auth.json")
        let json = """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "access-only",
            "refresh_token": "must-never-surface",
            "account_id": "acct-9"
          },
          "last_refresh": "2026-09-04T02:39:09.977682Z"
        }
        """
        try Data(json.utf8).write(to: authURL)

        let credentials = CodexAuthFile.load(
            environment: ["CODEX_HOME": tempCodexHome.path],
            home: tempHome
        )

        let loaded = try XCTUnwrap(credentials)
        XCTAssertEqual(loaded.accessToken, "access-only")
        XCTAssertEqual(loaded.accountId, "acct-9")
        let labels = Mirror(reflecting: loaded).children.compactMap(\.label)
        XCTAssertFalse(labels.contains("refreshToken"))
    }

    private func writeAuthFile(
        at url: URL,
        authMode: String,
        accessToken: String,
        accountId: String,
        lastRefresh: String
    ) throws {
        let json = """
        {
          "auth_mode": "\(authMode)",
          "OPENAI_API_KEY": null,
          "tokens": {
            "id_token": "id-token",
            "access_token": "\(accessToken)",
            "refresh_token": "refresh-token",
            "account_id": "\(accountId)"
          },
          "last_refresh": "\(lastRefresh)"
        }
        """
        try Data(json.utf8).write(to: url)
    }
}
