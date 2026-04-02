import Foundation

public struct ManagedMLXModelPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String { modelIdentifier }
    public var modelIdentifier: String
    public var label: String
    public var summary: String
    public var recommended: Bool

    public init(modelIdentifier: String, label: String, summary: String, recommended: Bool) {
        self.modelIdentifier = modelIdentifier
        self.label = label
        self.summary = summary
        self.recommended = recommended
    }
}

public struct ManagedMLXInstalledModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String { modelIdentifier }
    public var modelIdentifier: String
    public var downloadDirectory: String
    public var installedAt: Date

    public init(modelIdentifier: String, downloadDirectory: String, installedAt: Date) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
        self.installedAt = installedAt
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

public enum ManagedMLXModelsError: LocalizedError {
    case missingRunner
    case invalidModelIdentifier
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingRunner:
            return "MLX runner not found. Install llm-tool or set CLAUDESTUDIO_MLX_RUNNER."
        case .invalidModelIdentifier:
            return "Enter a Hugging Face MLX model id to download, not a local path."
        case .installFailed(let output):
            return output.isEmpty ? "Failed to install the MLX model." : output
        }
    }
}

private struct ManagedMLXManifest: Codable {
    var installed: [ManagedMLXInstalledModel] = []
}

public enum ManagedMLXModels {
    public static let downloadDirectoryEnvironmentKey = "CLAUDESTUDIO_MLX_DOWNLOAD_DIR"

    public static func presets() -> [ManagedMLXModelPreset] {
        [
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                label: "Qwen2.5 1.5B Instruct",
                summary: "Balanced default for local chat and light coding tasks.",
                recommended: true
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen3-0.6B-4bit",
                label: "Qwen3 0.6B",
                summary: "Smallest recommended install for quick testing.",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                label: "Llama 3.2 3B Instruct",
                summary: "Larger local model for stronger general responses.",
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
        guard !trimmedModelIdentifier.isEmpty, !looksLikeLocalModelPath(trimmedModelIdentifier) else {
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
        if let installed = manifest.installed.first(where: { $0.modelIdentifier == trimmedModelIdentifier }) {
            return InstallMLXModelResult(
                modelIdentifier: trimmedModelIdentifier,
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
                "--model", trimmedModelIdentifier,
                "--download", downloadDirectory,
                "--prompt", "Hello",
                "--max-tokens", "1",
                "--quiet",
            ],
            extraEnvironment: [downloadDirectoryEnvironmentKey: downloadDirectory]
        )

        let installedAt = Date()
        var updatedManifest = manifest
        updatedManifest.installed.removeAll { $0.modelIdentifier == trimmedModelIdentifier }
        updatedManifest.installed.append(
            ManagedMLXInstalledModel(
                modelIdentifier: trimmedModelIdentifier,
                downloadDirectory: downloadDirectory,
                installedAt: installedAt
            )
        )
        updatedManifest.installed.sort { $0.modelIdentifier.localizedCaseInsensitiveCompare($1.modelIdentifier) == .orderedAscending }
        try saveManifest(updatedManifest, to: manifestPath)

        return InstallMLXModelResult(
            modelIdentifier: trimmedModelIdentifier,
            downloadDirectory: downloadDirectory,
            manifestPath: manifestPath,
            runnerPath: runnerPath,
            alreadyInstalled: false,
            output: output,
            installedAt: installedAt
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

        if let configured = ProcessInfo.processInfo.environment[downloadDirectoryEnvironmentKey],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return standardizedPath(configured)
        }

        return standardizedPath("~/.claudestudio/local-agent/models/huggingface")
    }

    public static func manifestPath(for downloadDirectory: String) -> String {
        let root = URL(fileURLWithPath: standardizedPath(downloadDirectory))
            .deletingLastPathComponent()
        return root.appendingPathComponent("managed-models.json").path
    }

    public static func resolveRunner(_ explicitRunnerPath: String? = nil) -> String? {
        if let explicitRunnerPath, FileManager.default.isExecutableFile(atPath: standardizedPath(explicitRunnerPath)) {
            return standardizedPath(explicitRunnerPath)
        }

        if let configured = ProcessInfo.processInfo.environment["CLAUDESTUDIO_MLX_RUNNER"],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let standardized = standardizedPath(configured)
            if FileManager.default.isExecutableFile(atPath: standardized) {
                return standardized
            }
        }

        let managedRunnerPath = standardizedPath("~/.claudestudio/local-agent/bin/llm-tool")
        if FileManager.default.isExecutableFile(atPath: managedRunnerPath) {
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

    private static func resolveExecutable(named command: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
        for entry in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
