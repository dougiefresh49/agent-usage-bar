import XCTest
@testable import AgentUsageBar

final class ClaudeCodeCredentialsTests: XCTestCase {
    func testLoadUsesExactExecutableAndArgv() {
        let credentials = ClaudeCodeKeychain.load { executable, arguments in
            XCTAssertEqual(executable, "/usr/bin/security")
            XCTAssertEqual(
                arguments,
                ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            )
            return Self.oauthJSON(accessToken: "cli-access", expiresAtMs: 1_789_074_284_548)
        }

        XCTAssertEqual(credentials?.accessToken, "cli-access")
    }

    func testLoadConvertsExpiresAtMillisecondsToDate() throws {
        let credentials = ClaudeCodeKeychain.load { _, _ in
            Self.oauthJSON(accessToken: "cli-access", expiresAtMs: 1_789_074_284_548)
        }

        let expiresAt = try XCTUnwrap(credentials?.expiresAt)
        XCTAssertEqual(
            expiresAt.timeIntervalSince1970,
            1_789_074_284.548,
            accuracy: 0.001
        )
        XCTAssertEqual(credentials?.subscriptionType, "max")
        XCTAssertEqual(credentials?.rateLimitTier, "default_claude_max_20x")
    }

    func testLoadIgnoresRefreshTokenField() {
        let credentials = ClaudeCodeKeychain.load { _, _ in
            """
            {
              "claudeAiOauth": {
                "refreshToken": "must-never-surface"
              }
            }
            """
        }

        XCTAssertNil(credentials)

        let labels = Mirror(reflecting: ClaudeCodeCredentials(
            accessToken: "tok",
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )).children.compactMap(\.label)
        XCTAssertFalse(labels.contains("refreshToken"))
    }

    func testLoadReturnsNilWhenClaudeAiOauthIsMissing() {
        let credentials = ClaudeCodeKeychain.load { _, _ in
            #"{"unrelated": true}"#
        }
        XCTAssertNil(credentials)
    }

    func testLoadReturnsNilWhenAccessTokenIsEmpty() {
        let credentials = ClaudeCodeKeychain.load { _, _ in
            Self.oauthJSON(accessToken: "   ", expiresAtMs: 1_789_074_284_548)
        }
        XCTAssertNil(credentials)
    }

    func testLoadReturnsNilForMalformedJSON() {
        let credentials = ClaudeCodeKeychain.load { _, _ in "{ not json" }
        XCTAssertNil(credentials)
    }

    func testLoadReturnsNilWhenRunnerThrows() {
        struct StubError: Error {}

        let credentials = ClaudeCodeKeychain.load { _, _ in
            throw StubError()
        }

        XCTAssertNil(credentials)
    }

    func testLoadSucceedsWhenDocumentAlsoContainsMcpOAuth() throws {
        let credentials = ClaudeCodeKeychain.load { _, _ in
            """
            {
              "claudeAiOauth": {
                "accessToken": "cli-access",
                "refreshToken": "must-never-surface",
                "expiresAt": 1789074284548,
                "subscriptionType": "max",
                "rateLimitTier": "default_claude_max_20x"
              },
              "mcpOAuth": {
                "some-server": {
                  "accessToken": "third-party-must-never-surface"
                }
              }
            }
            """
        }

        XCTAssertEqual(credentials?.accessToken, "cli-access")
        let expiresAt = try XCTUnwrap(credentials?.expiresAt)
        XCTAssertEqual(
            expiresAt.timeIntervalSince1970,
            1_789_074_284.548,
            accuracy: 0.001
        )
    }

    private static func oauthJSON(accessToken: String, expiresAtMs: Int64) -> String {
        """
        {
          "claudeAiOauth": {
            "accessToken": "\(accessToken)",
            "refreshToken": "must-never-surface",
            "expiresAt": \(expiresAtMs),
            "subscriptionType": "max",
            "rateLimitTier": "default_claude_max_20x"
          }
        }
        """
    }
}
