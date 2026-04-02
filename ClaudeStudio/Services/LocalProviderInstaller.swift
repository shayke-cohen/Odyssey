import Foundation

enum LocalProviderInstallerError: LocalizedError {
    case missingExecutable(name: String)
    case missingHost
    case cloneFailed(String)
    case buildFailed(String)
    case binaryNotFound(String)
    case invalidModelIdentifier
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let name):
            return "Required executable not found: \(name). Install Xcode command line tools and try again."
        case .missingHost:
            return "ClaudeStudio local-agent host is not available. Build the app bundle or configure a host override."
        case .cloneFailed(let output):
            return output.isEmpty ? "Failed to download the MLX runner sources." : output
        case .buildFailed(let output):
            return output.isEmpty ? "Failed to build the MLX runner." : output
        case .binaryNotFound(let path):
            return "Built MLX runner was not found at \(path)."
        case .invalidModelIdentifier:
            return "Enter a Hugging Face MLX model id to download, not a local path."
        case .installFailed(let output):
            return output.isEmpty ? "Failed to install the MLX model." : output
        }
    }
}

struct ManagedInstalledMLXModel: Codable, Equatable, Identifiable {
    var id: String { modelIdentifier }
    let modelIdentifier: String
    let downloadDirectory: String
    let installedAt: Date
}

struct ManagedInstalledMLXManifest: Codable, Equatable {
    var installed: [ManagedInstalledMLXModel] = []
}

struct ManagedMLXInstallResult: Codable, Equatable {
    let modelIdentifier: String
    let downloadDirectory: String
    let manifestPath: String
    let runnerPath: String
    let alreadyInstalled: Bool
    let output: String
    let installedAt: Date
}

enum LocalProviderInstaller {
    static let managedToolsRelativePath = "local-agent"
    static let managedMLXSourceRelativePath = "local-agent/mlx-swift-examples"
    static let managedMLXBinaryRelativePath = "local-agent/bin/llm-tool"
    static let managedMLXRuntimeRelativePath = "local-agent/runtime/llm-tool-release"
    static let managedMLXDownloadRelativePath = "local-agent/models/huggingface"
    static let managedMLXManifestRelativePath = "local-agent/models/managed-models.json"
    static let mlxSwiftExamplesURL = "https://github.com/ml-explore/mlx-swift-examples.git"

