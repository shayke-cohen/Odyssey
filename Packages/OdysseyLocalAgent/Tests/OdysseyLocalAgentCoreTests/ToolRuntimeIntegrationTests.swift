@testable import OdysseyLocalAgentCore
import Foundation
import Network
import XCTest

final class ToolRuntimeIntegrationTests: XCTestCase {
    private var tempDirectory: URL!
    private var originalPath: String?
    private var originalWebSearchTemplate: String?
    private var originalLegacyWebSearchTemplate: String?
    private var originalMLXRunner: String?
    private var originalLegacyMLXRunner: String?
    private var originalMLXDownloadDirectory: String?
    private var originalLegacyMLXDownloadDirectory: String?
    private var originalLogFile: String?

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        originalPath = ProcessInfo.processInfo.environment["PATH"]
        originalWebSearchTemplate = ProcessInfo.processInfo.environment["ODYSSEY_WEB_SEARCH_URL_TEMPLATE"]
        originalLegacyWebSearchTemplate = ProcessInfo.processInfo.environment["CLAUDESTUDIO_WEB_SEARCH_URL_TEMPLATE"]
        originalMLXRunner = ProcessInfo.processInfo.environment["ODYSSEY_MLX_RUNNER"]
        originalLegacyMLXRunner = ProcessInfo.processInfo.environment["CLAUDESTUDIO_MLX_RUNNER"]
        originalMLXDownloadDirectory = ProcessInfo.processInfo.environment["ODYSSEY_MLX_DOWNLOAD_DIR"]
        originalLegacyMLXDownloadDirectory = ProcessInfo.processInfo.environment["CLAUDESTUDIO_MLX_DOWNLOAD_DIR"]
        originalLogFile = ProcessInfo.processInfo.environment["LOGFILE"]
    }

    override func tearDown() {
        restoreEnvironment("ODYSSEY_WEB_SEARCH_URL_TEMPLATE", value: originalWebSearchTemplate)
        restoreEnvironment("CLAUDESTUDIO_WEB_SEARCH_URL_TEMPLATE", value: originalLegacyWebSearchTemplate)
        restoreEnvironment("ODYSSEY_MLX_RUNNER", value: originalMLXRunner)
        restoreEnvironment("CLAUDESTUDIO_MLX_RUNNER", value: originalLegacyMLXRunner)
        restoreEnvironment("ODYSSEY_MLX_DOWNLOAD_DIR", value: originalMLXDownloadDirectory)
        restoreEnvironment("CLAUDESTUDIO_MLX_DOWNLOAD_DIR", value: originalLegacyMLXDownloadDirectory)
        restoreEnvironment("PATH", value: originalPath)
        restoreEnvironment("LOGFILE", value: originalLogFile)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        originalPath = nil
        originalWebSearchTemplate = nil
        originalLegacyWebSearchTemplate = nil
        originalMLXRunner = nil
        originalLegacyMLXRunner = nil
        originalMLXDownloadDirectory = nil
        originalLegacyMLXDownloadDirectory = nil
        originalLogFile = nil
        super.tearDown()
    }

    func testWebSearchToolUsesConfiguredEndpointAndFormatsResults() async throws {
        let server = try TestHTTPServer { url in
            XCTAssertEqual(url.path, "/search")
            XCTAssertEqual(url.query, "q=example%20domain")
            return .json(
                """
                {
                  "AbstractText": "Example summary",
                  "RelatedTopics": [
                    {
                      "Text": "Example Domain",
                      "FirstURL": "https://example.com"
                    }
                  ]
                }
                """
            )
        }
        let port = try await server.start()
        defer { server.stop() }

        let template = "http://127.0.0.1:\(port)/search?q=%QUERY%"
        setenv("ODYSSEY_WEB_SEARCH_URL_TEMPLATE", template, 1)
        setenv("CLAUDESTUDIO_WEB_SEARCH_URL_TEMPLATE", template, 1)

        let (executor, context) = try await makeExecutor(
            workingDirectory: tempDirectory.path,
            rules: ["WebSearch"]
        )
        let result = try await executor.execute(
            toolName: "web_search",
            arguments: ["query": .string("example domain")],
            context: context
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Search results for: example domain"))
        XCTAssertTrue(result.output.contains("Summary: Example summary"))
        XCTAssertTrue(result.output.contains("Example Domain"))
    }

    func testFetchURLToolReturnsHTMLFromLocalServer() async throws {
        let server = try TestHTTPServer { url in
            XCTAssertEqual(url.path, "/page")
            return .html("<html><head><title>Local Agent</title></head><body><h1>Hello</h1></body></html>")
        }
        let port = try await server.start()
        defer { server.stop() }

        let (executor, context) = try await makeExecutor(
            workingDirectory: tempDirectory.path,
            rules: ["WebFetch"]
        )
        let result = try await executor.execute(
            toolName: "fetch_url",
            arguments: ["url": .string("http://127.0.0.1:\(port)/page")],
            context: context
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("HTTP 200"))
        XCTAssertTrue(result.output.contains("<title>Local Agent</title>"))
    }

    func testToolExecutorWritesReadsAndReplacesFiles() async throws {
        let (executor, context) = try await makeExecutor(
            workingDirectory: tempDirectory.path,
            rules: ["Read", "Write(*.md)"]
        )

        let writeResult = try await executor.execute(
            toolName: "write_file",
            arguments: [
                "path": .string("notes.md"),
                "content": .string("hello world"),
            ],
            context: context
        )
        XCTAssertTrue(writeResult.success)

        let readResult = try await executor.execute(
            toolName: "read_file",
            arguments: ["path": .string("notes.md")],
            context: context
        )
        XCTAssertEqual(readResult.output, "hello world")

        let replaceResult = try await executor.execute(
            toolName: "replace_in_file",
            arguments: [
                "path": .string("notes.md"),
                "find": .string("world"),
                "replace": .string("odyssey"),
            ],
            context: context
        )
        XCTAssertTrue(replaceResult.success)

        let updated = try await executor.execute(
            toolName: "read_file",
            arguments: ["path": .string("notes.md")],
            context: context
        )
        XCTAssertEqual(updated.output, "hello odyssey")
    }

    func testToolExecutorRunsBashCommand() async throws {
        let (executor, context) = try await makeExecutor(
            workingDirectory: tempDirectory.path,
            rules: ["Bash(printf*)"]
        )

        let result = try await executor.execute(
            toolName: "run_command",
            arguments: ["command": .string("printf 'hello from bash'")],
            context: context
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "hello from bash")
    }

    func testToolExecutorWritesHTMLAndOpensItViaBrowserCommand() async throws {
        let fakeBin = tempDirectory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let logFile = tempDirectory.appendingPathComponent("open.log")
        let openScript = fakeBin.appendingPathComponent("open")
        try """
        #!/bin/zsh
        print -r -- "$@" >> "$LOGFILE"
        print -r -- "opened $1"
        """.write(to: openScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: openScript.path)

        setenv("LOGFILE", logFile.path, 1)

        let (executor, context) = try await makeExecutor(
            workingDirectory: tempDirectory.path,
            rules: ["Read", "Write(*.html)", "Bash(*open*)"]
        )

        let writeResult = try await executor.execute(
            toolName: "write_file",
            arguments: [
                "path": .string("site/index.html"),
                "content": .string("<html><body><h1>Hi</h1></body></html>"),
            ],
            context: context
        )
        XCTAssertTrue(writeResult.success)

        let openResult = try await executor.execute(
            toolName: "run_command",
            arguments: ["command": .string("\(openScript.path) site/index.html")],
            context: context
        )

        XCTAssertTrue(openResult.success)
        XCTAssertTrue(openResult.output.contains("opened site/index.html"))
        let log = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertTrue(log.contains("site/index.html"))
        let html = try String(contentsOf: tempDirectory.appendingPathComponent("site/index.html"), encoding: .utf8)
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
    }

    func testConversationalWebSearchRequestExecutesTool() async throws {
        let server = try TestHTTPServer { _ in
            .json(
                """
                {
                  "AbstractText": "",
                  "RelatedTopics": [
                    {
                      "Text": "Example Domain result",
                      "FirstURL": "https://example.com"
                    }
                  ]
                }
                """
            )
        }
        let port = try await server.start()
        defer { server.stop() }

        let template = "http://127.0.0.1:\(port)/search?q=%QUERY%"
        setenv("ODYSSEY_WEB_SEARCH_URL_TEMPLATE", template, 1)
        setenv("CLAUDESTUDIO_WEB_SEARCH_URL_TEMPLATE", template, 1)

        let core = LocalAgentCore()
        _ = await core.createSession(
            .init(
                sessionId: "mlx-web-search",
                config: .init(
                    name: "Web Search",
                    provider: .mlx,
                    model: "mlx-default",
                    systemPrompt: "You are a local coding agent.",
                    workingDirectory: tempDirectory.path,
                    allowedTools: ["WebSearch"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "mlx-web-search", text: #"search the web for "example domain""#)
        )

        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
        XCTAssertTrue(response.resultText.contains("web search"))
        XCTAssertTrue(response.resultText.contains("Example Domain result"))
    }

    func testConversationalBashRequestExecutesTool() async throws {
        let core = LocalAgentCore()
        _ = await core.createSession(
            .init(
                sessionId: "mlx-bash",
                config: .init(
                    name: "Bash",
                    provider: .mlx,
                    model: "mlx-default",
                    systemPrompt: "You are a local coding agent.",
                    workingDirectory: tempDirectory.path,
                    allowedTools: ["Bash(printf*)"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "mlx-bash", text: "execute printf local-agent-bash")
        )

        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
        XCTAssertTrue(response.resultText.contains("command output"))
        XCTAssertTrue(response.resultText.contains("local-agent-bash"))
    }

    func testMLXSessionRetainsHistoryAcrossTurns() async throws {
        let runnerPath = try makeHistoryAwareRunner()
        setenv("ODYSSEY_MLX_RUNNER", runnerPath, 1)
        setenv("CLAUDESTUDIO_MLX_RUNNER", runnerPath, 1)

        let core = LocalAgentCore()
        _ = await core.createSession(
            .init(
                sessionId: "mlx-history",
                config: .init(
                    name: "History",
                    provider: .mlx,
                    model: "mlx-community/history-test",
                    systemPrompt: "You are a local coding agent.",
                    workingDirectory: tempDirectory.path
                )
            )
        )

        _ = try await core.sendMessage(
            .init(sessionId: "mlx-history", text: "hello there")
        )

        let secondResponse = try await core.sendMessage(
            .init(sessionId: "mlx-history", text: "what did i ask first?")
        )

        XCTAssertTrue(secondResponse.resultText.contains("hello there"))
        XCTAssertEqual(secondResponse.numTurns, 2)

        let transcript = await core.transcript(for: "mlx-history")
        XCTAssertEqual(
            transcript.map(\.role),
            [.system, .user, .assistant, .user, .assistant]
        )
        XCTAssertEqual(transcript[1].text, "hello there")
        XCTAssertTrue(transcript[4].text.contains("hello there"))
    }

    private func makeExecutor(
        workingDirectory: String,
        rules: [String]
    ) async throws -> (ToolExecutor, ToolExecutionContext) {
        let registry = ToolRegistry(tools: BuiltInTools.makeDefaultTools())
        let executor = ToolExecutor(registry: registry)
        let definitions = await registry.allToolDefinitions()
        let policy = LocalToolAccessPolicy(rules: rules)
        let context = ToolExecutionContext(
            sessionId: "tool-runtime-test",
            workingDirectory: workingDirectory,
            localPermissionRules: rules,
            allowedBuiltInTools: policy.allowedBuiltInToolNames(from: definitions)
        )
        return (executor, context)
    }

    private func makeHistoryAwareRunner() throws -> String {
        let scriptURL = tempDirectory.appendingPathComponent("llm-tool")
        try """
        #!/bin/zsh
        prompt=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --prompt)
              prompt="$2"
              shift 2
              ;;
            *)
              shift
              ;;
          esac
        done

        lower_prompt=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_prompt" == *"what did i ask first?"* ]]; then
          if [[ "$lower_prompt" == *"user: hello there"* ]]; then
            print -r -- "You first asked: hello there."
          else
            print -r -- "history-missing"
          fi
        else
          print -r -- "Hi back."
        fi
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL.path
    }

    private func restoreEnvironment(_ key: String, value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}

private final class TestHTTPServer {
    struct Response {
        let status: Int
        let contentType: String
        let body: String

        static func json(_ body: String, status: Int = 200) -> Response {
            Response(status: status, contentType: "application/json", body: body)
        }

        static func html(_ body: String, status: Int = 200) -> Response {
            Response(status: status, contentType: "text/html; charset=utf-8", body: body)
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "ToolRuntimeIntegrationTests.HTTPServer")
    private let handler: @Sendable (URL) -> Response

    init(handler: @escaping @Sendable (URL) -> Response) throws {
        self.listener = try NWListener(using: .tcp, on: .any)
        self.handler = handler
    }

    func start() async throws -> Int {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let port = self?.listener.port?.rawValue else {
                        continuation.resume(throwing: NSError(
                            domain: "ToolRuntimeIntegrationTests.HTTPServer",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Listener did not expose a port"]
                        ))
                        return
                    }
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(returning: Int(port))
                case .failed(let error):
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [handler] data, _, _, _ in
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n").first
            else {
                connection.cancel()
                return
            }

            let parts = firstLine.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"
            let url = URL(string: "http://127.0.0.1\(path)") ?? URL(string: "http://127.0.0.1/")!
            let response = handler(url)
            let bodyData = Data(response.body.utf8)

            var headers = "HTTP/1.1 \(response.status) \(reasonPhrase(for: response.status))\r\n"
            headers += "Content-Type: \(response.contentType)\r\n"
            headers += "Content-Length: \(bodyData.count)\r\n"
            headers += "Connection: close\r\n\r\n"
            let packet = Data(headers.utf8) + bodyData

            connection.send(content: packet, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

private func reasonPhrase(for status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 404: return "Not Found"
    default: return "OK"
    }
}
