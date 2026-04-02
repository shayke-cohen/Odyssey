import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct LocalProviderStatusReport: Equatable {
    let hostSummary: String
    let hostBinaryPath: String?
    let packagePath: String?
    let foundationAvailable: Bool
    let foundationSummary: String
    let mlxAvailable: Bool
    let mlxSummary: String
    let mlxRunnerPath: String?
    let mlxDownloadDirectory: String
    let installedMLXModels: [ManagedInstalledMLXModel]
}

enum LocalProviderSupport {
    static let bundledHostRelativePath = "local-agent/bin/OdysseyLocalAgentHost"
    static let packageRelativePath = "Packages/OdysseyLocalAgent"
    static let sidecarRelativePath = "sidecar/src/index.ts"
    static let sourceRootInfoKey = "ODYSSEY_SOURCE_ROOT"

    static func resolveHostBinaryPath(
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = nil,
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey)
    ) -> String? {
        if let override = normalizedFilePath(hostOverride) {
            return override
        }

        if let bundleResourcePath {
            let bundled = URL(fileURLWithPath: bundleResourcePath)
                .appendingPathComponent(bundledHostRelativePath)
                .path
            if FileManager.default.isExecutableFile(atPath: bundled) {
                return bundled
            }
        }

        return nil
    }

    static func resolvePackagePath(
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        bundledSourceRoot: String? = preferredBundledSourceRoot(),
        fallbackProjectRoots: [String]? = nil
    ) -> String? {
        let fileManager = FileManager.default
        let candidates = preferredProjectRoots(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            bundledSourceRoot: bundledSourceRoot,
            fallbackProjectRoots: fallbackProjectRoots
        )
            .map { URL(fileURLWithPath: $0).appendingPathComponent(packageRelativePath).path }

        for candidate in candidates where fileManager.fileExists(atPath: candidate) {
            return candidate
        }

        return nil
    }

    static func resolveSidecarPath(
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        bundledSourceRoot: String? = preferredBundledSourceRoot(),
        fallbackProjectRoots: [String]? = nil
    ) -> String? {
        let fileManager = FileManager.default

        if let bundleResourcePath {
            let bundledSidecarPath = URL(fileURLWithPath: bundleResourcePath)
                .appendingPathComponent(sidecarRelativePath)
                .path
            if fileManager.fileExists(atPath: bundledSidecarPath) {
                return bundledSidecarPath
            }
        }

        let candidatePaths = preferredProjectRoots(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            bundledSourceRoot: bundledSourceRoot,
            fallbackProjectRoots: fallbackProjectRoots
        )
            .map { URL(fileURLWithPath: $0).appendingPathComponent(sidecarRelativePath).path }

        for candidate in candidatePaths where fileManager.fileExists(atPath: candidate) {
            return candidate
        }

        return candidatePaths.first
    }

    static func resolveMLXRunnerPath(
        runnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> String? {
        if let override = normalizedFilePath(runnerOverride) {
            return override
        }

        if let managed = normalizedFilePath(
            LocalProviderInstaller.managedMLXRunnerInstallPath(dataDirectoryPath: dataDirectoryPath)
        ) {
            return managed
        }

        return resolveExecutable(named: "llm-tool", pathEnvironment: pathEnvironment)
    }

    static func environmentValues(
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey),
        mlxRunnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> [String: String] {
        var environment: [String: String] = [:]
        if let hostBinaryPath = resolveHostBinaryPath(
            bundleResourcePath: bundleResourcePath,
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            hostOverride: hostOverride
        ) {
            environment["ODYSSEY_LOCAL_AGENT_HOST_BINARY"] = hostBinaryPath
            environment["CLAUDESTUDIO_LOCAL_AGENT_HOST_BINARY"] = hostBinaryPath
        }

        if let packagePath = resolvePackagePath(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride
        ) {
            environment["ODYSSEY_LOCAL_AGENT_PACKAGE_PATH"] = packagePath
            environment["CLAUDESTUDIO_LOCAL_AGENT_PACKAGE_PATH"] = packagePath
        }

        if let mlxRunnerPath = resolveMLXRunnerPath(
            runnerOverride: mlxRunnerOverride,
            dataDirectoryPath: dataDirectoryPath
        ) {
            environment["ODYSSEY_MLX_RUNNER"] = mlxRunnerPath
            environment["CLAUDESTUDIO_MLX_RUNNER"] = mlxRunnerPath
        }
        let downloadDirectory = LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: dataDirectoryPath)
        environment["ODYSSEY_MLX_DOWNLOAD_DIR"] = downloadDirectory
        environment["CLAUDESTUDIO_MLX_DOWNLOAD_DIR"] = downloadDirectory

        return environment
    }

    static func statusReport(
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey),
        mlxRunnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        defaultMLXModel: String = InstanceConfig.userDefaults.string(forKey: AppSettings.defaultMLXModelKey) ?? AppSettings.defaultMLXModel
    ) -> LocalProviderStatusReport {
        let hostBinaryPath = resolveHostBinaryPath(
            bundleResourcePath: bundleResourcePath,
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            hostOverride: hostOverride
        )
        let packagePath = resolvePackagePath(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride
        )
        let mlxRunnerPath = resolveMLXRunnerPath(
            runnerOverride: mlxRunnerOverride,
            dataDirectoryPath: dataDirectoryPath
        )
        let mlxDownloadDirectory = LocalProviderInstaller.managedMLXDownloadDirectory(
            dataDirectoryPath: dataDirectoryPath
        )
        let installedMLXModels = LocalProviderInstaller.installedMLXModels(
            dataDirectoryPath: dataDirectoryPath
        )
        let hostSummary: String = {
            if let hostBinaryPath {
                return "Bundled local-agent host: \(hostBinaryPath)"
            }
            if let packagePath {
                return "Development package available at \(packagePath)"
            }
            return "Local-agent host not found. Build the app bundle or set a host override."
        }()

        let foundationStatus = foundationAvailability(hostBinaryPath: hostBinaryPath, packagePath: packagePath)
        let mlxStatus = mlxAvailability(
            hostBinaryPath: hostBinaryPath,
            packagePath: packagePath,
            mlxRunnerPath: mlxRunnerPath,
            defaultMLXModel: defaultMLXModel,
            installedModels: installedMLXModels,
            downloadDirectory: mlxDownloadDirectory
        )

        return LocalProviderStatusReport(
            hostSummary: hostSummary,
            hostBinaryPath: hostBinaryPath,
            packagePath: packagePath,
            foundationAvailable: foundationStatus.available,
            foundationSummary: foundationStatus.summary,
            mlxAvailable: mlxStatus.available,
            mlxSummary: mlxStatus.summary,
            mlxRunnerPath: mlxRunnerPath,
            mlxDownloadDirectory: mlxDownloadDirectory,
            installedMLXModels: installedMLXModels
        )
    }

    private static func foundationAvailability(hostBinaryPath: String?, packagePath: String?) -> (available: Bool, summary: String) {
        guard hostBinaryPath != nil || packagePath != nil else {
            return (false, "Local-agent host is not available yet.")
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if model.isAvailable {
                return (true, "Foundation Models is available on this Mac.")
            }

            return (false, foundationReason(for: model.availability))
        }
        #endif

        return (false, "Requires macOS 26+ with Apple Foundation Models support.")
    }

    private static func mlxAvailability(
        hostBinaryPath: String?,
        packagePath: String?,
        mlxRunnerPath: String?,
        defaultMLXModel: String,
        installedModels: [ManagedInstalledMLXModel],
        downloadDirectory: String
    ) -> (available: Bool, summary: String) {
        guard hostBinaryPath != nil || packagePath != nil else {
            return (false, "Local-agent host is not available yet.")
        }
        guard let mlxRunnerPath else {
            return (false, "Install the MLX runner from Settings or configure an existing llm-tool path.")
        }

        let trimmedModel = defaultMLXModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            return (false, "Set a default MLX model identifier or local path in Settings.")
        }

        if looksLikeLocalModelPath(trimmedModel) {
            let resolvedPath = normalizedDirectoryPath(trimmedModel) ?? trimmedModel
            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                return (false, "Configured MLX model path does not exist: \(resolvedPath)")
            }
            return (true, "MLX is ready using runner \(mlxRunnerPath) and local model path \(resolvedPath).")
        }

        if installedModels.contains(where: { $0.modelIdentifier == trimmedModel }) {
            return (true, "MLX is ready using runner \(mlxRunnerPath) with cached model \(trimmedModel).")
        }

        return (true, "MLX is configured with runner \(mlxRunnerPath). The model \(trimmedModel) will download into \(downloadDirectory) on first use, or you can install it now from Settings.")
    }

    private static func normalizedFilePath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        return FileManager.default.fileExists(atPath: standardized) ? standardized : nil
    }

    private static func normalizedDirectoryPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
            .standardizedFileURL
            .path
    }

    private static func preferredBundledSourceRoot(bundle: Bundle = .main) -> String? {
        normalizedDirectoryPath(bundle.object(forInfoDictionaryKey: sourceRootInfoKey) as? String)
    }

    private static func preferredProjectRoots(
        currentDirectoryPath: String,
        projectRootOverride: String?,
        bundledSourceRoot: String?,
        fallbackProjectRoots: [String]?
    ) -> [String] {
        let rawFallbacks = fallbackProjectRoots ?? [
            NSHomeDirectory().appending("/Odyssey"),
            NSHomeDirectory().appending("/ClaudPeer"),
        ]
        let rawCandidates = [
            projectRootOverride,
            bundledSourceRoot,
            currentDirectoryPath,
        ] + rawFallbacks

        var seen = Set<String>()
        return rawCandidates
            .compactMap { normalizedDirectoryPath($0) }
            .filter { seen.insert($0).inserted }
    }

    private static func looksLikeLocalModelPath(_ path: String) -> Bool {
        path.hasPrefix("/")
            || path.hasPrefix("~/")
            || path.hasPrefix("./")
            || path.hasPrefix("../")
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

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func foundationReason(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Foundation Models is available on this Mac."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac is not eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence to use Foundation Models."
            case .modelNotReady:
                return "The Apple on-device model is still preparing."
            @unknown default:
                return "Foundation Models is unavailable on this Mac."
            }
        }
    }
    #endif
}
