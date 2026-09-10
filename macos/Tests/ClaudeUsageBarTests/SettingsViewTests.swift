import XCTest
@testable import AgentUsageBar

final class SettingsViewTests: XCTestCase {
    func testSupportsLaunchAtLoginManagementForSystemApplications() {
        XCTAssertTrue(
            supportsLaunchAtLoginManagement(
                appURL: URL(fileURLWithPath: "/Applications/AgentUsageBar.app"),
                installDirectories: [
                    URL(fileURLWithPath: "/Applications", isDirectory: true),
                    URL(fileURLWithPath: "/Users/test/Applications", isDirectory: true)
                ]
            )
        )
    }

    func testSupportsLaunchAtLoginManagementForUserApplications() {
        XCTAssertTrue(
            supportsLaunchAtLoginManagement(
                appURL: URL(fileURLWithPath: "/Users/test/Applications/AgentUsageBar.app"),
                installDirectories: [
                    URL(fileURLWithPath: "/Applications", isDirectory: true),
                    URL(fileURLWithPath: "/Users/test/Applications", isDirectory: true)
                ]
            )
        )
    }

    func testDoesNotSupportLaunchAtLoginOutsideApplicationsFolders() {
        XCTAssertFalse(
            supportsLaunchAtLoginManagement(
                appURL: URL(fileURLWithPath: "/Users/test/Downloads/AgentUsageBar.app"),
                installDirectories: [
                    URL(fileURLWithPath: "/Applications", isDirectory: true),
                    URL(fileURLWithPath: "/Users/test/Applications", isDirectory: true)
                ]
            )
        )
    }

    func testObfuscateEmailMasksLocalAndDomain() {
        XCTAssertEqual(obfuscateEmail("doug@example.com"), "d•••@e••••••.com")
        XCTAssertEqual(obfuscateEmail("a@b.co"), "a@b.co")
        XCTAssertEqual(obfuscateEmail("jane.doe@mail.example.org"), "j•••••••@m•••.e••••••.org")
    }

    func testObfuscateEmailHandlesNonEmailStrings() {
        XCTAssertEqual(obfuscateEmail("plaintext"), "•••••••••")
        XCTAssertEqual(obfuscateEmail(""), "••••")
    }

    func testOpenAICredentialStatusText() {
        let expiry = Date().addingTimeInterval(4 * 86_400 + 60)
        XCTAssertEqual(
            openAICredentialStatusText(source: .codexCLI, expiry: expiry),
            "Using Codex CLI login (expires in 4d)"
        )
        XCTAssertEqual(
            openAICredentialStatusText(source: .pasted, expiry: nil),
            "Using pasted token"
        )
        XCTAssertEqual(
            openAICredentialStatusText(source: .none, expiry: nil),
            "Run `codex login` to connect without pasting a token."
        )
    }

    func testCursorCredentialStatusText() {
        let expiry = Date().addingTimeInterval(9 * 86_400 + 60)
        XCTAssertEqual(
            cursorCredentialStatusText(source: .cursorCLI, expiry: expiry),
            "Using Cursor CLI login (expires in 9d)"
        )
        XCTAssertEqual(
            cursorCredentialStatusText(source: .pasted, expiry: nil),
            "Using pasted token"
        )
        XCTAssertEqual(
            cursorCredentialStatusText(source: .none, expiry: nil),
            "Run `cursor-agent login` to connect without pasting a token."
        )
    }

    func testPastedTokenDisclosureTitleFollowsTheActiveSource() {
        XCTAssertEqual(openAIPastedTokenDisclosureTitle(source: .pasted), "Manage pasted token")
        XCTAssertEqual(openAIPastedTokenDisclosureTitle(source: .codexCLI), "Use a pasted token instead")
        XCTAssertEqual(openAIPastedTokenDisclosureTitle(source: .environment), "Use a pasted token instead")
        XCTAssertEqual(openAIPastedTokenDisclosureTitle(source: .none), "Use a pasted token")

        XCTAssertEqual(cursorPastedTokenDisclosureTitle(source: .pasted), "Manage pasted token")
        XCTAssertEqual(cursorPastedTokenDisclosureTitle(source: .cursorCLI), "Use a pasted token instead")
        XCTAssertEqual(cursorPastedTokenDisclosureTitle(source: .environment), "Use a pasted token instead")
        XCTAssertEqual(cursorPastedTokenDisclosureTitle(source: .none), "Use a pasted token")
    }

    func testUsageFillModeAppearanceDefaults() {
        XCTAssertEqual(UsagePresentationDefaults.fillModeKey, "usageFillMode")
        XCTAssertEqual(UsagePresentationDefaults.fillMode, .drain)
        XCTAssertEqual(UsageFillMode.allCases.map(\.rawValue), ["fill", "drain"])
    }
}