    static func managedToolsDirectory(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedToolsRelativePath)")
    }

    static func managedMLXSourceDirectory(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXSourceRelativePath)")
    }

    static func managedMLXRunnerInstallPath(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXBinaryRelativePath)")
    }

    static func managedMLXDownloadDirectory(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXDownloadRelativePath)")
    }

    static func managedMLXRuntimeDirectory(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXRuntimeRelativePath)")
    }

    static func managedMLXManifestPath(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXManifestRelativePath)")
    }

    static func installMLXRunner(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) async throws -> String {
        let fileManager = FileManager.default
        let sourceDirectory = managedMLXSourceDirectory(dataDirectoryPath: dataDirectoryPath)
        let installPath = managedMLXRunnerInstallPath(dataDirectoryPath: dataDirectoryPath)
        let installDirectory = URL(fileURLWithPath: installPath).deletingLastPathComponent().path

        try fileManager.createDirectory(atPath: installDirectory, withIntermediateDirectories: true)

        let git = try requiredExecutable(named: "git", pathEnvironment: pathEnvironment)
        let xcodebuild = try requiredExecutable(named: "xcodebuild", pathEnvironment: pathEnvironment)

        if !fileManager.fileExists(atPath: sourceDirectory) {
            let checkoutParent = URL(fileURLWithPath: sourceDirectory).deletingLastPathComponent().path
            try fileManager.createDirectory(atPath: checkoutParent, withIntermediateDirectories: true)
            let cloneOutput = try runCommand(
                executable: git,
                arguments: ["clone", "--depth", "1", mlxSwiftExamplesURL, sourceDirectory],
                currentDirectory: checkoutParent,
                pathEnvironment: pathEnvironment
            )
            if !fileManager.fileExists(atPath: sourceDirectory) {
                throw LocalProviderInstallerError.cloneFailed(cloneOutput)
            }
        }

        let derivedDataPath = URL(fileURLWithPath: sourceDirectory)
            .appendingPathComponent(".claudestudio-derived")
            .path

        _ = try runCommand(
            executable: xcodebuild,
            arguments: [
                "-project", "mlx-swift-examples.xcodeproj",
                "-scheme", "llm-tool",
                "-configuration", "Release",
                "-derivedDataPath", derivedDataPath,
                "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO",
                "build",
            ],
            currentDirectory: sourceDirectory,
            pathEnvironment: pathEnvironment
        )

        let builtProductsDirectory = URL(fileURLWithPath: derivedDataPath)
            .appendingPathComponent("Build/Products/Release")
            .path
        try installBuiltMLXRunnerProducts(
            builtProductsDirectory: builtProductsDirectory,
            installPath: installPath,
            dataDirectoryPath: dataDirectoryPath
        )
        return installPath
    }

    static func installMLXModel(
        modelIdentifier: String,
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey),
        runnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) async throws -> ManagedMLXInstallResult {
        let trimmedModelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelIdentifier.isEmpty, !looksLikeLocalModelPath(trimmedModelIdentifier) else {
            throw LocalProviderInstallerError.invalidModelIdentifier
        }

        let runnerPath = try await ensureMLXRunner(
            dataDirectoryPath: dataDirectoryPath,
            runnerOverride: runnerOverride,
            pathEnvironment: pathEnvironment
        )
        let downloadDirectory = managedMLXDownloadDirectory(dataDirectoryPath: dataDirectoryPath)

        if let hostBinaryPath = LocalProviderSupport.resolveHostBinaryPath(
            bundleResourcePath: bundleResourcePath,
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            hostOverride: hostOverride
        ) {
            let output = try runCommand(
                executable: hostBinaryPath,
                arguments: [
                    "install-model",
                    "--model", trimmedModelIdentifier,
                    "--download-dir", downloadDirectory,
                    "--runner", runnerPath,
                    "--json",
                ],
                currentDirectory: currentDirectoryPath,
                pathEnvironment: pathEnvironment,
                extraEnvironment: ["CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory]
            )

            guard let data = output.data(using: .utf8) else {
                throw LocalProviderInstallerError.installFailed(output)
            }
            return try JSONDecoder().decode(ManagedMLXInstallResult.self, from: data)
        }

        guard let packagePath = LocalProviderSupport.resolvePackagePath(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride
        ) else {
            throw LocalProviderInstallerError.missingHost
        }

        let xcrun = try requiredExecutable(named: "xcrun", pathEnvironment: pathEnvironment)
        let output = try runCommand(
            executable: xcrun,
            arguments: [
                "swift", "run", "--package-path", packagePath, "ClaudeStudioLocalAgentHost",
                "install-model",
                "--model", trimmedModelIdentifier,
                "--download-dir", downloadDirectory,
                "--runner", runnerPath,
                "--json",
            ],
            currentDirectory: packagePath,
            pathEnvironment: pathEnvironment,
            extraEnvironment: ["CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory]
        )
        guard let data = output.data(using: .utf8) else {
            throw LocalProviderInstallerError.installFailed(output)
        }
        return try JSONDecoder().decode(ManagedMLXInstallResult.self, from: data)
    }

    static func installedMLXModels(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> [ManagedInstalledMLXModel] {
        let manifestPath = managedMLXManifestPath(dataDirectoryPath: dataDirectoryPath)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let manifest = try? JSONDecoder().decode(ManagedInstalledMLXManifest.self, from: data) else {
            return []
        }
        return manifest.installed.sorted { $0.modelIdentifier.localizedCaseInsensitiveCompare($1.modelIdentifier) == .orderedAscending }
    }

    private static func expandedDirectoryPath(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            .standardizedFileURL
            .path
    }

    private static func requiredExecutable(named name: String, pathEnvironment: String) throws -> String {
        if let resolved = resolveExecutable(named: name, pathEnvironment: pathEnvironment) {
            return resolved
        }
        throw LocalProviderInstallerError.missingExecutable(name: name)
    }

    private static func resolveExecutable(named executableName: String, pathEnvironment: String) -> String? {
        for entry in pathEnvironment.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent(executableName).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    @discardableResult
    private static func runCommand(
        executable: String,
        arguments: [String],
        currentDirectory: String,
        pathEnvironment: String,
        extraEnvironment: [String: String] = [:]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = pathEnvironment
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            if arguments.contains("clone") {
                throw LocalProviderInstallerError.cloneFailed(output)
            }
            throw LocalProviderInstallerError.buildFailed(output)
        }

        return output
    }

    private static func ensureMLXRunner(
        dataDirectoryPath: String,
        runnerOverride: String?,
        pathEnvironment: String
    ) async throws -> String {
        if let resolved = LocalProviderSupport.resolveMLXRunnerPath(
            runnerOverride: runnerOverride,
            dataDirectoryPath: dataDirectoryPath,
            pathEnvironment: pathEnvironment
        ) {
            return resolved
        }

        return try await installMLXRunner(
            dataDirectoryPath: dataDirectoryPath,
            pathEnvironment: pathEnvironment
        )
    }

    private static func looksLikeLocalModelPath(_ value: String) -> Bool {
        if value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("./") || value.hasPrefix("../") {
            return true
        }
        return FileManager.default.fileExists(atPath: expandedDirectoryPath(value))
    }

    static func installBuiltMLXRunnerProducts(
        builtProductsDirectory: String,
        installPath: String,
        dataDirectoryPath: String
    ) throws {
        let fileManager = FileManager.default
        let runtimeDirectory = managedMLXRuntimeDirectory(dataDirectoryPath: dataDirectoryPath)
        let builtProductsURL = URL(fileURLWithPath: builtProductsDirectory)
        let builtBinaryPath = builtProductsURL.appendingPathComponent("llm-tool").path

        guard fileManager.isExecutableFile(atPath: builtBinaryPath) else {
            throw LocalProviderInstallerError.binaryNotFound(builtBinaryPath)
        }

        let installDirectory = URL(fileURLWithPath: installPath).deletingLastPathComponent().path
        try fileManager.createDirectory(atPath: installDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: runtimeDirectory) {
            try fileManager.removeItem(atPath: runtimeDirectory)
        }
        try fileManager.createDirectory(atPath: runtimeDirectory, withIntermediateDirectories: true)

        try copyItem(at: builtBinaryPath, intoDirectory: runtimeDirectory, fileManager: fileManager)

        let builtItems = try fileManager.contentsOfDirectory(atPath: builtProductsDirectory)
        for item in builtItems where item == "PackageFrameworks" || item.hasSuffix(".bundle") {
            try copyItem(
                at: builtProductsURL.appendingPathComponent(item).path,
                intoDirectory: runtimeDirectory,
                fileManager: fileManager
            )
        }

        if fileManager.fileExists(atPath: installPath) {
            try fileManager.removeItem(atPath: installPath)
        }
        try managedMLXWrapperScript().write(
            to: URL(fileURLWithPath: installPath),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installPath)
    }

    static func managedMLXWrapperScript() -> String {
        """
        #!/bin/sh
        set -e

        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
        RUNTIME_DIR="$SCRIPT_DIR/../runtime/llm-tool-release"

        if [ ! -x "$RUNTIME_DIR/llm-tool" ]; then
          echo "Managed MLX runner is incomplete at $RUNTIME_DIR" >&2
          exit 1
        fi

        if [ -d "$RUNTIME_DIR/PackageFrameworks" ]; then
          export DYLD_FRAMEWORK_PATH="$RUNTIME_DIR/PackageFrameworks:$RUNTIME_DIR${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
        else
          export DYLD_FRAMEWORK_PATH="$RUNTIME_DIR${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
        fi

        exec "$RUNTIME_DIR/llm-tool" "$@"
        """
    }

    private static func copyItem(
        at sourcePath: String,
        intoDirectory destinationDirectory: String,
        fileManager: FileManager
    ) throws {
        let destinationPath = URL(fileURLWithPath: destinationDirectory)
            .appendingPathComponent(URL(fileURLWithPath: sourcePath).lastPathComponent)
            .path

        if fileManager.fileExists(atPath: destinationPath) {
            try fileManager.removeItem(atPath: destinationPath)
        }
        try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
    }
}
