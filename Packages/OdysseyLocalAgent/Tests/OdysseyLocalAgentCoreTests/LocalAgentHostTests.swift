import Foundation
import XCTest

final class LocalAgentHostTests: XCTestCase {
    private struct HostServerHandle {
        let process: Process
        let outputPipe: Pipe
    }

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

    func testCLIInvocationSupportsMLXRunMode() throws {
        let runnerPath = try makeStubRunner()
        let output = try runHost(arguments: [
            "run",
            "--provider", "mlx",
            "--allow", "Read",
            "--prompt", "list files here",
            "--json",
        ], environment: [
            "ODYSSEY_MLX_RUNNER": runnerPath,
            "ODYSSEY_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
        ])

        XCTAssertTrue(output.contains(#""resultText":"[mlx] directory listing for .:"#))
        XCTAssertTrue(output.contains(#""tool":"list_directory""#))
    }

    func testCLIModelsListsManagedCatalog() throws {
        let runnerPath = try makeStubRunner()
        let output = try runHost(
            arguments: ["models", "--json"],
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
            ]
        )

        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let presets = try XCTUnwrap(payload["presets"] as? [[String: Any]])
        XCTAssertTrue(presets.contains(where: { $0["modelIdentifier"] as? String == "mlx-community/Qwen3-4B-Instruct-2507-4bit" }))
    }

    func testCLIInstallModelUsesManagedCache() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        let output = try runHost(
            arguments: [
                "install-model",
                "--model", "mlx-community/Qwen3-0.6B-4bit",
                "--download-dir", downloadDirectory,
                "--runner", runnerPath,
                "--json",
            ],
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
            ]
        )

        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(payload["modelIdentifier"] as? String, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("managed-models.json").path))
    }

