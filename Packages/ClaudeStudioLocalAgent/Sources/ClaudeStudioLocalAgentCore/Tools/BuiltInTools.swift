import Foundation

enum BuiltInTools {
    static func makeDefaultTools() -> [ToolDefinition] {
        [
            readFileTool(),
            writeFileTool(),
            listDirectoryTool(),
            searchFilesTool(),
            replaceInFileTool(),
            runCommandTool(),
            webSearchTool(),
            fetchURLTool(),
        ]
    }

    private static func readFileTool() -> ToolDefinition {
        ToolDefinition(
            name: "read_file",
            description: "Read a UTF-8 text file from disk.",
            inputSchema: ["path": "string"]
        ) { arguments, context in
            let path = try resolvePath(from: arguments["path"], workingDirectory: context.workingDirectory)
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let text = String(decoding: data, as: UTF8.self)
            return ToolExecutionResult(success: true, output: text)
        }
    }

    private static func writeFileTool() -> ToolDefinition {
        ToolDefinition(
            name: "write_file",
            description: "Write UTF-8 text to disk, creating parent directories if needed.",
            inputSchema: ["path": "string", "content": "string"]
        ) { arguments, context in
            let path = try resolvePath(from: arguments["path"], workingDirectory: context.workingDirectory)
            let content = arguments["content"]?.stringValue ?? ""
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.data(using: .utf8)?.write(to: url)
            return ToolExecutionResult(success: true, output: "Wrote \(content.count) bytes to \(path)")
        }
    }

    private static func listDirectoryTool() -> ToolDefinition {
        ToolDefinition(
            name: "list_directory",
            description: "List directory contents.",
            inputSchema: ["path": "string"]
        ) { arguments, context in
            let path = try resolvePath(from: arguments["path"], workingDirectory: context.workingDirectory)
            let entries = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
            return ToolExecutionResult(success: true, output: entries.joined(separator: "\n"))
        }
    }

    private static func searchFilesTool() -> ToolDefinition {
        ToolDefinition(
            name: "search_files",
            description: "Search file contents recursively under a path.",
            inputSchema: ["path": "string", "query": "string", "maxResults": "number"]
        ) { arguments, context in
            let path = try resolvePath(from: arguments["path"], workingDirectory: context.workingDirectory)
            let query = arguments["query"]?.stringValue ?? ""
            let maxResults = Int(arguments["maxResults"]?.stringValue ?? "") ?? 20
            let results = try searchRecursively(rootPath: path, query: query, maxResults: maxResults)
            return ToolExecutionResult(success: true, output: results.joined(separator: "\n"))
        }
    }

    private static func replaceInFileTool() -> ToolDefinition {
        ToolDefinition(
            name: "replace_in_file",
            description: "Replace text in a file.",
            inputSchema: ["path": "string", "find": "string", "replace": "string"]
        ) { arguments, context in
            let path = try resolvePath(from: arguments["path"], workingDirectory: context.workingDirectory)
            let find = arguments["find"]?.stringValue ?? ""
            let replace = arguments["replace"]?.stringValue ?? ""
            let url = URL(fileURLWithPath: path)
            let original = try String(contentsOf: url, encoding: .utf8)
            guard original.contains(find) else {
                return ToolExecutionResult(success: false, output: "Text to replace was not found")
            }
            let updated = original.replacingOccurrences(of: find, with: replace)
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return ToolExecutionResult(success: true, output: "Updated \(path)")
        }
    }

    private static func runCommandTool() -> ToolDefinition {
        ToolDefinition(
            name: "run_command",
            description: "Run a shell command in the working directory.",
            inputSchema: ["command": "string", "timeoutSeconds": "number"]
        ) { arguments, context in
            let command = arguments["command"]?.stringValue ?? ""
            let timeoutSeconds = Int(arguments["timeoutSeconds"]?.stringValue ?? "") ?? 30
            let result = try runShellCommand(command, workingDirectory: context.workingDirectory, timeoutSeconds: timeoutSeconds)
            return ToolExecutionResult(success: result.exitCode == 0, output: result.output)
        }
    }

