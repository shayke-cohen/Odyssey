import Foundation

public struct ManagedMLXModelPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String { modelIdentifier }
    public var modelIdentifier: String
    public var label: String
    public var summary: String
    public var parameterSize: String
    public var downloadSize: String
    public var bestFor: String
    public var agentSuitability: String
    public var recommended: Bool

    public init(
        modelIdentifier: String,
        label: String,
        summary: String,
        parameterSize: String = "",
        downloadSize: String = "",
        bestFor: String = "",
        agentSuitability: String = "",
        recommended: Bool
    ) {
        self.modelIdentifier = modelIdentifier
        self.label = label
        self.summary = summary
        self.parameterSize = parameterSize
        self.downloadSize = downloadSize
        self.bestFor = bestFor
        self.agentSuitability = agentSuitability
        self.recommended = recommended
    }
}

public struct ManagedMLXInstalledModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String { modelIdentifier }
    public var modelIdentifier: String
    public var downloadDirectory: String
    public var installedAt: Date
    public var sourceURL: String?
    public var managedPath: String?

    public init(
        modelIdentifier: String,
        downloadDirectory: String,
        installedAt: Date,
        sourceURL: String? = nil,
        managedPath: String? = nil
    ) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
        self.installedAt = installedAt
        self.sourceURL = sourceURL
        self.managedPath = managedPath
    }
}

public struct MLXModelsListParams: Codable, Sendable, Equatable {
    public var downloadDirectory: String?
    public var runnerPath: String?

    public init(downloadDirectory: String? = nil, runnerPath: String? = nil) {
        self.downloadDirectory = downloadDirectory
        self.runnerPath = runnerPath
    }
}

public struct MLXModelsListResult: Codable, Sendable, Equatable {
    public var downloadDirectory: String
    public var manifestPath: String
    public var runnerPath: String?
    public var presets: [ManagedMLXModelPreset]
    public var installed: [ManagedMLXInstalledModel]

    public init(
        downloadDirectory: String,
        manifestPath: String,
        runnerPath: String?,
        presets: [ManagedMLXModelPreset],
        installed: [ManagedMLXInstalledModel]
    ) {
        self.downloadDirectory = downloadDirectory
        self.manifestPath = manifestPath
        self.runnerPath = runnerPath
        self.presets = presets
        self.installed = installed
    }
}

public struct InstallMLXModelParams: Codable, Sendable, Equatable {
    public var modelIdentifier: String
    public var downloadDirectory: String?
    public var runnerPath: String?

    public init(modelIdentifier: String, downloadDirectory: String? = nil, runnerPath: String? = nil) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
        self.runnerPath = runnerPath
    }
}

public struct RemoveMLXModelParams: Codable, Sendable, Equatable {
    public var modelIdentifier: String
    public var downloadDirectory: String?

    public init(modelIdentifier: String, downloadDirectory: String? = nil) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
    }
}

public struct InstallMLXModelResult: Codable, Sendable, Equatable {
    public var modelIdentifier: String
    public var downloadDirectory: String
    public var manifestPath: String
    public var runnerPath: String
    public var alreadyInstalled: Bool
    public var output: String
    public var installedAt: Date

    public init(
        modelIdentifier: String,
        downloadDirectory: String,
        manifestPath: String,
        runnerPath: String,
        alreadyInstalled: Bool,
        output: String,
        installedAt: Date
    ) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
        self.manifestPath = manifestPath
        self.runnerPath = runnerPath
        self.alreadyInstalled = alreadyInstalled
        self.output = output
        self.installedAt = installedAt
    }
}

public struct RemoveMLXModelResult: Codable, Sendable, Equatable {
    public var modelIdentifier: String
    public var downloadDirectory: String
    public var manifestPath: String
    public var deletedPaths: [String]
    public var alreadyRemoved: Bool

    public init(
        modelIdentifier: String,
        downloadDirectory: String,
        manifestPath: String,
        deletedPaths: [String],
        alreadyRemoved: Bool
    ) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
        self.manifestPath = manifestPath
        self.deletedPaths = deletedPaths
        self.alreadyRemoved = alreadyRemoved
    }
}

public enum ManagedMLXModelsError: LocalizedError {
    case missingRunner
    case invalidModelIdentifier
    case installFailed(String)
    case removeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingRunner:
            return "MLX runner not found. Install llm-tool or set ODYSSEY_MLX_RUNNER."
        case .invalidModelIdentifier:
            return "Enter a Hugging Face MLX model id or URL, not a local path."
        case .installFailed(let output):
            return output.isEmpty ? "Failed to install the MLX model." : output
        case .removeFailed(let output):
            return output.isEmpty ? "Failed to remove the MLX model." : output
        }
    }
}