    func testCLIInstallModelSupportsArchiveURL() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        let archiveURL = try makeModelArchive(named: "CLI Archive Demo")
        let output = try runHost(
            arguments: [
                "install-model",
                "--model", archiveURL.absoluteString,
                "--download-dir", downloadDirectory,
                "--runner", runnerPath,
                "--json",
            ],
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
            ]
        )

        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(payload["modelIdentifier"] as? String, "archive/cli-archive-demo")
    }

    func testCLIRemoveModelDeletesManagedCache() throws {
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        _ = try runHost(
            arguments: [
                "install-model",
                "--model", "mlx-community/Qwen3-0.6B-4bit",
                "--download-dir", downloadDirectory,
                "--runner", runnerPath,
                "--json",
            ],
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
            ]
        )

        let managedPath = tempDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("mlx-community")
            .appendingPathComponent("Qwen3-0.6B-4bit")
        try FileManager.default.createDirectory(at: managedPath, withIntermediateDirectories: true)

        let output = try runHost(
            arguments: [
                "remove-model",
                "--model", "https://huggingface.co/mlx-community/Qwen3-0.6B-4bit",
                "--download-dir", downloadDirectory,
                "--json",
            ],
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
            ]
        )

        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(payload["modelIdentifier"] as? String, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath.path))
    }

    func testRESTServerSupportsMLXRunEndpoint() async throws {
        let port = Int.random(in: 32000...38000)
        let runnerPath = try makeStubRunner()
        let server = try startHostServer(
            port: port,
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
            ]
        )
        defer {
            server.process.terminate()
        }

        try await waitForHealth(port: port, server: server)

        let response = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/run")!,
            method: "POST",
            body: [
                "config": [
                    "name": "REST Test",
                    "provider": "mlx",
                    "model": "mlx-test",
                    "systemPrompt": "You are a local coding agent.",
                    "workingDirectory": packageRoot.path,
                    "allowedTools": ["Read"],
                    "mcpServers": [],
                    "skills": [],
                    "toolDefinitions": [],
                ],
                "prompt": "list files here",
            ]
        )
        XCTAssertTrue((response["resultText"] as? String)?.contains("[mlx] directory listing for .:") == true)
        XCTAssertNotNil(response["backendSessionId"] as? String)
    }

    func testRESTServerSupportsManagedMLXInstallEndpoint() async throws {
        let port = Int.random(in: 38001...43000)
        let runnerPath = try makeStubRunner()
        let server = try startHostServer(
            port: port,
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
            ]
        )
        defer {
            server.process.terminate()
        }

        try await waitForHealth(port: port, server: server)

        let response = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/mlx/models/install")!,
            method: "POST",
            body: [
                "modelIdentifier": "mlx-community/Qwen3-0.6B-4bit",
                "downloadDirectory": tempDirectory.appendingPathComponent("huggingface").path,
                "runnerPath": runnerPath,
            ]
        )

        XCTAssertEqual(response["modelIdentifier"] as? String, "mlx-community/Qwen3-0.6B-4bit")
    }

    func testRESTServerSupportsManagedMLXArchiveInstallEndpoint() async throws {
        let port = Int.random(in: 38001...43000)
        let runnerPath = try makeStubRunner()
        let archiveURL = try makeModelArchive(named: "REST Archive Demo")
        let server = try startHostServer(
            port: port,
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
            ]
        )
        defer {
            server.process.terminate()
        }

        try await waitForHealth(port: port, server: server)

        let response = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/mlx/models/install")!,
            method: "POST",
            body: [
                "modelIdentifier": archiveURL.absoluteString,
                "downloadDirectory": tempDirectory.appendingPathComponent("huggingface").path,
                "runnerPath": runnerPath,
            ]
        )

        XCTAssertEqual(response["modelIdentifier"] as? String, "archive/rest-archive-demo")
    }

    func testRESTServerSupportsManagedMLXDeleteEndpoint() async throws {
        let port = Int.random(in: 43001...48000)
        let runnerPath = try makeStubRunner()
        let downloadDirectory = tempDirectory.appendingPathComponent("huggingface").path
        let server = try startHostServer(
            port: port,
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
            ]
        )
        defer {
            server.process.terminate()
        }

        try await waitForHealth(port: port, server: server)

        _ = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/mlx/models/install")!,
            method: "POST",
            body: [
                "modelIdentifier": "mlx-community/Qwen3-0.6B-4bit",
                "downloadDirectory": downloadDirectory,
                "runnerPath": runnerPath,
            ]
        )

        let managedPath = tempDirectory
            .appendingPathComponent("huggingface")
            .appendingPathComponent("mlx-community")
            .appendingPathComponent("Qwen3-0.6B-4bit")
        try FileManager.default.createDirectory(at: managedPath, withIntermediateDirectories: true)

        let response = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/mlx/models/delete")!,
            method: "POST",
            body: [
                "modelIdentifier": "https://huggingface.co/mlx-community/Qwen3-0.6B-4bit",
                "downloadDirectory": downloadDirectory,
            ]
        )

        XCTAssertEqual(response["modelIdentifier"] as? String, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath.path))
    }

    func testStdioAgentAPIAliasesSupportSessionLifecycle() throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = try hostExecutableURL()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "ODYSSEY_MLX_RUNNER": try makeStubRunner(),
            "ODYSSEY_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
        ]) { _, new in new }
        try process.run()
        defer {
            inputPipe.fileHandleForWriting.closeFile()
            if process.isRunning {
                process.terminate()
            }
        }

        let createResponse = try sendStdioRequest(
            id: 1,
            method: "agent.createSession",
            params: [
                "sessionId": "stdio-agent-session",
                "config": [
                    "name": "Stdio Agent",
                    "provider": "mlx",
                    "model": "mlx-test",
                    "systemPrompt": "You are a local coding agent.",
                    "workingDirectory": packageRoot.path,
                    "allowedTools": ["Read"],
                    "mcpServers": [],
                    "skills": [],
                    "toolDefinitions": [],
                ],
            ],
            input: inputPipe.fileHandleForWriting,
            output: outputPipe.fileHandleForReading
        )
        let createResult = try XCTUnwrap(createResponse["result"] as? [String: Any])
        XCTAssertNotNil(createResult["backendSessionId"] as? String)

        let messageResponse = try sendStdioRequest(
            id: 2,
            method: "agent.sendMessage",
            params: [
                "sessionId": "stdio-agent-session",
                "text": "list files here",
            ],
            input: inputPipe.fileHandleForWriting,
            output: outputPipe.fileHandleForReading
        )
        let messageResult = try XCTUnwrap(messageResponse["result"] as? [String: Any])
        XCTAssertTrue((messageResult["resultText"] as? String)?.contains("directory listing") == true)

        let transcriptResponse = try sendStdioRequest(
            id: 3,
            method: "agent.getTranscript",
            params: [
                "sessionId": "stdio-agent-session",
            ],
            input: inputPipe.fileHandleForWriting,
            output: outputPipe.fileHandleForReading
        )
        let transcriptResult = try XCTUnwrap(transcriptResponse["result"] as? [String: Any])
        let transcript = try XCTUnwrap(transcriptResult["transcript"] as? [[String: Any]])
        XCTAssertTrue(transcript.contains(where: { $0["role"] as? String == "user" && $0["text"] as? String == "list files here" }))
        XCTAssertTrue(transcript.contains(where: { $0["role"] as? String == "assistant" }))
    }

    func testRESTAgentAPIEndpointsMirrorSessionLifecycle() async throws {
        let port = Int.random(in: 48001...53000)
        let runnerPath = try makeStubRunner()
        let server = try startHostServer(
            port: port,
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
            ]
        )
        defer {
            server.process.terminate()
        }

        try await waitForHealth(port: port, server: server)

        let createResponse = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions")!,
            method: "POST",
            body: [
                "sessionId": "rest-agent-session",
                "config": [
                    "name": "REST Agent",
                    "provider": "mlx",
                    "model": "mlx-test",
                    "systemPrompt": "You are a local coding agent.",
                    "workingDirectory": packageRoot.path,
                    "allowedTools": ["Read"],
                    "mcpServers": [],
                    "skills": [],
                    "toolDefinitions": [],
                ],
            ]
        )
        XCTAssertNotNil(createResponse["backendSessionId"] as? String)

        let messageResponse = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions/rest-agent-session/messages")!,
            method: "POST",
            body: [
                "text": "list files here",
            ]
        )
        XCTAssertTrue((messageResponse["resultText"] as? String)?.contains("directory listing") == true)

        let transcriptResponse = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions/rest-agent-session/transcript")!,
            method: "GET"
        )
        let transcript = try XCTUnwrap(transcriptResponse["transcript"] as? [[String: Any]])
        XCTAssertTrue(transcript.contains(where: { $0["role"] as? String == "user" && $0["text"] as? String == "list files here" }))
    }

    func testRESTAgentAPIExposeProviderProbeAndTools() async throws {
        let port = Int.random(in: 53001...58000)
        let runnerPath = try makeStubRunner()
        let server = try startHostServer(
            port: port,
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
            ]
        )
        defer {
            server.process.terminate()
        }

        try await waitForHealth(port: port, server: server)

        let providersResponse = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/providers")!,
            method: "GET"
        )
        let providers = try XCTUnwrap(providersResponse["providers"] as? [[String: Any]])
        XCTAssertTrue(providers.contains(where: { $0["provider"] as? String == "mlx" }))
        XCTAssertTrue(providers.contains(where: { $0["provider"] as? String == "foundation" }))

        _ = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions")!,
            method: "POST",
            body: [
                "sessionId": "rest-tools-session",
                "config": [
                    "name": "REST Tools Agent",
                    "provider": "mlx",
                    "model": "mlx-test",
                    "systemPrompt": "You are a local coding agent.",
                    "workingDirectory": packageRoot.path,
                    "allowedTools": ["Read", "Bash(pwd)"],
                    "mcpServers": [],
                    "skills": [],
                    "toolDefinitions": [],
                ],
            ]
        )

        let toolsResponse = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions/rest-tools-session/tools")!,
            method: "GET"
        )
        let tools = try XCTUnwrap(toolsResponse["tools"] as? [[String: Any]])
        XCTAssertTrue(tools.contains(where: { $0["name"] as? String == "list_directory" }))
        XCTAssertTrue(tools.contains(where: { $0["name"] as? String == "read_file" }))
    }

    func testRESTAgentAPIResumeAndForkEndpoints() async throws {
        let port = Int.random(in: 33000...36000)
        let runnerPath = try makeStubRunner()
        let server = try startHostServer(
            port: port,
            environment: [
                "ODYSSEY_MLX_RUNNER": runnerPath,
                "ODYSSEY_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
            ]
        )
        defer {
            server.process.terminate()
        }

        try await waitForHealth(port: port, server: server)

        let createResponse = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions")!,
            method: "POST",
            body: [
                "sessionId": "rest-parent-session",
                "config": [
                    "name": "REST Parent",
                    "provider": "mlx",
                    "model": "mlx-test",
                    "systemPrompt": "You are a local coding agent.",
                    "workingDirectory": packageRoot.path,
                    "allowedTools": ["Read"],
                    "mcpServers": [],
                    "skills": [],
                    "toolDefinitions": [],
                ],
            ]
        )
        let backendSessionId = try XCTUnwrap(createResponse["backendSessionId"] as? String)

        let resumeResponse = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions/rest-parent-session/resume")!,
            method: "POST",
            body: [
                "backendSessionId": backendSessionId,
            ]
        )
        XCTAssertEqual(resumeResponse["backendSessionId"] as? String, backendSessionId)

        _ = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions/rest-parent-session/messages")!,
            method: "POST",
            body: [
                "text": "hello from resume",
            ]
        )

        let forkResponse = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions/rest-parent-session/fork")!,
            method: "POST",
            body: [
                "childSessionId": "rest-child-session",
            ]
        )
        XCTAssertNotNil(forkResponse["backendSessionId"] as? String)

        let childTranscript = try await request(
            url: URL(string: "http://127.0.0.1:\(port)/v1/agent/sessions/rest-child-session/transcript")!,
            method: "GET"
        )
        let transcript = try XCTUnwrap(childTranscript["transcript"] as? [[String: Any]])
        XCTAssertTrue(transcript.contains(where: { $0["role"] as? String == "user" && $0["text"] as? String == "hello from resume" }))
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func runHost(arguments: [String], environment: [String: String] = [:]) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        process.executableURL = try hostExecutableURL()
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        try process.run()
        process.waitUntilExit()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        if process.terminationStatus != 0 {
            XCTFail("Host command failed: \(output)")
        }
        return output
    }

    private func startHostServer(port: Int, environment: [String: String] = [:]) throws -> HostServerHandle {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = try hostExecutableURL()
        process.arguments = ["serve", "--port", String(port)]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        try process.run()
        return HostServerHandle(process: process, outputPipe: outputPipe)
    }

    private func hostExecutableURL() throws -> URL {
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/OdysseyLocalAgentHost"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/OdysseyLocalAgentHost"),
            packageRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/OdysseyLocalAgentHost"),
        ]

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return match
        }

        throw XCTSkip("OdysseyLocalAgentHost executable was not built yet")
    }

    private func waitForHealth(port: Int, server: HostServerHandle) async throws {
        let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!
        for _ in 0..<20 {
            if !server.process.isRunning {
                let data = server.outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                XCTFail("Host server exited before becoming healthy: \(output)")
                return
            }
            do {
                let (_, response) = try await URLSession.shared.data(from: healthURL)
                if let response = response as? HTTPURLResponse, response.statusCode == 200 {
                    return
                }
            } catch {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        let data = server.outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        XCTFail("Host server did not become healthy in time: \(output)")
    }

    private func request(
        url: URL,
        method: String,
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    return [:]
                }
                if response.statusCode == 200 {
                    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                }
                if response.statusCode >= 500, attempt < 2 {
                    try await Task.sleep(for: .milliseconds(200))
                    continue
                }
                XCTFail("Unexpected status code: \(response.statusCode)")
                return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            } catch {
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(200))
                    continue
                }
                throw error
            }
        }
        return [:]
    }

    private func sendStdioRequest(
        id: Int,
        method: String,
        params: [String: Any],
        input: FileHandle,
        output: FileHandle
    ) throws -> [String: Any] {
        let payload: [String: Any] = [
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        input.write(data)
        input.write(Data("\n".utf8))

        let responseData = try readStdioLine(from: output)
        return (try JSONSerialization.jsonObject(with: responseData) as? [String: Any]) ?? [:]
    }

    private func readStdioLine(from handle: FileHandle) throws -> Data {
        var buffer = Data()
        while true {
            let chunk = try handle.read(upToCount: 1) ?? Data()
            if chunk.isEmpty {
                return buffer
            }
            if chunk == Data("\n".utf8) {
                return buffer
            }
            buffer.append(chunk)
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
