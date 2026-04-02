@testable import ClaudeStudioLocalAgentCore
import XCTest

final class LocalAgentCoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func testProbeReflectsRunnerAvailabilityWithoutStubEnv() async {
        unsetenv("CLAUDESTUDIO_MLX_RUNNER")
        let core = LocalAgentCore()

        let result = await core.probe(.init(provider: .mlx))

        XCTAssertEqual(result.provider, .mlx)
        XCTAssertEqual(result.available, ManagedMLXModels.resolveRunner() != nil)
        XCTAssertTrue(result.supportsTools)
    }

    func testManualToolLoopExecutesRegisteredTool() async throws {
        setenv("CLAUDESTUDIO_MLX_RUNNER", "/bin/echo", 1)
        let core = LocalAgentCore()
        await core.registerTool(
            ToolDefinition(name: "echo", description: "Echo") { arguments, _ in
                ToolExecutionResult(success: true, output: "ECHO:\(arguments["message"]?.stringValue ?? "")")
            }
        )

        _ = await core.createSession(
            .init(
                sessionId: "mlx-session",
                config: .init(
                    name: "Local Coder",
                    provider: .mlx,
                    model: "mlx-default",
                    systemPrompt: "prompt",
                    workingDirectory: "/tmp",
                    allowedTools: ["echo"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "mlx-session", text: #"please [[tool:echo {"message":"hi"}]] now"#)
        )

        XCTAssertTrue(response.resultText.contains("[mlx]"))
        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
    }

    func testConversationalDirectoryRequestExecutesToolWithoutInternalSyntax() async throws {
        unsetenv("CLAUDESTUDIO_MLX_RUNNER")
        let core = LocalAgentCore()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        FileManager.default.createFile(atPath: tempDirectory.appendingPathComponent("notes.md").path, contents: Data())

        _ = await core.createSession(
            .init(
                sessionId: "mlx-natural-language-session",
                config: .init(
                    name: "Local Coder",
                    provider: .mlx,
                    model: "mlx-default",
                    systemPrompt: "prompt",
                    workingDirectory: tempDirectory.path,
                    allowedTools: ["Read"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "mlx-natural-language-session", text: "list files here")
        )

        XCTAssertTrue(response.resultText.contains("directory listing"))
        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
        XCTAssertTrue(response.resultText.contains("notes.md"))
    }

    func testConversationalReadRequestExecutesToolWithoutInternalSyntax() async throws {
        unsetenv("CLAUDESTUDIO_MLX_RUNNER")
        let core = LocalAgentCore()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL = tempDirectory.appendingPathComponent("notes.md")
        try "hello world".write(to: fileURL, atomically: true, encoding: .utf8)

        _ = await core.createSession(
            .init(
                sessionId: "mlx-natural-language-read-session",
                config: .init(
                    name: "Local Coder",
                    provider: .mlx,
                    model: "mlx-default",
                    systemPrompt: "prompt",
                    workingDirectory: tempDirectory.path,
                    allowedTools: ["Read"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "mlx-natural-language-read-session", text: "read notes.md")
        )

        XCTAssertTrue(response.resultText.contains("contents of notes.md"))
        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
        XCTAssertTrue(response.resultText.contains("hello world"))
    }

    func testNativeToolFlowExecutesRegisteredTool() async throws {
        let core = LocalAgentCore()
        await core.registerTool(
            ToolDefinition(name: "echo", description: "Echo") { arguments, _ in
                ToolExecutionResult(success: true, output: "FOUNDATION:\(arguments["message"]?.stringValue ?? "")")
            }
        )

        _ = await core.createSession(
            .init(
                sessionId: "foundation-session",
                config: .init(
                    name: "On Device Assistant",
                    provider: .foundation,
                    model: "foundation.system",
                    systemPrompt: "prompt",
                    workingDirectory: "/tmp",
                    allowedTools: ["echo"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(sessionId: "foundation-session", text: #"please [[tool:echo {"message":"hi"}]] now"#)
        )

        XCTAssertEqual(response.events.first?.type, .toolCall)
        XCTAssertEqual(response.events.dropFirst().first?.type, .toolResult)
    }

    func testPermissionRulesRestrictBuiltInTools() async throws {
        let core = LocalAgentCore()
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        _ = await core.createSession(
            .init(
                sessionId: "restricted-session",
                config: .init(
                    name: "Restricted",
                    provider: .foundation,
                    model: "foundation.system",
                    systemPrompt: "prompt",
                    workingDirectory: tempDirectory.path,
                    allowedTools: ["Read"]
                )
            )
        )

        let response = try await core.sendMessage(
            .init(
                sessionId: "restricted-session",
                text: #"please [[tool:write_file {"path":"notes.md","content":"hello"}]] now"#
            )
        )

        XCTAssertTrue(response.resultText.contains("not enabled") || response.resultText.contains("not allowed"))
    }

    func testWritePatternRuleAllowsMatchingFilesOnly() {
        let policy = LocalToolAccessPolicy(rules: ["Write(*.md)"])

        XCTAssertTrue(
            policy.allowsInvocation(
                toolName: "write_file",
                arguments: ["path": .string("notes.md")],
                workingDirectory: "/tmp"
            )
        )
        XCTAssertFalse(
            policy.allowsInvocation(
                toolName: "write_file",
                arguments: ["path": .string("main.swift")],
                workingDirectory: "/tmp"
            )
        )
    }

    func testToolsAndTranscriptAreAvailableForInspection() async throws {
        let core = LocalAgentCore()
        _ = await core.createSession(
            .init(
                sessionId: "inspectable-session",
                config: .init(
                    name: "Inspectable",
                    provider: .foundation,
                    model: "foundation.system",
                    systemPrompt: "prompt",
                    workingDirectory: "/tmp",
                    allowedTools: ["Read", "Grep"]
                )
            )
        )

        let tools = await core.tools(for: "inspectable-session")
        let transcript = await core.transcript(for: "inspectable-session")

        XCTAssertTrue(tools.contains(where: { $0.name == "read_file" }))
        XCTAssertTrue(tools.contains(where: { $0.name == "search_files" }))
        XCTAssertEqual(transcript.first?.role, .system)
    }

    func testTranscriptCodecRoundTripsItems() throws {
        let transcript = [
            TranscriptItem(role: .system, text: "sys"),
            TranscriptItem(role: .user, text: "hello"),
            TranscriptItem(role: .assistant, text: "hi"),
        ]

        let encoded = try TranscriptCodec.encode(transcript)
        let decoded = try TranscriptCodec.decode(encoded)

        XCTAssertEqual(decoded.map(\.role), transcript.map(\.role))
        XCTAssertEqual(decoded.map(\.text), transcript.map(\.text))
    }

    func testMCPBridgeCreatesSummary() async {
        let bridge = MCPBridge()
        let summary = await bridge.summarize(
            servers: [
                LocalAgentMCPServer(name: "filesystem", command: "/does/not/exist"),
                LocalAgentMCPServer(name: "docs", url: "http://localhost:9999"),
            ]
        )

        XCTAssertEqual(summary.configuredServers, ["filesystem", "docs"])
        XCTAssertEqual(summary.discoveredTools.count, 2)
    }

    func testManagedMLXInstallWritesManifest() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path

        let result = try ManagedMLXModels.installModel(
            modelIdentifier: "mlx-community/Qwen3-0.6B-4bit",
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        XCTAssertEqual(result.modelIdentifier, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertFalse(result.alreadyInstalled)
        XCTAssertEqual(result.downloadDirectory, downloadDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.manifestPath))

        let listed = ManagedMLXModels.installedModels(downloadDirectory: downloadDirectory)
        XCTAssertEqual(listed.map(\.modelIdentifier), ["mlx-community/Qwen3-0.6B-4bit"])
    }

    func testManagedMLXListReturnsPresetsAndInstalledModels() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        _ = try ManagedMLXModels.installModel(
            modelIdentifier: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        let result = ManagedMLXModels.listModels(
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        XCTAssertTrue(result.presets.contains(where: { $0.modelIdentifier == "mlx-community/Qwen2.5-1.5B-Instruct-4bit" }))
        XCTAssertEqual(result.installed.map(\.modelIdentifier), ["mlx-community/Qwen2.5-1.5B-Instruct-4bit"])
        XCTAssertEqual(result.runnerPath, runnerPath)
    }

    private func makeStubRunner() throws -> String {
        let scriptURL = tempDirectory.appendingPathComponent("llm-tool")
        try """
        #!/bin/zsh
        echo "$@"
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL.path
    }
}
