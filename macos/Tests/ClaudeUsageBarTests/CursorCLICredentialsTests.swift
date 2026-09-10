import XCTest
@testable import AgentUsageBar

final class CursorCLICredentialsTests: XCTestCase {
    func testLoadReturnsCredentialsWhenRunnerReturnsToken() {
        let credentials = CursorCLIKeychain.load { executable, arguments in
            XCTAssertEqual(executable, "/usr/bin/security")
            XCTAssertEqual(
                arguments,
                ["find-generic-password", "-s", "cursor-access-token", "-a", "cursor-user", "-w"]
            )
            return "  fake-cursor-access-token\n"
        }

        XCTAssertEqual(credentials?.accessToken, "fake-cursor-access-token")
    }

    func testLoadReturnsNilWhenRunnerReturnsEmptyString() {
        let credentials = CursorCLIKeychain.load { _, _ in "" }
        XCTAssertNil(credentials)
    }

    func testLoadReturnsNilWhenRunnerReturnsWhitespaceOnly() {
        let credentials = CursorCLIKeychain.load { _, _ in "  \n\t  " }
        XCTAssertNil(credentials)
    }

    func testLoadReturnsNilWhenRunnerThrows() {
        struct StubError: Error {}

        let credentials = CursorCLIKeychain.load { _, _ in
            throw StubError()
        }

        XCTAssertNil(credentials)
    }
}
