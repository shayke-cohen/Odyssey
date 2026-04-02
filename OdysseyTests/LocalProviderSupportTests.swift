import Foundation
import XCTest
@testable import Odyssey

final class LocalProviderSupportTests: XCTestCase {
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

    func testResolveHostBinaryPathPrefersBundledExecutable() throws {
        let resourceDirectory = tempDirectory.appendingPathComponent("Resources")
        let hostDirectory = resourceDirectory.appendingPathComponent("local-agent/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        let hostPath = hostDirectory.appendingPathComponent("OdysseyLocalAgentHost")
        FileManager.default.createFile(atPath: hostPath.path, contents: Data("echo host".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostPath.path)

        let resolved = LocalProviderSupport.resolveHostBinaryPath(
            bundleResourcePath: resourceDirectory.path,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: nil,
            hostOverride: nil
        )

        XCTAssertEqual(resolved, hostPath.path)
    }

    func testResolvePackagePathFindsPackageUnderProjectOverride() throws {
        let projectRoot = tempDirectory.appendingPathComponent("Project")
        let packageDirectory = projectRoot.appendingPathComponent("Packages/OdysseyLocalAgent", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)

        let resolved = LocalProviderSupport.resolvePackagePath(
            currentDirectoryPath: "/tmp/does-not-exist",
            projectRootOverride: projectRoot.path
        )

        XCTAssertEqual(resolved, packageDirectory.path)
    }

    func testResolvePackagePathPrefersBundledSourceRootOverFallbackRoots() throws {
        let fallbackRoot = tempDirectory.appendingPathComponent("LegacyWorkspace")
        let bundledRoot = tempDirectory.appendingPathComponent("CurrentWorkspace")
        try FileManager.default.createDirectory(
            at: fallbackRoot.appendingPathComponent("Packages/OdysseyLocalAgent", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bundledRoot.appendingPathComponent("Packages/OdysseyLocalAgent", isDirectory: true),
            withIntermediateDirectories: true
        )

        let resolved = LocalProviderSupport.resolvePackagePath(
            currentDirectoryPath: "/tmp/does-not-exist",
            projectRootOverride: nil,
            bundledSourceRoot: bundledRoot.path,
            fallbackProjectRoots: [fallbackRoot.path]
        )

        XCTAssertEqual(
            resolved,
            bundledRoot.appendingPathComponent("Packages/OdysseyLocalAgent").path
        )
    }

    func testResolveSidecarPathPrefersBundledSourceRootOverFallbackRoots() throws {
        let fallbackRoot = tempDirectory.appendingPathComponent("LegacyWorkspace")
        let bundledRoot = tempDirectory.appendingPathComponent("CurrentWorkspace")
        try makeSidecarWorkspace(at: fallbackRoot)
        try makeSidecarWorkspace(at: bundledRoot)

        let resolved = LocalProviderSupport.resolveSidecarPath(
            bundleResourcePath: nil,
            currentDirectoryPath: "/tmp/does-not-exist",
            projectRootOverride: nil,
            bundledSourceRoot: bundledRoot.path,
            fallbackProjectRoots: [fallbackRoot.path]
        )

        XCTAssertEqual(
            resolved,
            bundledRoot.appendingPathComponent("sidecar/src/index.ts").path
        )
    }

    func testEnvironmentValuesIncludeDetectedAssets() throws {
        let resourceDirectory = tempDirectory.appendingPathComponent("Resources")
        let hostDirectory = resourceDirectory.appendingPathComponent("local-agent/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        let hostPath = hostDirectory.appendingPathComponent("OdysseyLocalAgentHost")
        FileManager.default.createFile(atPath: hostPath.path, contents: Data("echo host".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostPath.path)

        let runnerPath = tempDirectory.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: runnerPath.path, contents: Data("echo runner".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerPath.path)

        let environment = LocalProviderSupport.environmentValues(
            bundleResourcePath: resourceDirectory.path,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: nil,
            hostOverride: nil,
            mlxRunnerOverride: runnerPath.path,
            dataDirectoryPath: tempDirectory.path
        )

        XCTAssertEqual(environment["ODYSSEY_LOCAL_AGENT_HOST_BINARY"], hostPath.path)
        XCTAssertEqual(environment["ODYSSEY_MLX_RUNNER"], runnerPath.path)
        XCTAssertEqual(
            environment["ODYSSEY_MLX_DOWNLOAD_DIR"],
            LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: tempDirectory.path)
        )
    }

    func testResolveMLXRunnerPathPrefersManagedInstallLocation() throws {
        let managedRunnerPath = URL(fileURLWithPath: LocalProviderInstaller.managedMLXRunnerInstallPath(
            dataDirectoryPath: tempDirectory.path
        ))
        try FileManager.default.createDirectory(
            at: managedRunnerPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: managedRunnerPath.path, contents: Data("echo runner".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedRunnerPath.path)

        let resolved = LocalProviderSupport.resolveMLXRunnerPath(
            runnerOverride: nil,
            dataDirectoryPath: tempDirectory.path,
            pathEnvironment: ""
        )

        XCTAssertEqual(resolved, managedRunnerPath.path)
    }

    func testStatusReportMarksCachedManagedModelAsReady() throws {
        let resourceDirectory = tempDirectory.appendingPathComponent("Resources")
        let hostDirectory = resourceDirectory.appendingPathComponent("local-agent/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        let hostPath = hostDirectory.appendingPathComponent("OdysseyLocalAgentHost")
        FileManager.default.createFile(atPath: hostPath.path, contents: Data("echo host".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostPath.path)

        let runnerPath = tempDirectory.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: runnerPath.path, contents: Data("echo runner".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerPath.path)

        let manifest = ManagedInstalledMLXManifest(installed: [
            ManagedInstalledMLXModel(
                modelIdentifier: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                downloadDirectory: LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: tempDirectory.path),
                installedAt: Date()
            )
        ])
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestURL = URL(fileURLWithPath: LocalProviderInstaller.managedMLXManifestPath(dataDirectoryPath: tempDirectory.path))
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manifestData.write(to: manifestURL)

        let report = LocalProviderSupport.statusReport(
            bundleResourcePath: resourceDirectory.path,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: nil,
            hostOverride: nil,
            mlxRunnerOverride: runnerPath.path,
            dataDirectoryPath: tempDirectory.path,
            defaultMLXModel: "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        )

        XCTAssertTrue(report.mlxAvailable)
        XCTAssertTrue(report.mlxSummary.contains("cached model"))
        XCTAssertEqual(report.installedMLXModels.map(\.modelIdentifier), ["mlx-community/Qwen2.5-1.5B-Instruct-4bit"])
    }

    func testInstallBuiltMLXRunnerProductsCreatesManagedWrapperAndRuntime() throws {
        let builtProducts = tempDirectory.appendingPathComponent("BuildProducts", isDirectory: true)
        try FileManager.default.createDirectory(at: builtProducts, withIntermediateDirectories: true)

        let builtBinary = builtProducts.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: builtBinary.path, contents: Data("#!/bin/sh\necho live-runner\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: builtBinary.path)

        let packageFrameworks = builtProducts.appendingPathComponent("PackageFrameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: packageFrameworks, withIntermediateDirectories: true)
        let frameworkMarker = packageFrameworks.appendingPathComponent("marker.txt")
        try "framework".write(to: frameworkMarker, atomically: true, encoding: .utf8)

        let bundle = builtProducts.appendingPathComponent("mlx-swift_Cmlx.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "bundle".write(
            to: bundle.appendingPathComponent("payload.txt"),
            atomically: true,
            encoding: .utf8
        )

        let installPath = LocalProviderInstaller.managedMLXRunnerInstallPath(dataDirectoryPath: tempDirectory.path)
        try LocalProviderInstaller.installBuiltMLXRunnerProducts(
            builtProductsDirectory: builtProducts.path,
            installPath: installPath,
            dataDirectoryPath: tempDirectory.path
        )

        let runtimeDirectory = URL(fileURLWithPath: LocalProviderInstaller.managedMLXRuntimeDirectory(dataDirectoryPath: tempDirectory.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installPath))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: runtimeDirectory.appendingPathComponent("llm-tool").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeDirectory.appendingPathComponent("PackageFrameworks/marker.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeDirectory.appendingPathComponent("mlx-swift_Cmlx.bundle/payload.txt").path))

        let wrapperScript = try String(contentsOfFile: installPath, encoding: .utf8)
        XCTAssertTrue(wrapperScript.contains("DYLD_FRAMEWORK_PATH"))
        XCTAssertTrue(wrapperScript.contains("../runtime/llm-tool-release"))
    }

    private func makeSidecarWorkspace(at root: URL) throws {
        let sidecarDirectory = root.appendingPathComponent("sidecar/src", isDirectory: true)
        try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: sidecarDirectory.appendingPathComponent("index.ts").path,
            contents: Data("export {};".utf8)
        )
    }
}
