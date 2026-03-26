import SwiftUI
import SwiftData
import OSLog
#if DEBUG
import AppXray
#endif

@main
struct ClaudeStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var p2pNetworkManager = P2PNetworkManager()
    @State private var configSyncService = ConfigSyncService()
    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettings.autoConnectSidecarKey, store: AppSettings.store) private var autoConnectSidecar = true

    @Environment(\.openWindow) private var openWindow

    let modelContainer: ModelContainer
    private let launchIntent: LaunchIntent?

    init() {
        #if DEBUG
        AppXray.shared.start(appName: "ClaudeStudio")
        #endif

        InstanceConfig.ensureDirectories()

        do {
            let storeURL = InstanceConfig.dataDirectory.appendingPathComponent("ClaudeStudio.store")
            let config = ModelConfiguration(url: storeURL)
            let schema = Schema([
                Agent.self,
                Session.self,
                Conversation.self,
                ConversationMessage.self,
                MessageAttachment.self,
                Skill.self,
                MCPServer.self,
                PermissionSet.self,
                SharedWorkspace.self,
                BlackboardEntry.self,
                Peer.self,
                AgentGroup.self,
                TaskItem.self,
            ])
            modelContainer = try ModelContainer(
                for: schema,
                configurations: config
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        launchIntent = LaunchIntent.fromCommandLine()
    }

    private var resolvedColorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearance) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup("ClaudeStudio", for: String.self) { $projectDir in
            ProjectWindowContent(
                initialProjectDirectory: projectDir,
                appState: appState,
                p2pNetworkManager: p2pNetworkManager,
                configSyncService: $configSyncService,
                modelContainer: modelContainer,
                launchIntent: launchIntent,
                autoConnectSidecar: autoConnectSidecar,
                resolvedColorScheme: resolvedColorScheme,
                lastProjectDirectory: lastProjectDirectory
            )
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Project\u{2026}") {
                    // Open a new window with no project — shows the project picker
                    openWindow(value: "" as String)
                }
                .keyboardShortcut("o")
            }
            CommandMenu("Debug") {
                Button("Send Test Message") {
                    sendTestMessage()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Report a Bug...") {
                    if let url = URL(string: "https://forms.gle/Cq4bWNwUVaX8zZr67") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Window("Debug Log", id: "debug-log") {
            DebugLogView()
                .environmentObject(appState)
                .preferredColorScheme(resolvedColorScheme)
        }
        .defaultSize(width: 900, height: 600)
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(resolvedColorScheme)
        }
    }

    // MARK: - Recent project persistence

    private var lastProjectDirectory: String? {
        InstanceConfig.userDefaults.string(forKey: AppSettings.instanceWorkingDirectoryKey)
    }

    private func saveLastProjectDirectory(_ path: String) {
        InstanceConfig.userDefaults.set(path, forKey: AppSettings.instanceWorkingDirectoryKey)
    }

    // MARK: - Test

    @MainActor
    private func sendTestMessage() {
        let context = modelContainer.mainContext
        let conversation = Conversation(topic: "Test Chat")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        let testSession = Session(agent: nil, mode: .interactive, workingDirectory: lastProjectDirectory ?? NSHomeDirectory())
        testSession.conversations = [conversation]
        conversation.sessions.append(testSession)
        context.insert(testSession)

        let agentParticipant = Participant(
            type: .agentSession(sessionId: testSession.id),
            displayName: "Claude"
        )
        agentParticipant.conversation = conversation
        conversation.participants.append(agentParticipant)

        let userMessage = ConversationMessage(
            senderParticipantId: userParticipant.id,
            text: "What is 2+2? Reply with just the number.",
            type: .chat,
            conversation: conversation
        )
        conversation.messages.append(userMessage)

        context.insert(conversation)
        try? context.save()

        guard appState.sidecarStatus == .connected,
              let manager = appState.sidecarManager else {
            Log.general.warning("Sidecar not connected")
            return
        }

        let sessionId = testSession.id.uuidString
        let config = AgentConfig(
            name: "Claude",
            systemPrompt: "You are a helpful assistant. Be concise and clear.",
            allowedTools: [],
            mcpServers: [],
            model: "claude-sonnet-4-6",
            maxTurns: 1,
            maxBudget: nil,
            maxThinkingTokens: 10000,
            workingDirectory: lastProjectDirectory ?? NSHomeDirectory(),
            skills: []
        )

        appState.streamingText.removeValue(forKey: sessionId)
        appState.lastSessionEvent.removeValue(forKey: sessionId)

        Task {
            try? await manager.send(.sessionCreate(
                conversationId: sessionId,
                agentConfig: config
            ))
            try? await manager.send(.sessionMessage(
                sessionId: sessionId,
                text: "What is 2+2? Reply with just the number."
            ))
            Log.general.info("Sent test message for session \(sessionId, privacy: .public)")
        }
    }
}

