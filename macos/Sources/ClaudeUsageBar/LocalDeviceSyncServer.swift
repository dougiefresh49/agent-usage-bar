import Foundation
import Network

struct LocalHTTPRequest {
    let method: String
    let path: String
    let queryItems: [String: String]
    let body: Data
}

struct LocalHTTPResponse {
    let status: Int
    let body: Data

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> LocalHTTPResponse {
        let body = (try? JSONEncoder.deviceSyncEncoder.encode(value)) ?? Data()
        return LocalHTTPResponse(status: status, body: body)
    }
}

final class LocalDeviceSyncServer {
    static let port: UInt16 = 48_321
    typealias Handler = @Sendable (LocalHTTPRequest) async -> LocalHTTPResponse

    private let queue = DispatchQueue(label: "AgentUsageBar.DeviceSyncServer")
    private let handler: Handler
    private var listener: NWListener?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() throws {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: Self.port) else {
            throw DeviceSyncError.serverUnavailable
        }
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[DeviceSync] Local server failed: \(error)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data {
                buffer.append(data)
            }

            if let request = Self.parseRequest(buffer) {
                Task {
                    let response = await self.handler(request)
                    self.send(response, on: connection)
                }
                return
            }

            if error != nil || isComplete || buffer.count > 65_536 {
                connection.cancel()
                return
            }
            receive(on: connection, accumulated: buffer)
        }
    }

    private func send(_ response: LocalHTTPResponse, on connection: NWConnection) {
        let reason = switch response.status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 409: "Conflict"
        case 410: "Gone"
        default: "Error"
        }
        var data = Data(
            """
            HTTP/1.1 \(response.status) \(reason)\r
            Content-Type: application/json\r
            Content-Length: \(response.body.count)\r
            Connection: close\r
            \r
            """.utf8
        )
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func parseRequest(_ data: Data) -> LocalHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let header = String(
                data: data[..<headerRange.lowerBound],
                encoding: .utf8
              ) else {
            return nil
        }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let contentLength = lines
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) }
            ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))

        let components = URLComponents(string: String(parts[1]))
        let path = components?.path ?? String(parts[1])
        var query = [String: String]()
        for item in components?.queryItems ?? [] {
            if let value = item.value {
                query[item.name] = value
            }
        }
        return LocalHTTPRequest(
            method: String(parts[0]),
            path: path,
            queryItems: query,
            body: body
        )
    }
}
