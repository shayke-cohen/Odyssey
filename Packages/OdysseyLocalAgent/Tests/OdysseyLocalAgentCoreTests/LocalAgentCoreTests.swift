@testable import OdysseyLocalAgentCore
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
        unsetenv("ODYSSEY_MLX_RUNNER")
        unsetenv("CLAUDESTUDIO_MLX_RUNNER")
        let core = LocalAgentCore()

        let result = await core.probe(.init(provider: .mlx))

        XCTAssertEqual(result.provider, .mlx)
        XCTAssertEqual(result.available, ManagedMLXModels.resolveRunner() != nil)
        XCTAssertTrue(result.supportsTools)
    }

    func testResolveRunnerIgnoresDirectoryNamedLikeLLMTool() throws {
        let previousPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let fakeBin = tempDirectory.appendingPathComponent("fake-bin", isDirectory: true)
        let fakeRunnerDirectory = fakeBin.appendingPathComponent("llm-tool", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeRunnerDirectory, withIntermediateDirectories: true)

        unsetenv("ODYSSEY_MLX_RUNNER")
        unsetenv("CLAUDESTUDIO_MLX_RUNNER")
        _ = fakeBin.path.withCString { pointer in
            setenv("PATH", pointer, 1)
        }
        defer {
            _ = previousPath.withCString { pointer in
                setenv("PATH", pointer, 1)
            }
        }

        XCTAssertNotEqual(ManagedMLXModels.resolveRunner(fakeRunnerDirectory.path), fakeRunnerDirectory.path)
    }

    func testManagedMLXPresetsIncludeSizingAndAgentGuidance() {
        let presets = ManagedMLXModels.presets()

        XCTAssertFalse(presets.isEmpty)
        XCTAssertTrue(presets.allSatisfy { !$0.parameterSize.isEmpty })
        XCTAssertTrue(presets.allSatisfy { !$0.downloadSize.isEmpty })
        XCTAssertTrue(presets.allSatisfy { !$0.bestFor.isEmpty })
        XCTAssertTrue(presets.allSatisfy { !$0.agentSuitability.isEmpty })
    }

    func testManagedMLXPresetsMatchCuratedList() {
        XCTAssertEqual(
            ManagedMLXModels.presets().map(\.modelIdentifier),
            [
                "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                "mlx-community/Qwen3-0.6B-4bit",
                "mlx-community/Qwen2.5-7B-Instruct-4bit",
                "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
                "mlx-community/Llama-3.2-3B-Instruct-4bit",
                "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit",
            ]
        )
    }

    func testManualToolLoopExecutesRegisteredTool() async throws {
        setenv("ODYSSEY_MLX_RUNNER", "/bin/echo", 1)
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
        unsetenv("ODYSSEY_MLX_RUNNER")
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
        unsetenv("ODYSSEY_MLX_RUNNER")
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

    func testSanitizeMLXOutputRemovesLoadingLine() {
        let output = """
        Loading mlx-community/Qwen2.5-1.5B-Instruct-4bit...
        1 + 1 = 2
        """

        XCTAssertEqual(sanitizeMLXOutput(output), "1 + 1 = 2")
    }

    func testSanitizeMLXOutputExtractsStructuredResult() {
        let output = """
        Loading mlx-community/Qwen2.5-1.5B-Instruct-4bit...
        {"result": "2"}
        """

        XCTAssertEqual(sanitizeMLXOutput(output), "2")
    }

    func testSanitizeMLXOutputCollapsesDuplicatedAnswer() {
        let output = """
        "1+1 equals 2." "1+1 equals 2."
        """

        XCTAssertEqual(sanitizeMLXOutput(output), "\"1+1 equals 2.\"")
    }

    func testShouldPreferDirectChatResponseForGeneralQuestion() {
        XCTAssertTrue(
            shouldPreferDirectChatResponse(
                for: "where is tel aviv?",
                availableTools: ["read_file", "run_command"]
            )
        )
    }

    func testShouldPreferDirectChatResponseForToolingRequest() {
        XCTAssertFalse(
            shouldPreferDirectChatResponse(
                for: "read AGENTS.md",
                availableTools: ["read_file", "run_command"]
            )
        )
    }

    func testDetectsDegenerateAssistantResponses() {
        XCTAssertTrue(isDegenerateAssistantResponse("None", userText: "where is tel aviv?"))
        XCTAssertTrue(isDegenerateAssistantResponse("\"where is tel aviv?\"", userText: "where is tel aviv?"))
        XCTAssertFalse(isDegenerateAssistantResponse("Tel Aviv is on Israel's Mediterranean coast.", userText: "where is tel aviv?"))
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

    func testManagedMLXInstallNormalizesHuggingFaceURL() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path

        let result = try ManagedMLXModels.installModel(
            modelIdentifier: "https://huggingface.co/mlx-community/Qwen3-0.6B-4bit",
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        XCTAssertEqual(result.modelIdentifier, "mlx-community/Qwen3-0.6B-4bit")
    }

    func testManagedMLXInstallSupportsArchiveURL() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        let archiveURL = try makeModelArchive(named: "Qwen3 Archive Demo")

        let result = try ManagedMLXModels.installModel(
            modelIdentifier: archiveURL.absoluteString,
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        XCTAssertEqual(result.modelIdentifier, "archive/qwen3-archive-demo")
        XCTAssertFalse(result.alreadyInstalled)

        let listed = ManagedMLXModels.installedModels(downloadDirectory: downloadDirectory)
        XCTAssertEqual(listed.map(\.modelIdentifier), ["archive/qwen3-archive-demo"])
        XCTAssertEqual(listed.first?.sourceURL, archiveURL.absoluteString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: listed.first?.managedPath ?? ""))
    }

    func testInstalledModelsHealHuggingFaceManagedPathLayout() throws {
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        let actualManagedPath = tempDirectory
            .appendingPathComponent("huggingface/models/mlx-community/Qwen3-4B-Instruct-2507-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: actualManagedPath, withIntermediateDirectories: true)

        let manifestPath = ManagedMLXModels.manifestPath(for: downloadDirectory)
        struct TestManifest: Encodable {
            let installed: [ManagedMLXInstalledModel]
        }

        let manifest = TestManifest(installed: [
            ManagedMLXInstalledModel(
                modelIdentifier: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                downloadDirectory: downloadDirectory,
                installedAt: Date(),
                sourceURL: "https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit",
                managedPath: tempDirectory.appendingPathComponent("huggingface/mlx-community/Qwen3-4B-Instruct-2507-4bit").path
            )
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: manifestPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(manifest).write(to: URL(fileURLWithPath: manifestPath), options: .atomic)

        let listed = ManagedMLXModels.installedModels(downloadDirectory: downloadDirectory)
        XCTAssertEqual(listed.first?.managedPath, actualManagedPath.path)
    }

    func testManagedMLXRemoveModelDeletesManagedPathAndManifestEntry() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        let managedPath = tempDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("mlx-community")
            .appendingPathComponent("Qwen3-0.6B-4bit")
        try FileManager.default.createDirectory(at: managedPath, withIntermediateDirectories: true)
        try "weights".write(
            to: managedPath.appendingPathComponent("weights.bin"),
            atomically: true,
            encoding: .utf8
        )

        _ = try ManagedMLXModels.installModel(
            modelIdentifier: "mlx-community/Qwen3-0.6B-4bit",
            downloadDirectory: downloadDirectory,
            runnerPath: runnerPath
        )

        let result = try ManagedMLXModels.removeModel(
            modelIdentifier: "https://huggingface.co/mlx-community/Qwen3-0.6B-4bit",
            downloadDirectory: downloadDirectory
        )

        XCTAssertEqual(result.modelIdentifier, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertFalse(result.alreadyRemoved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath.path))
        XCTAssertEqual(
            ManagedMLXModels.installedModels(downloadDirectory: downloadDirectory).map(\.modelIdentifier),
            []
        )
    }

    func testNormalizeModelIdentifierRejectsInvalidURL() {
        XCTAssertNil(ManagedMLXModels.normalizeModelIdentifier("https://example.com/mlx-community/Qwen3-0.6B-4bit"))
        XCTAssertNil(ManagedMLXModels.normalizeModelIdentifier("/tmp/local-model"))
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

    func testRunProcessReturnsOutputFromStubRunner() throws {
        let runnerPath = try makeStubRunner()

        let output = try ManagedMLXModels.runProcess(
            executable: runnerPath,
            arguments: ["eval", "--model", "mlx-community/Qwen3-0.6B-4bit"]
        )

        XCTAssertEqual(output, "eval --model mlx-community/Qwen3-0.6B-4bit")
    }

    func testRunProcessTimesOutHungRunner() throws {
        let runnerPath = try makeHangingRunner()

        XCTAssertThrowsError(
            try ManagedMLXModels.runProcess(
                executable: runnerPath,
                arguments: ["eval", "--model", "mlx-community/Qwen3-0.6B-4bit"],
                timeout: 0.2
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Process timed out"))
        }
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

    private func makeHangingRunner() throws -> String {
        let scriptURL = tempDirectory.appendingPathComponent("llm-tool-hang")
        try """
        #!/bin/zsh
        sleep 5
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL.path
    }

    private func makeModelArchive(named directoryName: String) throws -> URL {
        let modelDirectory = tempDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try "{}".write(to: modelDirectory.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: modelDirectory.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
        try "weights".write(to: modelDirectory.appendingPathComponent("weights.safetensors"), atomically: true, encoding: .utf8)

        let archiveURL = tempDirectory.appendingPathComponent("mlx-model.tar.gz")
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archiveURL.path, "-C", tempDirectory.path, directoryName]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output)
        return archiveURL
    }
}
