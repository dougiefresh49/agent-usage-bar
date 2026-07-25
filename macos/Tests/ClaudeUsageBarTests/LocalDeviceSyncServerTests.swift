import XCTest
@testable import AgentUsageBar

final class LocalDeviceSyncServerTests: XCTestCase {
    func testSerializedResponseUsesCompleteHTTPHeaderTerminator() throws {
        let body = Data(#"{"status":"pending","confirmationCode":"954893"}"#.utf8)

        let response = LocalDeviceSyncServer.serializedResponse(
            LocalHTTPResponse(status: 202, body: body)
        )

        let separator = Data("\r\n\r\n".utf8)
        let separatorRange = try XCTUnwrap(response.range(of: separator))
        let header = try XCTUnwrap(
            String(data: response[..<separatorRange.lowerBound], encoding: .utf8)
        )

        XCTAssertEqual(
            header,
            """
            HTTP/1.1 202 Accepted\r
            Content-Type: application/json\r
            Content-Length: \(body.count)\r
            Connection: close
            """
        )
        XCTAssertEqual(response[separatorRange.upperBound...], body[...])
    }
}
