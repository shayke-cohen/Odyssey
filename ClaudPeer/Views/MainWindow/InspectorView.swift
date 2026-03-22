import SwiftUI
import SwiftData
import AppKit

enum InspectorTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case files = "Files"

    var id: String { rawValue }
}

struct InspectorView: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var allConversations: [Conversation]
    @EnvironmentObject private var appState: AppState
    @State private var now = Date()
    @State private var inspectorTab: InspectorTab = .info

    private let durationTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var orderedSessions: [Session] {
        (conversation?.sessions ?? []).sorted { $0.startedAt < $1.startedAt }
    }

    private var primarySession: Session? {
        conversation?.primarySession
    }

    private func liveInfo(for session: Session) -> AppState.SessionInfo? {
        appState.activeSessions[session.id]
    }

    private var hasWorkingDirectory: Bool {
        guard let session = primarySession else { return false }
        return !session.workingDirectory.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasWorkingDirectory {
                Picker("Inspector Tab", selection: $inspectorTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityIdentifier("inspector.tabPicker")
            }

            switch inspectorTab {
            case .info:
                infoContent
            case .files:
                if let dir = primarySession?.workingDirectory, !dir.isEmpty {
                    FileExplorerView(
                        workingDirectory: dir,
                        refreshTrigger: appState.fileTreeRefreshTrigger
                    )
                } else {
                    infoContent
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 280)
        .onReceive(durationTimer) { _ in
            now = Date()
        }
    }

    // MARK: - Info Content

    private var infoContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if orderedSessions.isEmpty {
                    EmptyView()
                } else if orderedSessions.count == 1, let session = orderedSessions.first {
                    sessionSection(session: session)
                    usageSection(session: session, agent: session.agent)
                    if let agent = session.agent {
                        agentSection(agent: agent)
                    }
                } else {
                    multiSessionsSection
                }
                if hasWorkingDirectory {
                    workspaceSection
                }
                historySection
            }
            .padding()
        }
        .accessibilityIdentifier("inspector.scrollView")
    }

    // MARK: - Session Section

    @ViewBuilder
    private func sessionSection(session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Session", systemImage: "terminal")
                .font(.headline)
                .accessibilityIdentifier("inspector.sessionHeading")

            InfoRow(label: "Status", value: session.status.rawValue.capitalized)
            InfoRow(label: "Model", value: modelShortName(session.agent?.model ?? ""))
            InfoRow(label: "Mode", value: session.mode.rawValue.capitalized)

            if let convo = conversation {
                InfoRow(label: "Duration", value: durationString(from: convo.startedAt))
            }
        }
    }

    @ViewBuilder
    private var multiSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sessions in this conversation", systemImage: "person.3")
                .font(.headline)
                .accessibilityIdentifier("inspector.sessionsListHeading")

            ForEach(orderedSessions, id: \.id) { session in
                multiSessionRow(session: session)
            }
        }
    }

    @ViewBuilder
    private func multiSessionRow(session: Session) -> some View {
        let live = liveInfo(for: session)
        let agent = session.agent
        let liveTokens = live?.tokenCount ?? session.tokenCount
        let liveCost = live?.cost ?? session.totalCost
        let streaming = live?.isStreaming == true ? "active" : session.status.rawValue.capitalized

        VStack(alignment: .leading, spacing: 6) {
            Text(agent?.name ?? "Agent")
                .font(.subheadline)
                .fontWeight(.semibold)
            InfoRow(label: "Status", value: streaming)
            InfoRow(label: "Model", value: modelShortName(agent?.model ?? ""))
            InfoRow(label: "Tokens", value: formatNumber(liveTokens))
            InfoRow(label: "Cost", value: String(format: "$%.4f", liveCost))
            InfoRow(label: "Tool Calls", value: "\(session.toolCallCount)")
            if let agent {
                Button {
                    appState.showAgentLibrary = true
                } label: {
                    Text("Open \(agent.name) in editor")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inspector.sessionRow.agentLink.\(session.id.uuidString)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("inspector.sessionRow.\(session.id.uuidString)")
    }

    // MARK: - Usage Section

    @ViewBuilder
    private func usageSection(session: Session, agent: Agent?) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Label("Usage", systemImage: "chart.bar")
                .font(.headline)
                .accessibilityIdentifier("inspector.usageHeading")

            let live = liveInfo(for: session)
            let liveTokens = live?.tokenCount ?? session.tokenCount
            let liveCost = live?.cost ?? session.totalCost
            let maxTurns = agent?.maxTurns ?? 30
            let toolCalls = session.toolCallCount

            InfoRow(label: "Tokens", value: formatNumber(liveTokens))
            InfoRow(label: "Cost", value: String(format: "$%.4f", liveCost))
            InfoRow(label: "Tool Calls", value: "\(toolCalls)")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Turns")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text("\(toolCalls) / \(maxTurns)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("inspector.turnsLabel")

                ProgressView(value: min(Double(toolCalls), Double(maxTurns)), total: Double(maxTurns))
                    .tint(turnProgressColor(used: toolCalls, max: maxTurns))
                    .padding(.leading, 84)
                    .accessibilityIdentifier("inspector.turnsProgress")
            }
        }
    }

    // MARK: - Workspace Section

    @ViewBuilder
    private var workspaceSection: some View {
        if let session = primarySession, !session.workingDirectory.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Working directory", systemImage: "folder")
                    .font(.headline)
                    .accessibilityIdentifier("inspector.workspaceHeading")

                InfoRow(label: "Path", value: abbreviatePath(session.workingDirectory))

                HStack(spacing: 8) {
                    Button {
                        revealInFinder(session.workingDirectory)
                    } label: {
                        Label("Finder", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reveal working directory in Finder")
                    .accessibilityLabel("Reveal in Finder")
                    .accessibilityIdentifier("inspector.openFinderButton")

                    Button {
                        openInTerminal(session.workingDirectory)
                    } label: {
                        Label("Open in Terminal", systemImage: "terminal")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open working directory in Terminal")
                    .accessibilityIdentifier("inspector.openTerminalButton")

                    Button {
                        revealSandboxesRootInFinder()
                    } label: {
                        Label("Sandboxes", systemImage: "archivebox")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open ~/.claudpeer/sandboxes in Finder")
                    .accessibilityIdentifier("inspector.openSandboxesFinderButton")
                }
            }
        }
    }

    // MARK: - Agent Section

    @ViewBuilder
    private func agentSection(agent: Agent) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Label("Agent", systemImage: agent.icon)
                .font(.headline)
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .accessibilityIdentifier("inspector.agentHeading")

            Button {
                appState.showAgentLibrary = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: agent.icon)
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                    Text(agent.name)
                        .font(.callout)
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.plain)
            .help("Open \(agent.name) in editor")
            .accessibilityIdentifier("inspector.agentNameButton")

            HStack(spacing: 12) {
                Label("\(agent.skillIds.count) skills", systemImage: "book")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(agent.extraMCPServerIds.count) MCPs", systemImage: "server.rack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("inspector.agentCapabilities")

            InfoRow(label: "Policy", value: policyLabel(agent.instancePolicy))
        }
    }

    // MARK: - History Section

    @ViewBuilder
    private var historySection: some View {
        if let convo = conversation {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("History", systemImage: "clock")
                    .font(.headline)
                    .accessibilityIdentifier("inspector.historyHeading")

                InfoRow(label: "Started", value: convo.startedAt.formatted(.relative(presentation: .named)))
                InfoRow(label: "Messages", value: "\(convo.messages.count)")

                if let parentId = convo.parentConversationId,
                   let parent = allConversations.first(where: { $0.id == parentId }) {
                    InfoRow(label: "Forked from", value: parent.topic ?? "Untitled")
                }

                if convo.isPinned {
                    InfoRow(label: "Pinned", value: "Yes")
                }
            }
        }
    }

    // MARK: - Helpers

    private func durationString(from start: Date) -> String {
        let interval = now.timeIntervalSince(start)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }

    private func turnProgressColor(used: Int, max: Int) -> Color {
        let ratio = Double(used) / Double(max)
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return .accentColor
    }

    private func modelShortName(_ model: String) -> String {
        if model.contains("sonnet") { return "Sonnet 4.6" }
        if model.contains("opus") { return "Opus 4.6" }
        if model.contains("haiku") { return "Haiku 4.6" }
        return model
    }

    private func policyLabel(_ policy: InstancePolicy) -> String {
        switch policy {
        case .spawn: return "Spawn"
        case .singleton: return "Singleton"
        case .pool(let max): return "Pool(\(max))"
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    /// Opens `~/.claudpeer/sandboxes` (conversation sandboxes and other ephemeral dirs live here).
    private func revealSandboxesRootInFinder() {
        let path = "\(NSHomeDirectory())/.claudpeer/sandboxes"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private func openInTerminal(_ path: String) {
        let script = "tell application \"Terminal\" to do script \"cd \(path.replacingOccurrences(of: "\"", with: "\\\""))\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .lineLimit(2)
        }
        .accessibilityIdentifier("infoRow.\(label.lowercased().replacingOccurrences(of: " ", with: ""))")
        .accessibilityLabel("\(label): \(value)")
    }
}
