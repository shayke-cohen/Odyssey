import Foundation
import XCTest

final class LocalAgentHostTests: XCTestCase {
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
        let output = try runHost(arguments: [
            "run",
            "--provider", "mlx",
            "--allow", "Read",
            "--prompt", "list files here",
            "--json",
        ])

        XCTAssertTrue(output.contains(#""resultText":"[mlx] directory listing for .:"#))
        XCTAssertTrue(output.contains(#""tool":"list_directory""#))
    }

    func testCLIModelsListsManagedCatalog() throws {
        let runnerPath = try makeStubRunner()
        let output = try runHost(
            arguments: ["models", "--json"],
            environment: [
                "CLAUDESTUDIO_MLX_RUNNER": runnerPath,
                "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
            ]
        )

        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let presets = try XCTUnwrap(payload["presets"] as? [[String: Any]])
        XCTAssertTrue(presets.contains(where: { $0["modelIdentifier"] as? String == "mlx-community/Qwen2.5-1.5B-Instruct-4bit" }))
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
                "CLAUDESTUDIO_MLX_RUNNER": runnerPath,
                "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory,
            ]
        )

        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(payload["modelIdentifier"] as? String, "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("managed-models.json").path))
    }

    func testRESTServerSupportsMLXRunEndpoint() async throws {
        let port = Int.random(in: 32000...38000)
        let process = try startHostServer(port: port)
        defer {
            process.terminate()
        }

        try await waitForHealth(port: port)

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
        let process = try startHostServer(
            port: port,
            environment: [
                "CLAUDESTUDIO_MLX_RUNNER": runnerPath,
                "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": tempDirectory.appendingPathComponent("huggingface").path,
            ]
        )
        defer {
            process.terminate()
        }

        try await waitForHealth(port: port)

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

    private func startHostServer(port: Int, environment: [String: String] = [:]) throws -> Process {
        let process = Process()
        process.executableURL = try hostExecutableURL()
        process.arguments = ["serve", "--port", String(port)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        try process.run()
        return process
    }

    private func hostExecutableURL() throws -> URL {
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/ClaudeStudioLocalAgentHost"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/ClaudeStudioLocalAgentHost"),
            packageRoot.appendingPathComponent(".build/x86_64-apple-macosx/debug/ClaudeStudioLocalAgentHost"),
        ]

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return match
        }

        throw XCTSkip("ClaudeStudioLocalAgentHost executable was not built yet")
    }

    private func waitForHealth(port: Int) async throws {
        let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!
        for _ in 0..<20 {
            do {
                let (_, response) = try await URLSession.shared.data(from: healthURL)
                if let response = response as? HTTPURLResponse, response.statusCode == 200 {
                    return
                }
            } catch {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        XCTFail("Host server did not become healthy in time")
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
