import Foundation

enum JWTClaims {
    static func expiry(of token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }

        let payloadSegment = String(segments[1])
        guard let payloadData = Data(base64URLEncoded: payloadSegment) else {
            return nil
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: payloadData),
              let exp = payload.exp else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    private struct Payload: Decodable {
        let exp: TimeInterval?
    }
}