// MARK: - Project Window Content

/// Wrapper view that creates and owns the WindowState for a project window.
/// Shows a project picker if no project directory is set yet.
private struct ProjectWindowContent: View {
    let initialProjectDirectory: String?
    let appState: AppState
    let p2pNetworkManager: P2PNetworkManager
    @Binding var configSyncService: ConfigSyncService
    let modelContainer: ModelContainer
    let launchIntent: LaunchIntent?
    let autoConnectSidecar: Bool
    let resolvedColorScheme: ColorScheme?
    let lastProjectDirectory: String?

    @State private var windowState: WindowState?
    @State private var chosenDirectory: String?
    @State private var hasInitialized = false

    private var effectiveDirectory: String? {
        // Empty string means "show picker" (from Cmd+O)
        if let chosen = chosenDirectory, !chosen.isEmpty { return chosen }
        if let initial = initialProjectDirectory, !initial.isEmpty { return initial }
        return lastProjectDirectory
    }

    var body: some View {
        Group {
            if let ws = windowState {
                MainWindowView()
                    .environment(ws)
            } else if effectiveDirectory != nil {
                ProgressView("Opening project\u{2026}")
            } else {
                ProjectPickerView { path in
                    chosenDirectory = path
                }
            }
        }
        .environmentObject(appState)
        .environmentObject(p2pNetworkManager)
        .preferredColorScheme(resolvedColorScheme)
        .onChange(of: effectiveDirectory) { _, newDir in
            if let dir = newDir, windowState == nil {
                initializeWindow(projectDirectory: dir)
            }
        }
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true

            // Boot shared services (only once across windows)
            appState.modelContext = modelContainer.mainContext
            appState.configSyncService = configSyncService
            configSyncService.start(container: modelContainer)

            if autoConnectSidecar, appState.sidecarStatus == .disconnected {
                appState.connectSidecar()
            }

            p2pNetworkManager.attach(modelContext: modelContainer.mainContext)
            p2pNetworkManager.sidecarManager = appState.sidecarManager
            p2pNetworkManager.setSidecarWsPort(appState.allocatedWsPort)
            p2pNetworkManager.start()

            #if DEBUG
            AppXray.shared.registerObservableObject(appState, name: "appState")
            #endif

            // If we already have a directory, initialize immediately
            if let dir = effectiveDirectory {
                initializeWindow(projectDirectory: dir)
            }
        }
        .onOpenURL { url in
            guard let ws = windowState else { return }
            if let intent = LaunchIntent.fromURL(url) {
                appState.executeLaunchIntent(intent, modelContext: modelContainer.mainContext, windowState: ws)
            }
        }
        .navigationTitle(windowState.map { "ClaudeStudio — \($0.projectName)" } ?? "ClaudeStudio")
    }

    private func initializeWindow(projectDirectory: String) {
        guard windowState == nil else { return }

        let ws = WindowState(projectDirectory: projectDirectory)
        ws.appState = appState
        windowState = ws

        // Save as last-used
        InstanceConfig.userDefaults.set(projectDirectory, forKey: AppSettings.instanceWorkingDirectoryKey)
        RecentDirectories.add(projectDirectory)

        // Execute launch intent if present
        if let intent = launchIntent {
            let ctx = modelContainer.mainContext
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                appState.executeLaunchIntent(intent, modelContext: ctx, windowState: ws)
            }
        }
    }
}

// MARK: - Project Picker View

/// Shown when a new window is opened without a project directory.
/// Embeds the shared ChangeProjectSheet inline (full-window, not as a sheet).
private struct ProjectPickerView: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Open a Project")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Choose a folder to work in. Each window is bound to a project.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .padding(.bottom, 8)

            ChangeProjectSheet(onSelect: onSelect)
                .frame(maxWidth: 500, maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
