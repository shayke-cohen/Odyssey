import OdysseyLocalAgentCore
import Foundation
import Network

final class LocalAgentHTTPServer {
    private let listener: NWListener
    private let service: HostService
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(port: Int, service: HostService) throws {
        self.listener = try NWListener(using: .tcp, on: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port)))
        self.service = service
        self.encoder.outputFormatting = [.sortedKeys]
    }

    func run() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: .global(qos: .userInitiated))
            Task {
                await self.handle(connection: connection)
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        while true {
            try await Task.sleep(for: .seconds(60))
        }
    }

    private func handle(connection: NWConnection) async {
        do {
            guard let requestData = try await receiveRequest(on: connection),
                  let request = parseRequest(requestData) else {
                await send(status: 400, body: ["error": "invalid_request"], over: connection)
                return
            }

            let response = try await route(request: request)
            await send(status: response.status, body: response.body, over: connection)
        } catch {
            await send(status: 500, body: ["error": error.localizedDescription], over: connection)
        }
    }

    private func receiveRequest(on connection: NWConnection) async throws -> Data? {
        var buffer = Data()
        var expectedBodyLength: Int?

        while true {
            let chunk = try await receiveChunk(on: connection)
            guard let chunk else {
                return buffer.isEmpty ? nil : buffer
            }

            buffer.append(chunk)

            if expectedBodyLength == nil,
               let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)),
               let headerText = String(data: buffer[..<headerRange.lowerBound], encoding: .utf8) {
                expectedBodyLength = contentLength(from: headerText) ?? 0
            }

            if let expectedBodyLength,
               let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let bodyStart = headerRange.upperBound
                let receivedBodyLength = buffer.count - bodyStart
                if receivedBodyLength >= expectedBodyLength {
                    return buffer
                }
            }
        }
    }

    private func receiveChunk(on connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }

                if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    private func parseRequest(_ data: Data) -> (method: String, path: String, body: [String: Any])? {
        guard let text = String(data: data, encoding: .utf8),
              let headerRange = text.range(of: "\r\n\r\n") else {
            return nil
        }

        let header = String(text[..<headerRange.lowerBound])
        let body = String(text[headerRange.upperBound...])
        let requestLine = header.split(separator: "\r\n").first?.split(separator: " ")
        guard let requestLine, requestLine.count >= 2 else { return nil }
        let method = String(requestLine[0])
        let path = String(requestLine[1])
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]
        return (method, path, json)
    }

    private func contentLength(from headerText: String) -> Int? {
        for line in headerText.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    private func route(request: (method: String, path: String, body: [String: Any])) async throws -> (status: Int, body: [String: Any]) {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let segments = path.split(separator: "/").map(String.init)

        switch (request.method, path) {
        case ("GET", "/health"):
            return (200, ["status": "ok"])
        case ("GET", "/v1/providers"):
            var probeResults = [[String: Any]]()
            for provider in LocalAgentProvider.allCases {
                probeResults.append(
                    try await call(
                        method: LocalAgentHostMethod.providerProbe.rawValue,
                        params: ["provider": provider.rawValue]
                    )
                )
            }
            return (200, ["providers": probeResults])
        case ("GET", "/v1/mlx/models"):
            return (200, try await call(method: LocalAgentHostMethod.mlxModelsList.rawValue, params: request.body))
        case ("POST", "/v1/mlx/models/install"):
            return (200, try await call(method: LocalAgentHostMethod.mlxModelInstall.rawValue, params: request.body))
        case ("POST", "/v1/mlx/models/delete"):
            return (200, try await call(method: LocalAgentHostMethod.mlxModelDelete.rawValue, params: request.body))
        case ("POST", "/v1/provider/probe"):
            return (200, try await call(method: LocalAgentHostMethod.providerProbe.rawValue, params: request.body))
        case ("POST", "/v1/sessions"):
            return (200, try await call(method: LocalAgentHostMethod.sessionCreate.rawValue, params: request.body))
        case ("POST", "/v1/run"):
            return (200, try await call(method: LocalAgentHostMethod.sessionRun.rawValue, params: request.body))
        default:
            if segments.count == 4, segments[0] == "v1", segments[1] == "sessions", request.method == "GET", segments[3] == "transcript" {
                return (200, try await call(
                    method: LocalAgentHostMethod.sessionTranscript.rawValue,
                    params: ["sessionId": segments[2]]
                ))
            }

            if segments.count == 4, segments[0] == "v1", segments[1] == "sessions", request.method == "GET", segments[3] == "tools" {
                return (200, try await call(
                    method: LocalAgentHostMethod.sessionTools.rawValue,
                    params: ["sessionId": segments[2]]
                ))
            }

            if segments.count == 4, segments[0] == "v1", segments[1] == "sessions", request.method == "POST" {
                return try await routeSessionAction(
                    sessionId: segments[2],
                    action: segments[3],
                    body: request.body
                )
            }

            return (404, ["error": "not_found", "path": path])
        }
    }

    private func routeSessionAction(
        sessionId: String,
        action: String,
        body: [String: Any]
    ) async throws -> (status: Int, body: [String: Any]) {
        switch action {
        case "message":
            return (200, try await call(
                method: LocalAgentHostMethod.sessionMessage.rawValue,
                params: body.merging(["sessionId": sessionId]) { _, new in new }
            ))
        case "resume":
            return (200, try await call(
                method: LocalAgentHostMethod.sessionResume.rawValue,
                params: body.merging(["sessionId": sessionId]) { _, new in new }
            ))
        case "pause":
            return (200, try await call(
                method: LocalAgentHostMethod.sessionPause.rawValue,
                params: body.merging(["sessionId": sessionId]) { _, new in new }
            ))
        case "fork":
            return (200, try await call(
                method: LocalAgentHostMethod.sessionFork.rawValue,
                params: body.merging(["parentSessionId": sessionId]) { _, new in new }
            ))
        default:
            return (404, ["error": "not_found", "path": "/v1/sessions/\(sessionId)/\(action)"])
        }
    }

    private func call(method: String, params: [String: Any]) async throws -> [String: Any] {
        let result = try await service.handle(method: method, params: params)
        return result as? [String: Any] ?? ["result": result]
    }

    private func send(status: Int, body: [String: Any], over connection: NWConnection) async {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])) ?? Data()
        var header = "HTTP/1.1 \(status) \(reasonPhrase(for: status))\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Connection: close\r\n\r\n"
        let packet = Data(header.utf8) + data
        await withCheckedContinuation { continuation in
            connection.send(content: packet, completion: .contentProcessed { _ in
                connection.cancel()
                continuation.resume()
            })
        }
    }

    private func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        default: "Internal Server Error"
        }
    }
}
