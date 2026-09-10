import XCTest
@testable import AgentUsageBar

@MainActor
final class OpenAIResetCreditRedeemerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        RedeemerMockURLProtocol.handler = nil
        suiteName = "OpenAIResetCreditRedeemerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        RedeemerMockURLProtocol.handler = nil
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUUIDv5MatchesInteroperableDNSVector() {
        // SHA-1 UUIDv5 matching Python uuid.uuid5(NAMESPACE_DNS, "www.example.com").
        // Issue #46 cited 2ed6657d-e927-568b-95e3-46f7c8c2c13d, which does not match the
        // RFC 4122 algorithm; 2ed6657d-e927-568b-95e1-2665a8aea6a2 is the cross-platform value.
        let dnsNamespace = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        let uuid = UUIDv5.make(namespace: dnsNamespace, name: "www.example.com")
        XCTAssertEqual(
            uuid,
            UUID(uuidString: "2ed6657d-e927-568b-95e1-2665a8aea6a2")
        )
    }

    func testRequestIDIsDeterministicForSameInputs() {
        let first = OpenAIResetCreditRedemption.requestID(
            accountID: "acct-1",
            creditID: "credit-9"
        )
        let second = OpenAIResetCreditRedemption.requestID(
            accountID: "acct-1",
            creditID: "credit-9"
        )
        XCTAssertEqual(first, second)

        let local = OpenAIResetCreditRedemption.requestID(
            accountID: nil,
            creditID: "credit-9"
        )
        let explicitLocal = OpenAIResetCreditRedemption.requestID(
            accountID: "local",
            creditID: "credit-9"
        )
        XCTAssertEqual(local, explicitLocal)
        XCTAssertNotEqual(first, local)

        let expected = UUIDv5.make(
            namespace: OpenAIResetCreditRedemption.namespace,
            name: "acct-1:credit-9"
        )
        XCTAssertEqual(first, expected)
    }

    func testRequestHeadersAndBody() throws {
        let endpoint = OpenAIResetCreditRedemption.consumeEndpoint
        let request = OpenAIResetCreditRedemption.request(
            endpoint: endpoint,
            token: "tok-test",
            accountID: "acct-42",
            creditID: "cred-7"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.timeoutInterval, 20)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "codex-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Originator"), "Codex Desktop")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Chatgpt-Account-Id"), "acct-42")

        let body = try XCTUnwrap(Self.jsonBody(for: request))
        let expectedID = OpenAIResetCreditRedemption.requestID(
            accountID: "acct-42",
            creditID: "cred-7"
        )
        XCTAssertEqual(body["credit_id"], "cred-7")
        XCTAssertEqual(body["redeem_request_id"], expectedID.uuidString.lowercased())

        let withoutAccount = OpenAIResetCreditRedemption.request(
            endpoint: endpoint,
            token: "tok-test",
            accountID: nil,
            creditID: "cred-7"
        )
        XCTAssertNil(withoutAccount.value(forHTTPHeaderField: "Chatgpt-Account-Id"))
    }

    func testEachOutcomeDecodesAndExposesUserMessage() throws {
        let cases: [(String, OpenAIResetCreditOutcome, String)] = [
            ("reset", .reset, "Limits reset"),
            ("nothing_to_reset", .nothingToReset, "Nothing to reset yet"),
            ("no_credit", .noCredit, "No credit available"),
            ("already_redeemed", .alreadyRedeemed, "Already redeemed")
        ]

        for (raw, expected, message) in cases {
            let rawData = Data("\"\(raw)\"".utf8)
            let decoded = try JSONDecoder().decode(OpenAIResetCreditOutcome.self, from: rawData)

            let envelopeData = Data("{\"code\":\"\(raw)\"}".utf8)
            struct Envelope: Decodable {
                let code: OpenAIResetCreditOutcome
            }
            let envelope = try JSONDecoder().decode(Envelope.self, from: envelopeData)
            XCTAssertEqual(envelope.code, expected)
            XCTAssertEqual(decoded, expected)
            XCTAssertEqual(expected.userMessage, message)
            XCTAssertEqual(expected.rawValue, raw)
        }
    }

    func testRedeemDecodesEachOutcome() async throws {
        let outcomes: [(String, OpenAIResetCreditOutcome)] = [
            ("reset", .reset),
            ("nothing_to_reset", .nothingToReset),
            ("no_credit", .noCredit),
            ("already_redeemed", .alreadyRedeemed)
        ]

        for (raw, expected) in outcomes {
            defaults.removePersistentDomain(forName: suiteName)
            RedeemerMockURLProtocol.handler = { request in
                XCTAssertEqual(request.url, OpenAIResetCreditRedemption.consumeEndpoint)
                return try Self.httpResponse(
                    url: request.url!,
                    statusCode: 200,
                    body: "{\"code\":\"\(raw)\"}"
                )
            }

            let redeemer = OpenAIResetCreditRedeemer(
                session: makeSession(),
                defaults: defaults
            )
            let outcome = try await redeemer.redeem(
                token: "tok",
                accountID: "acct",
                creditID: "credit-\(raw)"
            )
            XCTAssertEqual(outcome, expected)
            XCTAssertNil(defaults.data(forKey: "openAIResetCreditPendingAttempt"))
        }
    }

    func testPendingAttemptSurvivesFailedSendAndIsReused() async throws {
        let creditID = "credit-retry"
        // First attempt with unknown account so the stored id is the "local" form.
        let expectedID = OpenAIResetCreditRedemption.requestID(
            accountID: nil,
            creditID: creditID
        )
        var seenRequestIDs: [String] = []

        RedeemerMockURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }

        let firstRedeemer = OpenAIResetCreditRedeemer(
            session: makeSession(),
            defaults: defaults
        )

        do {
            _ = try await firstRedeemer.redeem(
                token: "tok",
                accountID: nil,
                creditID: creditID
            )
            XCTFail("Expected timeout")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }

        let pendingData = try XCTUnwrap(defaults.data(forKey: "openAIResetCreditPendingAttempt"))
        let pending = try JSONDecoder().decode([String: UUID].self, from: pendingData)
        XCTAssertEqual(pending[creditID], expectedID)

        RedeemerMockURLProtocol.handler = { request in
            let body = try XCTUnwrap(Self.jsonBody(for: request))
            if let id = body["redeem_request_id"] {
                seenRequestIDs.append(id)
            }
            return try Self.httpResponse(
                url: request.url!,
                statusCode: 200,
                body: #"{"code":"reset"}"#
            )
        }

        // New instance, account now known: must still send the original stored request id.
        let retryRedeemer = OpenAIResetCreditRedeemer(
            session: makeSession(),
            defaults: defaults
        )
        let outcome = try await retryRedeemer.redeem(
            token: "tok",
            accountID: "acct-now-known",
            creditID: creditID
        )
        XCTAssertEqual(outcome, .reset)
        XCTAssertEqual(seenRequestIDs, [expectedID.uuidString.lowercased()])
        XCTAssertNotEqual(
            expectedID,
            OpenAIResetCreditRedemption.requestID(
                accountID: "acct-now-known",
                creditID: creditID
            )
        )
        XCTAssertNil(defaults.data(forKey: "openAIResetCreditPendingAttempt"))
    }

    func testFailedCreditAThenCreditBSucceeds() async throws {
        // A later credit may proceed; clearing B must not drop A's pending entry.
        RedeemerMockURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }

        let redeemer = OpenAIResetCreditRedeemer(
            session: makeSession(),
            defaults: defaults
        )
        let expectedAID = OpenAIResetCreditRedemption.requestID(
            accountID: "acct",
            creditID: "credit-a"
        )

        do {
            _ = try await redeemer.redeem(
                token: "tok",
                accountID: "acct",
                creditID: "credit-a"
            )
            XCTFail("Expected timeout")
        } catch is URLError {
            // Pending for credit-a remains in the map.
        }

        var seenCreditIDs: [String] = []
        RedeemerMockURLProtocol.handler = { request in
            let body = try XCTUnwrap(Self.jsonBody(for: request))
            if let creditID = body["credit_id"] {
                seenCreditIDs.append(creditID)
            }
            return try Self.httpResponse(
                url: request.url!,
                statusCode: 200,
                body: #"{"code":"reset"}"#
            )
        }

        let outcome = try await redeemer.redeem(
            token: "tok",
            accountID: "acct",
            creditID: "credit-b"
        )
        XCTAssertEqual(outcome, .reset)
        XCTAssertEqual(seenCreditIDs, ["credit-b"])

        let pendingData = try XCTUnwrap(defaults.data(forKey: "openAIResetCreditPendingAttempt"))
        let pending = try JSONDecoder().decode([String: UUID].self, from: pendingData)
        XCTAssertEqual(pending["credit-a"], expectedAID)
        XCTAssertNil(pending["credit-b"])
    }

    func testFailedCreditAThenCreditBLeavesAReusable() async throws {
        // Failed send for A, then send for B, must leave A's request id reusable.
        let expectedAID = OpenAIResetCreditRedemption.requestID(
            accountID: "acct",
            creditID: "credit-a"
        )
        var seenRequestIDs: [String] = []

        RedeemerMockURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }

        let redeemer = OpenAIResetCreditRedeemer(
            session: makeSession(),
            defaults: defaults
        )

        do {
            _ = try await redeemer.redeem(
                token: "tok",
                accountID: "acct",
                creditID: "credit-a"
            )
            XCTFail("Expected timeout")
        } catch is URLError {
            // Keep A's pending entry.
        }

        RedeemerMockURLProtocol.handler = { request in
            let body = try XCTUnwrap(Self.jsonBody(for: request))
            if let id = body["redeem_request_id"] {
                seenRequestIDs.append(id)
            }
            return try Self.httpResponse(
                url: request.url!,
                statusCode: 200,
                body: #"{"code":"reset"}"#
            )
        }

        let bOutcome = try await redeemer.redeem(
            token: "tok",
            accountID: "acct",
            creditID: "credit-b"
        )
        XCTAssertEqual(bOutcome, .reset)

        let aOutcome = try await redeemer.redeem(
            token: "tok",
            accountID: "acct",
            creditID: "credit-a"
        )
        XCTAssertEqual(aOutcome, .reset)
        XCTAssertEqual(
            seenRequestIDs.last,
            expectedAID.uuidString.lowercased()
        )
        XCTAssertNil(defaults.data(forKey: "openAIResetCreditPendingAttempt"))
    }

    func testSingleFlightThrowsWhileRedeeming() async throws {
        let started = expectation(description: "first request started")
        let gate = DispatchSemaphore(value: 0)

        RedeemerMockURLProtocol.handler = { request in
            started.fulfill()
            gate.wait()
            return try Self.httpResponse(
                url: request.url!,
                statusCode: 200,
                body: #"{"code":"reset"}"#
            )
        }

        let redeemer = OpenAIResetCreditRedeemer(
            session: makeSession(),
            defaults: defaults
        )

        let first = Task {
            try await redeemer.redeem(
                token: "tok",
                accountID: "acct",
                creditID: "credit-flight"
            )
        }

        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(redeemer.isRedeeming)

        do {
            _ = try await redeemer.redeem(
                token: "tok",
                accountID: "acct",
                creditID: "credit-flight"
            )
            XCTFail("Expected inFlight")
        } catch let error as OpenAIResetCreditError {
            XCTAssertEqual(error, .inFlight)
        }

        gate.signal()
        let outcome = try await first.value
        XCTAssertEqual(outcome, .reset)
        XCTAssertFalse(redeemer.isRedeeming)
    }

    func testNon2xxMapsToHTTPErrorAndKeepsPending() async throws {
        RedeemerMockURLProtocol.handler = { request in
            try Self.httpResponse(url: request.url!, statusCode: 503, body: "nope")
        }

        let redeemer = OpenAIResetCreditRedeemer(
            session: makeSession(),
            defaults: defaults
        )

        do {
            _ = try await redeemer.redeem(
                token: "tok",
                accountID: "acct",
                creditID: "credit-http"
            )
            XCTFail("Expected http error")
        } catch let error as OpenAIResetCreditError {
            XCTAssertEqual(error, .http(status: 503))
        }

        XCTAssertNotNil(defaults.data(forKey: "openAIResetCreditPendingAttempt"))
    }

    func testUndecodableBodyMapsToInvalidResponse() async throws {
        RedeemerMockURLProtocol.handler = { request in
            try Self.httpResponse(url: request.url!, statusCode: 200, body: #"{"nope":true}"#)
        }

        let redeemer = OpenAIResetCreditRedeemer(
            session: makeSession(),
            defaults: defaults
        )

        do {
            _ = try await redeemer.redeem(
                token: "tok",
                accountID: "acct",
                creditID: "credit-bad"
            )
            XCTFail("Expected invalidResponse")
        } catch let error as OpenAIResetCreditError {
            XCTAssertEqual(error, .invalidResponse)
        }

        XCTAssertNotNil(defaults.data(forKey: "openAIResetCreditPendingAttempt"))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedeemerMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonBody(for request: URLRequest) -> [String: String]? {
        guard let body = bodyData(for: request),
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: String] else {
            return nil
        }
        return object
    }

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }
        return data.isEmpty ? nil : data
    }

    private static func httpResponse(
        url: URL,
        statusCode: Int,
        body: String
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, Data(body.utf8))
    }
}

private final class RedeemerMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