private struct ManagedMLXManifest: Codable {
    var installed: [ManagedMLXInstalledModel] = []
}

public enum ManagedMLXModels {
    public static let downloadDirectoryEnvironmentKey = "ODYSSEY_MLX_DOWNLOAD_DIR"
    public static let legacyDownloadDirectoryEnvironmentKey = "CLAUDESTUDIO_MLX_DOWNLOAD_DIR"

    public static func presets() -> [ManagedMLXModelPreset] {
        [
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                label: "Qwen3 4B Instruct",
                summary: "Recommended for local agent work. Better reasoning and tool use than the tiny defaults.",
                parameterSize: "4B params",
                downloadSize: "~2.6 GB",
                bestFor: "Daily local agent work, repo navigation, and stronger tool use.",
                agentSuitability: "Strong for agents",
                recommended: true
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                label: "Qwen2.5 1.5B Instruct",
                summary: "Lightweight fallback for quick local chat when you want a smaller download.",
                parameterSize: "1.5B params",
                downloadSize: "~1.0 GB",
                bestFor: "Quick chats, lightweight edits, and smaller laptops.",
                agentSuitability: "Okay for agents",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen3-0.6B-4bit",
                label: "Qwen3 0.6B",
                summary: "Smallest install for smoke tests and very constrained Macs.",
                parameterSize: "0.6B params",
                downloadSize: "~450 MB",
                bestFor: "Smoke tests, setup validation, and very fast downloads.",
                agentSuitability: "Limited for agents",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                label: "Qwen2.5 7B Instruct",
                summary: "Stronger local reasoning and tool use if you can afford a larger model.",
                parameterSize: "7B params",
                downloadSize: "~4.5 GB",
                bestFor: "Longer reasoning, stronger coding help, and beefier Macs.",
                agentSuitability: "Strong for agents",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                label: "Llama 3.2 3B Instruct",
                summary: "Alternative medium-size general model.",
                parameterSize: "3B params",
                downloadSize: "~2.0 GB",
                bestFor: "General local assistant work and an alternative instruction tune.",
                agentSuitability: "Good for agents",
                recommended: false
            ),
        ]
    }

    public static func listModels(
        downloadDirectory explicitDownloadDirectory: String? = nil,
        runnerPath explicitRunnerPath: String? = nil
    ) -> MLXModelsListResult {
        let downloadDirectory = resolveDownloadDirectory(explicitDownloadDirectory)
        return MLXModelsListResult(
            downloadDirectory: downloadDirectory,
            manifestPath: manifestPath(for: downloadDirectory),
            runnerPath: resolveRunner(explicitRunnerPath),
            presets: presets(),
            installed: installedModels(downloadDirectory: downloadDirectory)
        )
    }

    public static func installModel(
        modelIdentifier: String,
        downloadDirectory explicitDownloadDirectory: String? = nil,
        runnerPath explicitRunnerPath: String? = nil
    ) throws -> InstallMLXModelResult {
        let trimmedModelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedModelIdentifier = normalizeModelIdentifier(trimmedModelIdentifier) else {
            throw ManagedMLXModelsError.invalidModelIdentifier
        }

        guard let runnerPath = resolveRunner(explicitRunnerPath) else {
            throw ManagedMLXModelsError.missingRunner
        }

        let downloadDirectory = resolveDownloadDirectory(explicitDownloadDirectory)
        let manifestPath = manifestPath(for: downloadDirectory)

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: downloadDirectory),
            withIntermediateDirectories: true
        )

        let manifest = loadManifest(at: manifestPath)
        if let installed = manifest.installed.first(where: {
            normalizeModelIdentifier($0.modelIdentifier) == normalizedModelIdentifier
        }) {
            return InstallMLXModelResult(
                modelIdentifier: normalizedModelIdentifier,
                downloadDirectory: downloadDirectory,
                manifestPath: manifestPath,
                runnerPath: runnerPath,
                alreadyInstalled: true,
                output: "Model already installed.",
                installedAt: installed.installedAt
            )
        }

        let output = try runProcess(
            executable: runnerPath,
            arguments: [
                "eval",
                "--model", normalizedModelIdentifier,
                "--download", downloadDirectory,
                "--prompt", "Hello",
                "--max-tokens", "1",
                "--quiet",
            ],
            extraEnvironment: [downloadDirectoryEnvironmentKey: downloadDirectory]
        )

        let installedAt = Date()
        let managedPath = firstExistingManagedPath(
            for: normalizedModelIdentifier,
            downloadDirectory: downloadDirectory
        ) ?? preferredManagedPath(
            for: normalizedModelIdentifier,
            downloadDirectory: downloadDirectory
        )
        var updatedManifest = manifest
        updatedManifest.installed.removeAll {
            normalizeModelIdentifier($0.modelIdentifier) == normalizedModelIdentifier
        }
        updatedManifest.installed.append(
            ManagedMLXInstalledModel(
                modelIdentifier: normalizedModelIdentifier,
                downloadDirectory: downloadDirectory,
                installedAt: installedAt,
                sourceURL: sourceURL(from: trimmedModelIdentifier),
                managedPath: managedPath
            )
        )
        updatedManifest.installed.sort { $0.modelIdentifier.localizedCaseInsensitiveCompare($1.modelIdentifier) == .orderedAscending }
        try saveManifest(updatedManifest, to: manifestPath)

        return InstallMLXModelResult(
            modelIdentifier: normalizedModelIdentifier,
            downloadDirectory: downloadDirectory,
            manifestPath: manifestPath,
            runnerPath: runnerPath,
            alreadyInstalled: false,
            output: output,
            installedAt: installedAt
        )
    }

    public static func removeModel(
        modelIdentifier: String,
        downloadDirectory explicitDownloadDirectory: String? = nil
    ) throws -> RemoveMLXModelResult {
        let trimmedModelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedModelIdentifier = normalizeModelIdentifier(trimmedModelIdentifier) else {
            throw ManagedMLXModelsError.invalidModelIdentifier
        }

        let downloadDirectory = resolveDownloadDirectory(explicitDownloadDirectory)
        let manifestPath = manifestPath(for: downloadDirectory)
        var manifest = loadManifest(at: manifestPath)
        let existing = manifest.installed.first {
            normalizeModelIdentifier($0.modelIdentifier) == normalizedModelIdentifier
        }
        let alreadyRemoved = existing == nil

        let candidatePaths = Array(
            Set(
                ([existing?.managedPath].compactMap { $0 } + managedPathCandidates(
                    for: normalizedModelIdentifier,
                    downloadDirectory: downloadDirectory
                )).map(standardizedPath)
            )
        )

        let allowedRoots = [
            standardizedPath(downloadDirectory),
            standardizedPath(URL(fileURLWithPath: downloadDirectory).deletingLastPathComponent().path),
        ]

        var deletedPaths: [String] = []
        for candidate in candidatePaths {
            guard isDescendant(candidate, ofAny: allowedRoots),
                  FileManager.default.fileExists(atPath: candidate) else {
                continue
            }

            do {
                try FileManager.default.removeItem(atPath: candidate)
                deletedPaths.append(candidate)
                removeEmptyAncestorDirectories(afterDeleting: candidate, stopAt: allowedRoots)
            } catch {
                throw ManagedMLXModelsError.removeFailed(error.localizedDescription)
            }
        }

        manifest.installed.removeAll {
            normalizeModelIdentifier($0.modelIdentifier) == normalizedModelIdentifier
        }
        try saveManifest(manifest, to: manifestPath)

        return RemoveMLXModelResult(
            modelIdentifier: normalizedModelIdentifier,
            downloadDirectory: downloadDirectory,
            manifestPath: manifestPath,
            deletedPaths: deletedPaths.sorted(),
            alreadyRemoved: alreadyRemoved
        )
    }

    public static func installedModels(downloadDirectory explicitDownloadDirectory: String? = nil) -> [ManagedMLXInstalledModel] {
        let downloadDirectory = resolveDownloadDirectory(explicitDownloadDirectory)
        return loadManifest(at: manifestPath(for: downloadDirectory)).installed
    }

    public static func resolveDownloadDirectory(_ explicitDownloadDirectory: String? = nil) -> String {
        if let explicitDownloadDirectory, !explicitDownloadDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return standardizedPath(explicitDownloadDirectory)
        }

        if let configured = ProcessInfo.processInfo.environment[downloadDirectoryEnvironmentKey]
            ?? ProcessInfo.processInfo.environment[legacyDownloadDirectoryEnvironmentKey],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return standardizedPath(configured)
        }

        return standardizedPath("~/.odyssey/local-agent/models/huggingface")
    }

    public static func manifestPath(for downloadDirectory: String) -> String {
        let root = URL(fileURLWithPath: standardizedPath(downloadDirectory))
            .deletingLastPathComponent()
        return root.appendingPathComponent("managed-models.json").path
    }

    public static func resolveRunner(_ explicitRunnerPath: String? = nil) -> String? {
        if let explicitRunnerPath {
            let standardized = standardizedPath(explicitRunnerPath)
            if isRunnableExecutable(atPath: standardized) {
                return standardized
            }
        }

        if let configured = ProcessInfo.processInfo.environment["ODYSSEY_MLX_RUNNER"]
           ?? ProcessInfo.processInfo.environment["CLAUDESTUDIO_MLX_RUNNER"],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let standardized = standardizedPath(configured)
            if isRunnableExecutable(atPath: standardized) {
                return standardized
            }
        }

        let managedRunnerPath = standardizedPath("~/.odyssey/local-agent/bin/llm-tool")
        if isRunnableExecutable(atPath: managedRunnerPath) {
            return managedRunnerPath
        }

        return resolveExecutable(named: "llm-tool")
    }

    public static func looksLikeLocalModelPath(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") || trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
            return true
        }
        return FileManager.default.fileExists(atPath: standardizedPath(trimmed))
    }

    public static func normalizeModelIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeLocalModelPath(trimmed) else {
            return nil
        }

        if let url = URL(string: trimmed),
           let host = url.host?.lowercased(),
           ["huggingface.co", "www.huggingface.co", "hf.co"].contains(host) {
            let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            guard components.count >= 2 else {
                return nil
            }
            return "\(components[0])/\(components[1])"
        }

        let slashComponents = trimmed.split(separator: "/").map(String.init)
        guard slashComponents.count == 2,
              slashComponents.allSatisfy({ component in
                  !component.isEmpty &&
                  component.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
              }) else {
            return nil
        }

        return "\(slashComponents[0])/\(slashComponents[1])"
    }

    @discardableResult
    public static func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        extraEnvironment: [String: String] = [:]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["PATH"]
            : "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ManagedMLXModelsError.installFailed(output)
        }
        return output
    }

    private static func loadManifest(at manifestPath: String) -> ManagedMLXManifest {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let manifest = try? JSONDecoder().decode(ManagedMLXManifest.self, from: data) else {
            return ManagedMLXManifest()
        }
        return manifest
    }

    private static func saveManifest(_ manifest: ManagedMLXManifest, to manifestPath: String) throws {
        let manifestURL = URL(fileURLWithPath: manifestPath)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.path
    }

    private static func sourceURL(from value: String) -> String? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(),
              ["huggingface.co", "www.huggingface.co", "hf.co"].contains(host) else {
            return nil
        }
        return url.absoluteString
    }

    private static func preferredManagedPath(for modelIdentifier: String, downloadDirectory: String) -> String {
        let components = modelIdentifier.split(separator: "/").map(String.init)
        return components.reduce(standardizedPath(downloadDirectory)) { partial, component in
            URL(fileURLWithPath: partial).appendingPathComponent(component).path
        }
    }

    private static func managedPathCandidates(for modelIdentifier: String, downloadDirectory: String) -> [String] {
        let standardizedDownloadDirectory = standardizedPath(downloadDirectory)
        let rootDirectory = standardizedPath(
            URL(fileURLWithPath: standardizedDownloadDirectory).deletingLastPathComponent().path
        )
        let namespacedCacheDirectory = "models--" + modelIdentifier.replacingOccurrences(of: "/", with: "--")
        return [
            preferredManagedPath(for: modelIdentifier, downloadDirectory: standardizedDownloadDirectory),
            URL(fileURLWithPath: standardizedDownloadDirectory).appendingPathComponent(namespacedCacheDirectory).path,
            URL(fileURLWithPath: rootDirectory).appendingPathComponent(namespacedCacheDirectory).path,
        ]
    }

    private static func firstExistingManagedPath(for modelIdentifier: String, downloadDirectory: String) -> String? {
        managedPathCandidates(for: modelIdentifier, downloadDirectory: downloadDirectory)
            .first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private static func isDescendant(_ path: String, ofAny roots: [String]) -> Bool {
        let standardized = standardizedPath(path)
        return roots.contains { root in
            let standardizedRoot = standardizedPath(root)
            return standardized == standardizedRoot || standardized.hasPrefix(standardizedRoot + "/")
        }
    }

    private static func removeEmptyAncestorDirectories(afterDeleting deletedPath: String, stopAt roots: [String]) {
        let fileManager = FileManager.default
        var current = URL(fileURLWithPath: deletedPath).deletingLastPathComponent().path

        while isDescendant(current, ofAny: roots) && !roots.map(standardizedPath).contains(standardizedPath(current)) {
            let contents = (try? fileManager.contentsOfDirectory(atPath: current)) ?? []
            guard contents.isEmpty else {
                break
            }
            try? fileManager.removeItem(atPath: current)
            current = URL(fileURLWithPath: current).deletingLastPathComponent().path
        }
    }

    private static func resolveExecutable(named command: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
        for entry in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent(command).path
            if isRunnableExecutable(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func isRunnableExecutable(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}
