import SwiftUI
import SwiftData

struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var p2pNetworkManager: P2PNetworkManager
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showStatusPopover = false
    @State private var inspectorVisible = true

    var body: some View {
        @Bindable var ws = windowState
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            Group {
                if inspectorVisible && windowState.selectedConversationId != nil {
                    HSplitView {
                        mainDetailPane
                            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                        inspectorPane
                            .frame(minWidth: 220, idealWidth: 380, maxWidth: 720, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SplitViewConfigurator(autosaveName: "claudestudio.chatInspectorSplit"))
                    .xrayId("mainWindow.chatInspectorSplit")
                } else {
                    mainDetailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowTitleSetter(projectName: windowState.projectName))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    windowState.showNewSessionSheet = true
                } label: {
                    Label("New Session", systemImage: "plus.bubble")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New session (⌘N)")
                .xrayId("mainWindow.newSessionButton")

                Button {
                    createQuickChat()
                } label: {
                    Label("Quick Chat", systemImage: "plus.message")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Quick chat (⌘⇧N)")
                .xrayId("mainWindow.quickChatButton")
            }

            ToolbarItem(placement: .status) {
                sidecarStatusPill
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    windowState.showAgentComms = true
                } label: {
                    Label("Agent Comms", systemImage: "antenna.radiowaves.left.and.right")
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Agent comms (⌘⇧A)")
                .xrayId("mainWindow.agentCommsButton")
                .badge(appState.commsEvents.count)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    windowState.showPeerNetwork = true
                } label: {
                    Label("Peer Network", systemImage: "network")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("Peer network (⌘⇧P)")
                .xrayId("mainWindow.peerNetworkButton")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: "debug-log")
                } label: {
                    Label("Debug Log", systemImage: "ladybug")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("Debug log (⌘⇧D)")
                .xrayId("mainWindow.debugLogButton")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    inspectorVisible.toggle()
                } label: {
                    Label(
                        inspectorVisible ? "Hide Inspector" : "Show Inspector",
                        systemImage: "sidebar.trailing"
                    )
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .help(inspectorVisible ? "Hide inspector (⌘⌥0)" : "Show inspector (⌘⌥0)")
                .xrayId("mainWindow.inspectorToggle")
            }
        }
        .sheet(isPresented: $ws.showNewSessionSheet) {
            NewSessionSheet()
        }
        .sheet(isPresented: $ws.showAgentLibrary) {
            AgentLibraryView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(isPresented: $ws.showGroupLibrary) {
            GroupLibraryView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(isPresented: $ws.showAgentComms) {
            AgentCommsView()
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(isPresented: $ws.showPeerNetwork) {
            PeerNetworkView()
                .environmentObject(p2pNetworkManager)
                .environment(\.modelContext, modelContext)
        }
        .sheet(isPresented: $ws.showWorkshop) {
            WorkshopView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 640)
        }
        .onAppear {
            appState.connectSidecar()
        }
        .alert("Launch Error", isPresented: launchErrorBinding) {
            Button("OK") { windowState.launchError = nil }
        } message: {
            Text(windowState.launchError ?? "")
        }
    }

    private var launchErrorBinding: Binding<Bool> {
        Binding(
            get: { windowState.launchError != nil },
            set: { if !$0 { windowState.launchError = nil } }
        )
    }

    // MARK: - Detail panes

    @ViewBuilder
    private var mainDetailPane: some View {
        if let conversationId = windowState.selectedConversationId {
            ChatView(conversationId: conversationId)
                .id(conversationId)
        } else if let groupId = windowState.selectedGroupId {
            GroupDetailView(groupId: groupId)
                .id(groupId)
        } else {
            WelcomeView(
                onQuickChat: { createQuickChat() },
                onStartAgent: { agent in startSessionWithAgent(agent) },
                onStartGroup: { group in startGroupChat(group) }
            )
            .xrayId("mainWindow.welcomeView")
        }
    }

    @ViewBuilder
    private var inspectorPane: some View {
        if let conversationId = windowState.selectedConversationId {
            InspectorView(conversationId: conversationId)
                .id(conversationId)
        } else {
            Text("Inspector")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .xrayId("mainWindow.inspectorPlaceholder")
        }
    }

    // MARK: - Status Pill

    private var sidecarStatusPill: some View {
        Button {
            showStatusPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                statusDot
                Text(statusShortLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Sidecar status")
        .xrayId("mainWindow.sidecarStatusPill")
        .accessibilityLabel("Sidecar \(statusShortLabel)")
        .popover(isPresented: $showStatusPopover, arrowEdge: .bottom) {
            statusPopoverContent
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch appState.sidecarStatus {
        case .connected:
            Circle().fill(.green).frame(width: 7, height: 7)
        case .connecting:
            ProgressView().controlSize(.mini)
        case .disconnected:
            Circle().fill(.gray).frame(width: 7, height: 7)
        case .error:
            Circle().fill(.red).frame(width: 7, height: 7)
        }
    }

    private var statusShortLabel: String {
        switch appState.sidecarStatus {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Disconnected"
        case .error: "Error"
        }
    }

    private var statusPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sidecar")
                        .font(.headline)
                    switch appState.sidecarStatus {
                    case .connected:
                        Text("ws://localhost:\(appState.allocatedWsPort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .error(let msg):
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    default:
                        EmptyView()
                    }
                }
            }

            Divider()

            HStack {
                switch appState.sidecarStatus {
                case .connected:
                    Button("Reconnect") {
                        showStatusPopover = false
                        appState.disconnectSidecar()
                        appState.connectSidecar()
                    }
                    .controlSize(.small)
                    .xrayId("mainWindow.statusPopover.reconnectButton")

                    Button("Stop") {
                        showStatusPopover = false
                        appState.disconnectSidecar()
                    }
                    .controlSize(.small)
                    .foregroundStyle(.red)
                    .xrayId("mainWindow.statusPopover.stopButton")

                case .disconnected, .error:
                    Button("Connect") {
                        showStatusPopover = false
                        appState.connectSidecar()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .xrayId("mainWindow.statusPopover.connectButton")

                case .connecting:
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 240)
        .xrayId("mainWindow.statusPopover")
    }

    // MARK: - Actions

    private func createQuickChat() {
        let conversation = Conversation(topic: "New Chat")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
    }

    private func startSessionWithAgent(_ agent: Agent) {
        let session = Session(agent: agent, mode: .interactive)
        session.workingDirectory = agent.defaultWorkingDirectory ?? windowState.projectDirectory
        let conversation = Conversation(topic: agent.name, sessions: [session])
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: agent.name
        )
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        session.conversations = [conversation]

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
    }

    private func startGroupChat(_ group: AgentGroup) {
        if let convoId = appState.startGroupChat(group: group, projectDirectory: windowState.projectDirectory, modelContext: modelContext) {
            windowState.selectedConversationId = convoId
        }
    }
}

/// Finds the nearest NSSplitView ancestor and sets its autosaveName so macOS
/// persists the divider position between app launches.
private struct SplitViewConfigurator: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = SplitViewFinderView(name: autosaveName)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SplitViewFinderView: NSView {
        let name: String
        init(name: String) {
            self.name = name
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.configureSplitView()
            }
        }

        private func configureSplitView() {
            var current: NSView? = superview
            while let view = current {
                if let splitView = view as? NSSplitView {
                    if splitView.autosaveName == nil || splitView.autosaveName!.isEmpty {
                        splitView.autosaveName = name
                    }
                    return
                }
                current = view.superview
            }
        }
    }
}

/// Sets the NSWindow title for multi-instance disambiguation.
/// Uses NSWindow.didBecomeKeyNotification so it fires after SwiftUI finishes layout.
private struct WindowTitleSetter: NSViewRepresentable {
    let projectName: String

    func makeNSView(context: Context) -> NSView {
        let view = TitleSettingView(projectName: projectName)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TitleSettingView: NSView {
        let projectName: String

        init(projectName: String) {
            self.projectName = projectName
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.title = "ClaudeStudio — \(projectName)"
        }
    }
}
