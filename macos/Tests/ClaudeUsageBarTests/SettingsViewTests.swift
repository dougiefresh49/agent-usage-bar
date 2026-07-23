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
}
