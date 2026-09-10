import XCTest
@testable import AgentUsageBar

final class JWTClaimsTests: XCTestCase {
    func testExpiryReadsKnownExpClaim() throws {
        let exp: TimeInterval = 1_893_456_000
        let token = try makeUnsignedJWT(payloadJSON: #"{"exp":\#(Int(exp)),"sub":"test"}"#)

        let expiry = JWTClaims.expiry(of: token)

        XCTAssertEqual(expiry, Date(timeIntervalSince1970: exp))
    }

    func testExpiryReturnsNilForGarbage() {
        XCTAssertNil(JWTClaims.expiry(of: "not-a-jwt"))
        XCTAssertNil(JWTClaims.expiry(of: "abc.!!!not-base64!!!.xyz"))
        XCTAssertNil(JWTClaims.expiry(of: ""))
    }

    private func makeUnsignedJWT(payloadJSON: String) throws -> String {
        let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8).base64URLEncodedString()
        let payload = Data(payloadJSON.utf8).base64URLEncodedString()
        return "\(header).\(payload).sig"
    }
}