    private static func fetchURLTool() -> ToolDefinition {
        ToolDefinition(
            name: "fetch_url",
            description: "Fetch text content from a URL.",
            inputSchema: ["url": "string"]
        ) { arguments, _ in
            guard let rawURL = arguments["url"]?.stringValue,
                  let url = URL(string: rawURL) else {
                return ToolExecutionResult(success: false, output: "Invalid URL")
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            let body = String(decoding: data.prefix(50_000), as: UTF8.self)
            return ToolExecutionResult(
                success: (200..<300).contains(statusCode),
                output: "HTTP \(statusCode)\n\n\(body)"
            )
        }
    }

    private static func webSearchTool() -> ToolDefinition {
        ToolDefinition(
            name: "web_search",
            description: "Search the web and return a compact list of results.",
            inputSchema: ["query": "string"]
        ) { arguments, _ in
            let query = arguments["query"]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !query.isEmpty else {
                return ToolExecutionResult(success: false, output: "A search query is required")
            }

            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&no_redirect=1") else {
                return ToolExecutionResult(success: false, output: "Could not build DuckDuckGo search URL")
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard (200..<300).contains(statusCode) else {
                return ToolExecutionResult(success: false, output: "Search failed with HTTP \(statusCode)")
            }

            let output = (try? formatSearchResponse(data: data, query: query)) ?? "No search results found."
            return ToolExecutionResult(success: true, output: output)
        }
    }
}

private func resolvePath(from value: DynamicValue?, workingDirectory: String) throws -> String {
    let raw = value?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !raw.isEmpty else {
        throw NSError(domain: "ClaudeStudioLocalAgent.BuiltInTools", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "A path is required"
        ])
    }

    if raw.hasPrefix("/") {
        return URL(fileURLWithPath: raw).standardizedFileURL.path
    }

    return URL(fileURLWithPath: workingDirectory)
        .appendingPathComponent(raw)
        .standardizedFileURL
        .path
}

private func searchRecursively(rootPath: String, query: String, maxResults: Int) throws -> [String] {
    guard !query.isEmpty else { return [] }

    let rootURL = URL(fileURLWithPath: rootPath)
    guard let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var matches = [String]()
    for case let fileURL as URL in enumerator {
        if matches.count >= maxResults { break }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            continue
        }
        if text.localizedCaseInsensitiveContains(query) {
            matches.append(fileURL.path)
        }
    }
    return matches
}

private struct ShellResult {
    var exitCode: Int32
    var output: String
}

private func runShellCommand(_ command: String, workingDirectory: String, timeoutSeconds: Int) throws -> ShellResult {
    let process = Process()
    let outputPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    try process.run()

    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
    while process.isRunning && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    if process.isRunning {
        process.terminate()
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: data, as: UTF8.self)
    return ShellResult(exitCode: process.terminationStatus, output: output)
}

private func formatSearchResponse(data: Data, query: String) throws -> String {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return "No search results found for \(query)."
    }

    var lines = ["Search results for: \(query)"]

    if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
        lines.append("")
        lines.append("Summary: \(abstract)")
    }

    let topics = (json["RelatedTopics"] as? [[String: Any]] ?? [])
        .flatMap { topic -> [[String: Any]] in
            if let nested = topic["Topics"] as? [[String: Any]], !nested.isEmpty {
                return nested
            }
            return [topic]
        }
        .prefix(5)

    if !topics.isEmpty {
        lines.append("")
        lines.append("Top results:")
        for topic in topics {
            let text = topic["Text"] as? String ?? "(no title)"
            let url = topic["FirstURL"] as? String ?? ""
            lines.append(url.isEmpty ? "- \(text)" : "- \(text) — \(url)")
        }
    }

    return lines.joined(separator: "\n")
}
