import SwiftUI
import SwiftData

enum SidebarBottomBarItem: String, CaseIterable, Identifiable {
    case catalog = "Catalog"
    case workshop = "Workshop"
    case agents = "Agents"
    case autoAssemble = "Auto-assemble"
    case newSession = "New session"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .catalog: "square.grid.2x2"
        case .workshop: "wrench.and.screwdriver"
        case .agents: "cpu"
        case .autoAssemble: "wand.and.stars"
        case .newSession: "plus"
        }
    }

    var helpText: String {
        switch self {
        case .catalog: "Browse catalog"
        case .workshop: "Entity workshop (⌘⇧W)"
        case .agents: "Agent library"
        case .autoAssemble: "Auto-assemble team"
        case .newSession: "New session"
        }
    }

    var xrayId: String {
        switch self {
        case .catalog: "sidebar.catalogButton"
        case .workshop: "sidebar.workshopButton"
        case .agents: "sidebar.agentsButton"
        case .autoAssemble: "sidebar.autoAssembleButton"
        case .newSession: "sidebar.newSessionButton"
        }
    }

    /// Whether this item shows a text label alongside its icon.
    /// Items with text labels participate in the adaptive icon-only collapse via `ViewThatFits`.
    var hasTextLabel: Bool {
        switch self {
        case .catalog, .workshop, .agents: true
        case .autoAssemble, .newSession: false
        }
    }

    /// Items that show text labels and collapse to icon-only when space is constrained.
    static var adaptiveItems: [SidebarBottomBarItem] {
        allCases.filter(\.hasTextLabel)
    }

    /// Items that always display as icon-only.
    static var iconOnlyItems: [SidebarBottomBarItem] {
        allCases.filter { !$0.hasTextLabel }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Session.startedAt, order: .reverse) private var allSessions: [Session]
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var taskItems: [TaskItem]
    @State private var searchText = ""
    @State private var isTasksExpanded = true
    @State private var isCompletedTasksExpanded = false
    @State private var showTaskCreation = false
    @State private var editingTask: TaskItem?
    @State private var expandedAgentIds: Set<UUID> = []
    @State private var expandedGroupIds: Set<UUID> = []
    @State private var editingGroup: AgentGroup?
    @State private var autonomousGroup: AgentGroup?
    @State private var showAutoAssemble = false
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""
    @State private var conversationToDelete: Conversation?
    @State private var showDeleteConfirmation = false
    @State private var showCatalog = false
    @State private var isPinnedExpanded = true
    @State private var isActiveExpanded = true
    @State private var isHistoryExpanded = false
    @State private var isArchivedExpanded = false
    @State private var hoveredConversationId: UUID?

    var body: some View {
        @Bindable var ws = windowState
        VStack(spacing: 0) {
            List(selection: $ws.selectedConversationId) {
                if conversations.isEmpty {
                    emptyState
                } else {
                    Section("Chats") {
                        pinnedSection
                        activeSection
                        historySection
                        archivedSection
                    }
                }
                tasksSection
                groupsSection
                agentsSection
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search conversations...")
            .xrayId("sidebar.conversationList")
            .onChange(of: windowState.selectedConversationId) { _, newValue in
                guard let selectedId = newValue else { return }
                // Check if the selected ID is a task ID (not a conversation)
                if let task = taskItems.first(where: { $0.id == selectedId }) {
                    if let convId = task.conversationId {
                        // Redirect to the actual conversation
                        DispatchQueue.main.async {
                            windowState.selectedConversationId = convId
                        }
                    } else {
                        // No conversation — open edit sheet, clear selection
                        DispatchQueue.main.async {
                            windowState.selectedConversationId = nil
                            editingTask = task
                        }
                    }
                }
            }

            Divider()

            sidebarBottomBar
        }
        .frame(minWidth: 220)
        .sheet(isPresented: $showCatalog) {
            CatalogBrowserView()
                .frame(minWidth: 700, minHeight: 550)
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorView(group: group)
        }
        .sheet(item: $autonomousGroup) { group in
            AutonomousMissionSheet(group: group)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showAutoAssemble) {
            AutoAssembleSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showTaskCreation) {
            TaskCreationSheet()
                .environmentObject(appState)
        }
        .sheet(item: $editingTask) { task in
            TaskEditSheet(task: task)
                .environmentObject(appState)
        }
        .alert("Rename Conversation", isPresented: Binding(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let convo = renamingConversation, !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    convo.topic = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? modelContext.save()
                }
                renamingConversation = nil
            }
            Button("Cancel", role: .cancel) { renamingConversation = nil }
        }
        .alert("Delete Conversation?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let convo = conversationToDelete {
                    if windowState.selectedConversationId == convo.id {
                        windowState.selectedConversationId = nil
                    }
                    appState.clearSessionActivity(for: convo.sessions.map(\.id.uuidString))
                    modelContext.delete(convo)
                    try? modelContext.save()
                }
                conversationToDelete = nil
            }
            Button("Cancel", role: .cancel) { conversationToDelete = nil }
        } message: {
            Text("This conversation and all its messages will be permanently deleted.")
        }
    }

    // MARK: - Bottom Bar

    private var sidebarBottomBar: some View {
        ViewThatFits(in: .horizontal) {
            sidebarBottomBarButtons
            sidebarBottomBarButtons
                .labelStyle(.iconOnly)
        }
        .padding(.vertical, 6)
        .background(.bar)
        .xrayId("sidebar.bottomBar")
    }

    private var sidebarBottomBarButtons: some View {
        HStack(spacing: 0) {
            let catalog = SidebarBottomBarItem.catalog
            Button {
                showCatalog = true
            } label: {
                Label(catalog.rawValue, systemImage: catalog.icon)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(catalog.helpText)
            .xrayId(catalog.xrayId)

            Divider()
                .frame(height: 16)

            let workshop = SidebarBottomBarItem.workshop
            Button {
                windowState.showWorkshop = true
            } label: {
                Label(workshop.rawValue, systemImage: workshop.icon)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(workshop.helpText)
            .xrayId(workshop.xrayId)
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Divider()
                .frame(height: 16)

            let agents = SidebarBottomBarItem.agents
            Button {
                windowState.showAgentLibrary = true
            } label: {
                Label(agents.rawValue, systemImage: agents.icon)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(agents.helpText)
            .xrayId(agents.xrayId)

            Divider()
                .frame(height: 16)

            let autoAssemble = SidebarBottomBarItem.autoAssemble
            Button {
                showAutoAssemble = true
            } label: {
                Image(systemName: autoAssemble.icon)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(autoAssemble.helpText)
            .xrayId(autoAssemble.xrayId)

            Divider()
                .frame(height: 16)

            let newSession = SidebarBottomBarItem.newSession
            Button {
                windowState.showNewSessionSheet = true
            } label: {
                Image(systemName: newSession.icon)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(newSession.helpText)
            .xrayId(newSession.xrayId)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No conversations yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Start chatting with an agent or create a freeform chat.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Button {
                    windowState.showNewSessionSheet = true
                } label: {
                    Label("New Session", systemImage: "plus.bubble")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Start a new session")
                .xrayId("sidebar.emptyState.newSessionButton")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Pinned Section

    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = rootConversations.filter { $0.isPinned && !$0.isArchived }
        let filteredPinned = filteredConversations(pinned)
        if !filteredPinned.isEmpty {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isPinnedExpanded || !searchText.isEmpty },
                    set: { isPinnedExpanded = $0 }
                )
            ) {
                ForEach(filteredPinned) { convo in
                    conversationTreeNode(convo, pinAction: "Unpin")
                }
            } label: {
                Label("Pinned (\(filteredPinned.count))", systemImage: "pin.fill")
                    .foregroundStyle(.secondary)
            }
            .xrayId("sidebar.pinnedSection")
        }
    }

    // MARK: - Active Section (last 10)

    @ViewBuilder
    private var activeSection: some View {
        let all = rootConversations.filter { !$0.isPinned && !$0.isArchived }
        let visible = filteredConversations(Array(all.prefix(10)))
        if !visible.isEmpty {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isActiveExpanded || !searchText.isEmpty },
                    set: { isActiveExpanded = $0 }
                )
            ) {
                ForEach(visible) { convo in
                    conversationTreeNode(convo, pinAction: "Pin")
                }
            } label: {
                Label("Active (\(visible.count))", systemImage: "bolt.fill")
                    .foregroundStyle(.secondary)
            }
            .xrayId("sidebar.activeSection")
        }
    }

    // MARK: - History Section (overflow, foldable)

    @ViewBuilder
    private var historySection: some View {
        let all = rootConversations.filter { !$0.isPinned && !$0.isArchived }
        let overflow = Array(all.dropFirst(10))
        let visible = filteredConversations(overflow)
        if !visible.isEmpty {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isHistoryExpanded || !searchText.isEmpty },
                    set: { isHistoryExpanded = $0 }
                )
            ) {
                ForEach(visible) { convo in
                    conversationTreeNode(convo, pinAction: "Pin")
                }
            } label: {
                Label("History (\(visible.count))", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }
            .xrayId("sidebar.historySection")
        }
    }

    // MARK: - Archived Section

    @ViewBuilder
    private var archivedSection: some View {
        let archived = rootConversations.filter { $0.isArchived }
        let visible = filteredConversations(archived)
        if !visible.isEmpty {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isArchivedExpanded || !searchText.isEmpty },
                    set: { isArchivedExpanded = $0 }
                )
            ) {
                ForEach(visible) { convo in
                    conversationRow(convo)
                        .tag(convo.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { promptDelete(convo) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { unarchiveConversation(convo) } label: {
                                Label("Unarchive", systemImage: "tray.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                }
            } label: {
                Label("Archived (\(visible.count))", systemImage: "archivebox")
                    .foregroundStyle(.secondary)
            }
            .xrayId("sidebar.archivedSection")
        }
    }

    // MARK: - Tree helpers

    private var rootConversations: [Conversation] {
        conversations.filter { $0.parentConversationId == nil }
    }

    private func childConversations(of parent: Conversation) -> [Conversation] {
        conversations
            .filter { $0.parentConversationId == parent.id }
            .sorted { $0.startedAt < $1.startedAt }
    }

    @ViewBuilder
    private func conversationTreeNode(_ convo: Conversation, pinAction: String) -> some View {
        let children = childConversations(of: convo)
        if children.isEmpty {
            conversationRow(convo)
                .tag(convo.id)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { promptDelete(convo) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { archiveConversation(convo) } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.indigo)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { togglePin(convo) } label: {
                        Label(pinAction, systemImage: convo.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(.yellow)
                }
        } else {
            DisclosureGroup {
                ForEach(children) { child in
                    childConversationRow(child)
                }
            } label: {
                conversationRow(convo)
                    .tag(convo.id)
            }
            .tag(convo.id)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { promptDelete(convo) } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button { archiveConversation(convo) } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.indigo)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { togglePin(convo) } label: {
                    Label(pinAction, systemImage: convo.isPinned ? "pin.slash" : "pin")
                }
                .tint(.yellow)
            }
        }
    }

    @ViewBuilder
    private func childConversationRow(_ convo: Conversation) -> some View {
        conversationRow(convo)
            .tag(convo.id)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { promptDelete(convo) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Tasks Section

    @ViewBuilder
    private var tasksSection: some View {
        let activeTasks = taskItems.filter { $0.status != .done && $0.status != .failed }
        let completedTasks = taskItems.filter { $0.status == .done || $0.status == .failed }

        if !taskItems.isEmpty || true { // Always show section for the [+] button
            Section {
                DisclosureGroup(isExpanded: $isTasksExpanded) {
                    // In Progress
                    ForEach(taskItems.filter { $0.status == .inProgress }) { task in
                        taskRow(task)
                    }
                    // Ready
                    ForEach(taskItems.filter { $0.status == .ready }) { task in
                        taskRow(task)
                    }
                    // Blocked
                    ForEach(taskItems.filter { $0.status == .blocked }) { task in
                        taskRow(task)
                    }
                    // Backlog
                    ForEach(taskItems.filter { $0.status == .backlog }) { task in
                        taskRow(task)
                    }
                    // Completed (foldable)
                    if !completedTasks.isEmpty {
                        DisclosureGroup(isExpanded: $isCompletedTasksExpanded) {
                            ForEach(completedTasks) { task in
                                taskRow(task)
                            }
                        } label: {
                            Text("Completed (\(completedTasks.count))")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } label: {
                    HStack {
                        Label("Task Board (\(activeTasks.count))", systemImage: "checklist")
                        Spacer()
                        Button {
                            showTaskCreation = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebar.tasksAddButton")
                    }
                }
            }
            .accessibilityIdentifier("sidebar.tasksSection")
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 6) {
            taskStatusIcon(task.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .lineLimit(1)
                    .font(.callout)
                HStack(spacing: 4) {
                    statusBadge(task.status)
                    priorityBadge(task.priority)
                    if let agentId = task.assignedAgentId,
                       let agent = agents.first(where: { $0.id == agentId }) {
                        Text(agent.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if task.conversationId != nil {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        // Use task.id as tag — intercepted by onChange to redirect
        .tag(task.id)
        .accessibilityIdentifier("sidebar.taskRow.\(task.id.uuidString)")
        .contextMenu { taskContextMenu(for: task) }
    }

    @ViewBuilder
    private func taskContextMenu(for task: TaskItem) -> some View {
        switch task.status {
        case .backlog:
            Button("Edit Task...") { editingTask = task }
            Button("Mark as Ready") { appState.updateTaskStatus(task, status: .ready) }
            Button("Run with Orchestrator") {
                appState.runTaskWithOrchestrator(task, modelContext: modelContext, windowState: windowState)
            }
            Divider()
            Button("Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
        case .ready:
            Button("Edit Task...") { editingTask = task }
            Button("Run with Orchestrator") {
                appState.runTaskWithOrchestrator(task, modelContext: modelContext, windowState: windowState)
            }
            Button("Move to Backlog") { appState.updateTaskStatus(task, status: .backlog) }
            Divider()
            Button("Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
        case .inProgress:
            if task.conversationId != nil {
                Button("Go to Conversation") {
                    windowState.selectedConversationId = task.conversationId
                }
            }
            Button("Pause") { appState.updateTaskStatus(task, status: .blocked) }
            Divider()
            Button("Cancel & Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
        case .blocked:
            if task.conversationId != nil {
                Button("Go to Conversation") {
                    windowState.selectedConversationId = task.conversationId
                }
            }
            Button("Resume") { appState.updateTaskStatus(task, status: .inProgress) }
            Divider()
            Button("Cancel & Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
        case .done, .failed:
            if task.conversationId != nil {
                Button("Go to Conversation") {
                    windowState.selectedConversationId = task.conversationId
                }
            }
            Button("Retry") { appState.updateTaskStatus(task, status: .ready) }
            Divider()
            Button("Delete", role: .destructive) {
                modelContext.delete(task)
                try? modelContext.save()
            }
        }
    }

    @ViewBuilder
    private func taskStatusIcon(_ status: TaskStatus) -> some View {
        switch status {
        case .backlog:
            Image(systemName: "circle.dotted").foregroundStyle(.gray)
        case .ready:
            Image(systemName: "circle").foregroundStyle(.blue)
        case .inProgress:
            Image(systemName: "circle.fill").foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .blocked:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: TaskStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .backlog: ("Backlog", .gray)
        case .ready: ("Ready", .blue)
        case .inProgress: ("In Progress", .orange)
        case .done: ("Done", .green)
        case .failed: ("Failed", .red)
        case .blocked: ("Blocked", .yellow)
        }
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15))
            .cornerRadius(3)
    }

    private func priorityBadge(_ priority: TaskPriority) -> some View {
        Text(priority.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(priorityColor(priority).opacity(0.2))
            .cornerRadius(3)
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: .gray
        case .medium: .blue
        case .high: .orange
        case .critical: .red
        }
    }

    // MARK: - Groups Section

    @ViewBuilder
    private var groupsSection: some View {
        Section {
            ForEach(groups.filter { $0.isEnabled }) { group in
                GroupSidebarRowView(
                    group: group,
                    agentCount: group.agentIds.compactMap { id in agents.first { $0.id == id } }.count,
                    conversations: conversationsForGroup(group),
                    allAgents: agents,
                    isExpanded: Binding(
                        get: { expandedGroupIds.contains(group.id) },
                        set: { expanded in
                            if expanded { expandedGroupIds.insert(group.id) }
                            else { expandedGroupIds.remove(group.id) }
                        }
                    ),
                    onNewChat: {
                        if let convoId = appState.startGroupChat(group: group, projectDirectory: windowState.projectDirectory, modelContext: modelContext) {
                            windowState.selectedConversationId = convoId
                        }
                    },
                    onNewAutonomousChat: group.autonomousCapable ? {
                        autonomousGroup = group
                    } : nil,
                    onSelectConversation: { conv in
                        windowState.selectedConversationId = conv.id
                    },
                    onSelectGroup: {
                        selectOrCreateGroupChat(group)
                    },
                    onEdit: { editingGroup = group },
                    onDuplicate: { duplicateGroup(group) },
                    selectedConversationId: windowState.selectedConversationId,
                    hasActiveSession: groupHasActiveSession(group)
                )
                .contextMenu {
                    Button("Start Chat") {
                        if let convoId = appState.startGroupChat(group: group, projectDirectory: windowState.projectDirectory, modelContext: modelContext) {
                            windowState.selectedConversationId = convoId
                        }
                    }
                    Button("Edit") { editingGroup = group }
                    Button("Duplicate") { duplicateGroup(group) }
                    Divider()
                    Button("Delete", role: .destructive) { deleteGroup(group) }
                }
            }
        } header: {
            HStack {
                Text("Groups")
                Spacer()
                Button {
                    windowState.showGroupLibrary = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.groupsAddButton")
            }
        }
        .accessibilityIdentifier("sidebar.groupsSection")
    }

    // MARK: - Agents Section

    @ViewBuilder
    private var agentsSection: some View {
        Section("Agents") {
            ForEach(agents.filter { $0.isEnabled }) { agent in
                AgentSidebarRowView(
                    agent: agent,
                    conversations: conversationsForAgent(agent),
                    isExpanded: Binding(
                        get: { expandedAgentIds.contains(agent.id) },
                        set: { expanded in
                            if expanded { expandedAgentIds.insert(agent.id) }
                            else { expandedAgentIds.remove(agent.id) }
                        }
                    ),
                    onNewChat: { startSession(with: agent) },
                    onSelectConversation: { conv in
                        windowState.selectedConversationId = conv.id
                    },
                    onSelectAgent: {
                        selectOrCreateAgentChat(agent)
                    },
                    selectedConversationId: windowState.selectedConversationId,
                    hasActiveSession: agentHasActiveSession(agent)
                )
                .contextMenu {
                    Button("Start Session") {
                        startSession(with: agent)
                    }
                    .xrayId("sidebar.agentRow.startSession.\(agent.id.uuidString)")
                }
            }
        }
    }

    // MARK: - Conversation Row

    private func conversationRow(_ convo: Conversation) -> some View {
        let activity = appState.conversationActivity(for: convo)
        let isHovered = hoveredConversationId == convo.id
        return HStack(spacing: 8) {
            if convo.isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .accessibilityIdentifier("sidebar.unreadBadge.\(convo.id.uuidString)")
            }
            conversationIcon(convo)
            VStack(alignment: .leading, spacing: 2) {
                Text(convo.topic ?? "Untitled")
                    .lineLimit(1)
                    .font(convo.isUnread ? .callout.bold() : .callout)
                HStack(spacing: 4) {
                    Text(relativeTime(convo.startedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let preview = lastMessagePreview(convo) {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let icon = preview.attachmentIcon {
                            Image(systemName: icon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(preview.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if case .working(let count) = activity.aggregate {
                    Text(count == 1 ? "Agent working\u{2026}" : "\(count) agents working\u{2026}")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isHovered {
                Menu {
                    conversationMenuContent(convo)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .xrayId("sidebar.moreMenu.\(convo.id.uuidString)")
            }
            SidebarActivityIndicator(
                summary: activity,
                conversationStatus: convo.status
            )
            .xrayId("sidebar.activityIndicator.\(convo.id.uuidString)")
        }
        .onHover { isHovering in
            hoveredConversationId = isHovering ? convo.id : nil
        }
        .xrayId("sidebar.conversationRow.\(convo.id.uuidString)")
        .contextMenu {
            conversationMenuContent(convo)
        }
    }

    @ViewBuilder
    private func conversationMenuContent(_ convo: Conversation) -> some View {
        Button {
            renameText = convo.topic ?? ""
            renamingConversation = convo
        } label: {
            Label("Rename\u{2026}", systemImage: "pencil")
        }
        Button { togglePin(convo) } label: {
            Label(convo.isPinned ? "Unpin" : "Pin", systemImage: convo.isPinned ? "pin.slash" : "pin")
        }
        Button { toggleUnread(convo) } label: {
            Label(convo.isUnread ? "Mark as Read" : "Mark as Unread",
                  systemImage: convo.isUnread ? "envelope.open" : "envelope.badge")
        }
        Divider()
        if convo.status == .active {
            Button { closeConversation(convo) } label: {
                Label("Close Session", systemImage: "stop.circle")
            }
        }
        Button { duplicateConversation(convo) } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }
        if convo.isArchived {
            Button { unarchiveConversation(convo) } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
        } else {
            Button { archiveConversation(convo) } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
        Divider()
        Button(role: .destructive) { promptDelete(convo) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Conversation Icon

    @ViewBuilder
    private func conversationIcon(_ convo: Conversation) -> some View {
        let hasUser = convo.participants.contains { $0.type == .user }
        let agentCount = convo.participants.filter {
            if case .agentSession = $0.type { return true }
            return false
        }.count
        let isChild = convo.parentConversationId != nil
        let isDelegation = convo.messages.contains { $0.type == .delegation }

        if let agent = convo.primarySession?.agent, hasUser {
            Image(systemName: agent.icon)
                .foregroundStyle(agentColor(agent.color))
                .font(.caption)
        } else if isDelegation {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.orange)
                .font(.caption)
        } else if !hasUser && agentCount >= 2 {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.purple)
                .font(.caption)
        } else if !hasUser && isChild {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(.purple)
                .font(.caption)
        } else if hasUser && agentCount > 1 {
            Image(systemName: "person.3.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        } else if hasUser {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        } else {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func lastMessagePreview(_ convo: Conversation) -> (text: String, attachmentIcon: String?)? {
        let chatMessages = convo.messages
            .filter { $0.type == .chat }
            .sorted { $0.timestamp < $1.timestamp }
        guard let last = chatMessages.last else { return nil }
        let attachments = last.attachments
        let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let icon: String? = {
            guard !attachments.isEmpty else { return nil }
            let hasImages = attachments.contains { $0.isImage }
            let hasDocs = attachments.contains { $0.isDocument }
            if hasImages && hasDocs { return "paperclip" }
            if hasDocs { return "doc.text" }
            return "photo"
        }()

        if text.isEmpty && !attachments.isEmpty {
            let count = attachments.count
            let hasImages = attachments.contains { $0.isImage }
            let hasDocs = attachments.contains { $0.isDocument }
            let label: String
            if hasImages && !hasDocs {
                label = count == 1 ? "Image" : "\(count) Images"
            } else if hasDocs && !hasImages {
                label = count == 1 ? "File" : "\(count) Files"
            } else {
                label = "\(count) Attachments"
            }
            return (text: label, attachmentIcon: icon)
        }

        let preview: String
        if text.count <= 40 {
            preview = text
        } else {
            let cutoff = text.index(text.startIndex, offsetBy: 40)
            preview = String(text[..<cutoff]) + "..."
        }
        return preview.isEmpty ? nil : (text: preview, attachmentIcon: icon)
    }

    private func filteredConversations(_ convos: [Conversation]) -> [Conversation] {
        if searchText.isEmpty { return convos }
        return convos.filter { convo in
            (convo.topic ?? "").localizedCaseInsensitiveContains(searchText) ||
            convo.participants.contains { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func agentColor(_ color: String) -> Color {
        Color.fromAgentColor(color)
    }

    // MARK: - Activity State

    private func agentHasActiveSession(_ agent: Agent) -> Bool {
        for conversation in conversationsForAgent(agent) {
            for session in conversation.sessions where session.agent?.id == agent.id {
                let key = session.id.uuidString
                if appState.sessionActivity[key]?.isActive == true {
                    return true
                }
            }
        }
        return false
    }

    private func groupHasActiveSession(_ group: AgentGroup) -> Bool {
        for conversation in conversationsForGroup(group) {
            for session in conversation.sessions {
                let key = session.id.uuidString
                if appState.sessionActivity[key]?.isActive == true {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Agent Chat History

    private func conversationsForGroup(_ group: AgentGroup) -> [Conversation] {
        conversations.filter { $0.sourceGroupId == group.id }
    }

    private func conversationsForAgent(_ agent: Agent) -> [Conversation] {
        var seen = Set<UUID>()
        return allSessions
            .filter { $0.agent?.id == agent.id }
            .compactMap { $0.conversations.first }
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: - Group Actions

    private func duplicateGroup(_ group: AgentGroup) {
        let copy = AgentGroup(
            name: "\(group.name) Copy",
            groupDescription: group.groupDescription,
            icon: group.icon,
            color: group.color,
            groupInstruction: group.groupInstruction,
            defaultMission: group.defaultMission,
            agentIds: group.agentIds,
            sortOrder: groups.count
        )
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func deleteGroup(_ group: AgentGroup) {
        modelContext.delete(group)
        try? modelContext.save()
    }

    // MARK: - Actions

    private func togglePin(_ convo: Conversation) {
        convo.isPinned.toggle()
        try? modelContext.save()
    }

    private func toggleUnread(_ convo: Conversation) {
        convo.isUnread.toggle()
        try? modelContext.save()
    }

    private func archiveConversation(_ convo: Conversation) {
        convo.isArchived = true
        convo.isPinned = false
        try? modelContext.save()
    }

    private func unarchiveConversation(_ convo: Conversation) {
        convo.isArchived = false
        try? modelContext.save()
    }

    private func closeConversation(_ convo: Conversation) {
        convo.status = .closed
        convo.closedAt = Date()
        let sessionKeys = convo.sessions.map(\.id.uuidString)
        for session in convo.sessions {
            appState.sendToSidecar(.sessionPause(sessionId: session.id.uuidString))
            session.status = .paused
        }
        appState.clearSessionActivity(for: sessionKeys)
        try? modelContext.save()
    }

    private func promptDelete(_ convo: Conversation) {
        conversationToDelete = convo
        showDeleteConfirmation = true
    }

    private func duplicateConversation(_ convo: Conversation) {
        let newConvo = Conversation(topic: (convo.topic ?? "Untitled") + " (copy)")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = newConvo
        newConvo.participants.append(userParticipant)

        for session in convo.sessions {
            guard let agent = session.agent else { continue }
            let newSession = Session(agent: agent, mode: session.mode)
            newSession.mission = session.mission
            newSession.workingDirectory = session.workingDirectory
            newConvo.sessions.append(newSession)
            newSession.conversations = [newConvo]

            let agentParticipant = Participant(
                type: .agentSession(sessionId: newSession.id),
                displayName: agent.name
            )
            agentParticipant.conversation = newConvo
            newConvo.participants.append(agentParticipant)
            modelContext.insert(newSession)
        }

        modelContext.insert(newConvo)
        try? modelContext.save()
        windowState.selectedConversationId = newConvo.id
    }

    private func selectOrCreateAgentChat(_ agent: Agent) {
        if let existing = conversationsForAgent(agent).first(where: { !$0.isArchived }) {
            windowState.selectedConversationId = existing.id
        } else {
            startSession(with: agent)
        }
    }

    private func selectOrCreateGroupChat(_ group: AgentGroup) {
        if let existing = conversationsForGroup(group).first(where: { !$0.isArchived }) {
            windowState.selectedConversationId = existing.id
        } else {
            if let convoId = appState.startGroupChat(group: group, projectDirectory: windowState.projectDirectory, modelContext: modelContext) {
                windowState.selectedConversationId = convoId
            }
        }
    }

    private func startSession(with agent: Agent) {
        let session = Session(agent: agent, mode: .interactive)
        if session.workingDirectory.isEmpty, !windowState.projectDirectory.isEmpty {
            session.workingDirectory = windowState.projectDirectory
        }
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
}
