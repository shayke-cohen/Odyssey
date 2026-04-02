import Foundation

struct MCPListedTool: Sendable, Equatable {
    var name: String
    var description: String
    var inputSchema: [String: String]
}

actor MCPClient {
    private let server: LocalAgentMCPServer
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID = 1
    private var buffer = Data()
    private var started = false

    init(server: LocalAgentMCPServer) async throws {
        self.server = server
        self.process = Process()
        self.stdinPipe = Pipe()
        self.stdoutPipe = Pipe()
        self.stderrPipe = Pipe()
        try await start()
    }

    func listTools() async throws -> [MCPListedTool] {
        let payload = try await request(method: "tools/list", params: [:])
        let tools = payload["tools"] as? [[String: Any]] ?? []
        return tools.map { tool in
            let schema = tool["inputSchema"] as? [String: Any]
            let properties = schema?["properties"] as? [String: [String: Any]] ?? [:]
            let inputSchema = properties.mapValues { property in
                property["type"] as? String ?? "string"
            }
            return MCPListedTool(
                name: tool["name"] as? String ?? "unknown",
                description: tool["description"] as? String ?? "",
                inputSchema: inputSchema
            )
        }
    }

    func callTool(named name: String, arguments: [String: DynamicValue]) async throws -> ToolExecutionResult {
        let payload = try await request(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": try dictionary(from: arguments),
            ]
        )

        let content = payload["content"] as? [[String: Any]] ?? []
        let output = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        let isError = payload["isError"] as? Bool ?? false
        return ToolExecutionResult(success: !isError, output: output)
    }

    private func start() async throws {
        guard !started else { return }
        guard let command = server.command else {
            throw NSError(domain: "ClaudeStudioLocalAgent.MCPClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Only stdio MCP servers are supported right now"
            ])
        }

        process.executableURL = URL(fileURLWithPath: resolveExecutable(command))
        process.arguments = server.args ?? []
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = mergedEnvironment(custom: server.env ?? [:])

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task {
                await self?.consume(data: data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [server] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fputs("[LocalAgent MCP \(server.name)] \(text)", stderr)
            }
        }

        try process.run()
        started = true

        _ = try await request(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:]],
            "clientInfo": [
                "name": "ClaudeStudioLocalAgent",
                "version": "0.1.0",
            ],
        ])
    }

    private func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextID
        nextID += 1

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try send([
                    "jsonrpc": "2.0",
                    "id": id,
                    "method": method,
                    "params": params,
                ])
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func send(_ payload: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let header = "Content-Length: \(body.count)\r\n\r\n"
        stdinPipe.fileHandleForWriting.write(Data(header.utf8))
        stdinPipe.fileHandleForWriting.write(body)
    }

    private func consume(data: Data) {
        buffer.append(data)
        while let message = nextMessage() {
            handle(message: message)
        }
    }

    private func nextMessage() -> [String: Any]? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.range(of: separator) else { return nil }
        let headerData = buffer[..<headerRange.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else {
            buffer.removeSubrange(..<headerRange.upperBound)
            return nil
        }

        let contentLength = header
            .split(separator: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .first

        guard let contentLength else {
            buffer.removeSubrange(..<headerRange.upperBound)
            return nil
        }

        let bodyStart = headerRange.upperBound
        guard buffer.count >= bodyStart + contentLength else { return nil }

        let body = buffer[bodyStart..<(bodyStart + contentLength)]
        buffer.removeSubrange(..<(bodyStart + contentLength))

        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func handle(message: [String: Any]) {
        guard let id = message["id"] as? Int,
              let continuation = pending.removeValue(forKey: id) else {
            return
        }

        if let error = message["error"] as? [String: Any] {
            continuation.resume(
                throwing: NSError(domain: "ClaudeStudioLocalAgent.MCPClient", code: error["code"] as? Int ?? -1, userInfo: [
                    NSLocalizedDescriptionKey: error["message"] as? String ?? "Unknown MCP error"
                ])
            )
            return
        }

        continuation.resume(returning: message["result"] as? [String: Any] ?? [:])
    }

    private func resolveExecutable(_ command: String) -> String {
        if command.contains("/") {
            return command
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
        for entry in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return command
    }

    private func mergedEnvironment(custom: [String: String]) -> [String: String] {
        ProcessInfo.processInfo.environment.merging(custom) { _, new in new }
    }

    private func dictionary(from values: [String: DynamicValue]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in values {
            result[key] = try DynamicValueWrapper(value: value).foundationValue()
        }
        return result
    }
}

private struct DynamicValueWrapper {
    let value: DynamicValue

    func foundationValue() throws -> Any {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .bool(let bool):
            return bool
        case .object(let object):
            return try object.mapValues { try DynamicValueWrapper(value: $0).foundationValue() }
        case .array(let array):
            return try array.map { try DynamicValueWrapper(value: $0).foundationValue() }
        case .null:
            return NSNull()
        }
    }
}
