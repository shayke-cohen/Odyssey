import Combine
import Foundation
import OSLog

@MainActor
final class SidecarManager: ObservableObject, Sendable {
    struct Config: Sendable {
        var wsPort: Int = 9849
        var httpPort: Int = 9850
        var logDirectory: String?
        var dataDirectory: String?
        var bunPathOverride: String?
        var sidecarPathOverride: String?
        var localAgentHostPathOverride: String?
        var mlxRunnerPathOverride: String?
    }

    private var process: Process?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var eventContinuation: AsyncStream<SidecarEvent>.Continuation?
    private var isRunning = false
    private var isReconnecting = false
    private var pingTask: Task<Void, Never>?
    private let config: Config

    var events: AsyncStream<SidecarEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    nonisolated init(config: Config = Config()) {
        self.config = config
    }

    func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        // Try connecting to an existing sidecar first
        do {
            try await connectWebSocket()
            return
        } catch {
            // No existing sidecar, launch a new one
        }

        try launchSidecar()

        // Retry connecting with backoff — sidecar may take a moment to bind the port
        var connected = false
        for attempt in 1...5 {
            try await Task.sleep(for: .milliseconds(attempt == 1 ? 800 : 1500))
            do {
                try await connectWebSocket()
                connected = true
                break
            } catch {
                Log.sidecar.warning("Connect attempt \(attempt)/5 failed: \(error.localizedDescription)")
            }
        }
        guard connected else {
            throw SidecarError.notConnected
        }
    }

    func stop() {
        isRunning = false
        pingTask?.cancel()
        pingTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        process?.terminate()
        process = nil
        eventContinuation?.yield(.disconnected)
        eventContinuation?.finish()
    }

    enum SidecarError: Error, LocalizedError {
        case notConnected
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Sidecar not connected"
            case .encodingFailed: return "Failed to encode command"
            }
        }
    }

    func send(_ command: SidecarCommand) async throws {
        let data = try command.encodeToJSON()
        guard let text = String(data: data, encoding: .utf8) else {
            throw SidecarError.encodingFailed
        }
        guard let task = webSocketTask else {
            throw SidecarError.notConnected
        }
        try await task.send(.string(text))
    }

    private func launchSidecar() throws {
        let bunPath = findBunPath()
        let sidecarPath = findSidecarPath()
        Log.sidecar.info("Bun: \(bunPath, privacy: .public)")
        Log.sidecar.info("Sidecar: \(sidecarPath, privacy: .public)")
        Log.sidecar.info("Sidecar exists: \(FileManager.default.fileExists(atPath: sidecarPath))")
        Log.sidecar.info("Bun exists: \(FileManager.default.fileExists(atPath: bunPath))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bunPath)
        process.arguments = ["run", sidecarPath]
        process.environment = normalizedEnvironment()
        process.environment?["ODYSSEY_WS_PORT"] = "\(config.wsPort)"
        process.environment?["ODYSSEY_HTTP_PORT"] = "\(config.httpPort)"
        process.environment?["CLAUDESTUDIO_WS_PORT"] = "\(config.wsPort)"
        process.environment?["CLAUDESTUDIO_HTTP_PORT"] = "\(config.httpPort)"
        if let dataDir = config.dataDirectory {
            process.environment?["ODYSSEY_DATA_DIR"] = dataDir
            process.environment?["CLAUDESTUDIO_DATA_DIR"] = dataDir
        }
        for (key, value) in localProviderEnvironment() {
            process.environment?[key] = value
        }
        let logLevel = InstanceConfig.userDefaults.string(forKey: AppSettings.logLevelKey) ?? AppSettings.defaultLogLevel
        process.environment?["ODYSSEY_LOG_LEVEL"] = logLevel
        process.environment?["CLAUDESTUDIO_LOG_LEVEL"] = logLevel

        let logDir = config.logDirectory ?? "\(NSHomeDirectory())/.odyssey/instances/default/logs"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let logFile = "\(logDir)/sidecar.log"
        FileManager.default.createFile(atPath: logFile, contents: nil)
        let logHandle = FileHandle(forWritingAtPath: logFile)
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        process.standardError = logHandle ?? FileHandle.nullDevice

        process.terminationHandler = { [weak self] proc in
            Log.sidecar.warning("Process exited with code \(proc.terminationStatus)")
            Task { @MainActor in
                self?.handleProcessTermination()
            }
        }

        try process.run()
        self.process = process
        Log.sidecar.info("Launched PID \(process.processIdentifier)")
    }

    private func normalizedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        let home = environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["HOME"]!
            : NSHomeDirectory()
        let user = environment["USER"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["USER"]!
            : NSUserName()
        let logname = environment["LOGNAME"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["LOGNAME"]!
            : user
        let shell = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["SHELL"]!
            : "/bin/zsh"

        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let currentPath = environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        environment["HOME"] = home
        environment["USER"] = user
        environment["LOGNAME"] = logname
        environment["SHELL"] = shell
        environment["PATH"] = currentPath.isEmpty ? defaultPath : [defaultPath, currentPath]
            .joined(separator: ":")

        return environment
    }

    private func localProviderEnvironment() -> [String: String] {
        LocalProviderSupport.environmentValues(
            bundleResourcePath: Bundle.main.resourcePath,
            currentDirectoryPath: FileManager.default.currentDirectoryPath,
            projectRootOverride: config.sidecarPathOverride,
            hostOverride: config.localAgentHostPathOverride,
            mlxRunnerOverride: config.mlxRunnerPathOverride
        )
    }

    private func connectWebSocket() async throws {
        // Cancel any previous connection attempt
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        urlSession?.invalidateAndCancel()

        let url = URL(string: "ws://localhost:\(config.wsPort)")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        self.urlSession = session
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        // Verify connection by receiving the sidecar.ready message
        let message = try await task.receive()
        if case .string(let text) = message {
            Log.sidecar.debug("Handshake received: \(text.prefix(80), privacy: .public)")
        }

        eventContinuation?.yield(.connected)
        receiveMessages()
        startPingPong()
    }

    private func startPingPong() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                self?.webSocketTask?.sendPing { error in
                    if let error {
                        Log.sidecar.warning("Ping failed: \(error)")
                    }
                }
            }
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessages()
                case .failure:
                    self?.eventContinuation?.yield(.disconnected)
                    self?.attemptReconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        guard let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data),
              let event = wire.toEvent() else { return }
        eventContinuation?.yield(event)
    }

    private func handleProcessTermination() {
        guard isRunning else { return }
        eventContinuation?.yield(.disconnected)
        attemptReconnect()
    }

    private func attemptReconnect() {
        guard isRunning, !isReconnecting else { return }
        isReconnecting = true
        Task {
            defer { Task { @MainActor in self.isReconnecting = false } }
            try await Task.sleep(for: .seconds(2))
            guard isRunning else { return }

            // Try connecting to an existing sidecar first (e.g. one that survived a UI restart)
            do {
                try await connectWebSocket()
                return
            } catch {
                // No existing sidecar, launch a new one
            }

            do {
                try launchSidecar()
                try await Task.sleep(for: .milliseconds(800))
                try await connectWebSocket()
            } catch {
                Log.sidecar.error("Reconnect failed: \(error). Will retry in 5s.")
                try? await Task.sleep(for: .seconds(5))
                Task { @MainActor in self.attemptReconnect() }
            }
        }
    }

    private func findBunPath() -> String {
        if let override = config.bunPathOverride,
           FileManager.default.fileExists(atPath: override) {
            return override
        }
        let candidates = [
            "/opt/homebrew/bin/bun",
            "/usr/local/bin/bun",
            "\(NSHomeDirectory())/.bun/bin/bun",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return "bun"
    }

    private func findSidecarPath() -> String {
        LocalProviderSupport.resolveSidecarPath(
            bundleResourcePath: Bundle.main.resourcePath,
            currentDirectoryPath: FileManager.default.currentDirectoryPath,
            projectRootOverride: config.sidecarPathOverride
        ) ?? "\(NSHomeDirectory())/Odyssey/sidecar/src/index.ts"
    }
}
