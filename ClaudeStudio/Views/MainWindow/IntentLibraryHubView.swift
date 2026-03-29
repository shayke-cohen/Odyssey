import SwiftUI
import SwiftData

struct IntentLibraryHubView: View {
    enum BuildFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case mine = "Mine"
        case shared = "Shared"
        case builtin = "Built-in"

        var id: String { rawValue }
    }

    private struct RecentLaunch: Identifiable {
        enum Kind {
            case agent(Agent)
            case group(AgentGroup)
        }

        let id: String
        let title: String
        let subtitle: String
        let date: Date
        let kind: Kind
    }

    @Binding var selectedSection: LibrarySection
    @Binding var selectedBuildSection: LibraryBuildSection
    @Binding var selectedDiscoverSection: LibraryDiscoverSection

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Skill.name) private var skills: [Skill]
    @Query(sort: \MCPServer.name) private var mcps: [MCPServer]
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]

    @State private var searchText = ""
    @State private var buildFilter: BuildFilter = .all
    @State private var selectedDiscoverCategory = "All"
    @State private var listRevision = 0
    @State private var selectedItem: CatalogItem?
    @State private var editingAgent: Agent?
    @State private var editingGroup: AgentGroup?
    @State private var showingNewGroup = false
    @State private var showingBlankAgentEditor = false
    @State private var showingPromptAgentEditor = false
    @State private var showingNewAgentEntry = false
    @State private var pendingAgentInstall: CatalogAgent?
    @State private var showAgentInstallConfirmation = false
    @State private var agentInstallAlertTitle = ""
    @State private var agentInstallAlertMessage = ""

    private var enabledAgents: [Agent] {
        agents.filter(\.isEnabled)
    }

    private var enabledGroups: [AgentGroup] {
        groups.filter(\.isEnabled)
    }

    private var filteredRunAgents: [Agent] {
        enabledAgents.filter { matchesRunSearch(name: $0.name, description: $0.agentDescription) }
    }

    private var filteredRunGroups: [AgentGroup] {
        enabledGroups.filter { matchesRunSearch(name: $0.name, description: $0.groupDescription) }
    }

    private var filteredBuildAgents: [Agent] {
        enabledAgents.filter { agent in
            matchesBuildSearch(name: agent.name, description: agent.agentDescription)
                && matchesBuildFilter(originKind: agent.originKind)
        }
    }

    private var filteredBuildGroups: [AgentGroup] {
        enabledGroups.filter { group in
            matchesBuildSearch(name: group.name, description: group.groupDescription)
                && matchesBuildFilter(originKind: group.originKind)
        }
    }

    private var recentLaunches: [RecentLaunch] {
        var launches: [RecentLaunch] = []
        var seenAgentIds = Set<UUID>()
        var seenGroupIds = Set<UUID>()

        for session in sessions {
            guard let agent = session.agent, agent.isEnabled, !seenAgentIds.contains(agent.id) else { continue }
            launches.append(
                RecentLaunch(
                    id: "agent-\(agent.id.uuidString)",
                    title: agent.name,
                    subtitle: "Agent",
                    date: session.startedAt,
                    kind: .agent(agent)
                )
            )
            seenAgentIds.insert(agent.id)
            if launches.count >= 6 { break }
        }

        for conversation in conversations {
            guard let groupId = conversation.sourceGroupId,
                  !seenGroupIds.contains(groupId),
                  let group = groups.first(where: { $0.id == groupId && $0.isEnabled }) else { continue }
            launches.append(
                RecentLaunch(
                    id: "group-\(group.id.uuidString)",
                    title: group.name,
                    subtitle: "Group",
                    date: conversation.startedAt,
                    kind: .group(group)
                )
            )
            seenGroupIds.insert(group.id)
        }

        return launches
            .sorted(by: { $0.date > $1.date })
            .filter { matchesRunSearch(name: $0.title, description: $0.subtitle) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        GeometryReader { geometry in
            let compactLayout = geometry.size.width < 900

            Group {
                if compactLayout {
                    VStack(spacing: 0) {
                        compactHeader
                        Divider()
                        content
                    }
                } else {
                    HStack(spacing: 0) {
                        leftRail
                        Divider()
                        VStack(spacing: 0) {
                            header
                            Divider()
                            content
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 620)
        .accessibilityIdentifier("libraryHub.sheet")
        .sheet(item: $editingAgent) { agent in
            AgentEditorView(agent: agent) { _ in
                editingAgent = nil
            }
            .frame(minWidth: 600, minHeight: 500)
        }
        .sheet(item: $editingGroup) { group in
            GroupEditorView(group: group)
                .frame(minWidth: 560, minHeight: 520)
        }
        .sheet(isPresented: $showingBlankAgentEditor) {
            AgentEditorView(agent: nil) { _ in
                showingBlankAgentEditor = false
            }
            .frame(minWidth: 600, minHeight: 500)
        }
        .sheet(isPresented: $showingPromptAgentEditor) {
            AgentFromPromptSheet(onSave: { _ in
                showingPromptAgentEditor = false
            })
            .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(isPresented: $showingNewGroup) {
            GroupEditorView(group: nil)
                .frame(minWidth: 560, minHeight: 520)
        }
        .sheet(isPresented: $showingNewAgentEntry) {
            LibraryNewAgentEntrySheet(
                onCreateBlank: {
                    showingNewAgentEntry = false
                    showingBlankAgentEditor = true
                },
                onCreateFromPrompt: {
                    showingNewAgentEntry = false
                    showingPromptAgentEditor = true
                }
            )
            .frame(minWidth: 500, minHeight: 280)
        }
        .sheet(isPresented: Binding(
            get: { selectedItem != nil },
            set: { if !$0 { selectedItem = nil } }
        )) {
            if let item = selectedItem {
                CatalogDetailView(item: item) {
                    listRevision += 1
                }
            }
        }
        .alert(agentInstallAlertTitle, isPresented: $showAgentInstallConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingAgentInstall = nil
            }
            Button("Install") {
                if let agent = pendingAgentInstall {
                    CatalogService.shared.installAgent(agent.catalogId, into: modelContext)
                    try? modelContext.save()
                    listRevision += 1
                }
                pendingAgentInstall = nil
            }
        } message: {
            Text(agentInstallAlertMessage)
        }
        .onChange(of: selectedSection) { _, _ in
            searchText = ""
        }
        .onChange(of: selectedDiscoverSection) { _, _ in
            selectedDiscoverCategory = "All"
        }
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                railButton(for: .run, icon: "play.circle")
                railButton(for: .build, icon: "square.and.pencil")
                railButton(for: .discover, icon: "sparkles.rectangle.stack")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(recentLaunches.count) launches")
                    .font(.headline)
                Text("Installed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                summaryLine("Agents", value: "\(enabledAgents.count)")
                summaryLine("Groups", value: "\(enabledGroups.count)")
                summaryLine("Skills", value: "\(skills.count)")
                summaryLine("Integrations", value: "\(mcps.count)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("libraryHub.summaryCard")

            Spacer()
        }
        .frame(minWidth: 240, idealWidth: 240, maxWidth: 240, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Library / \(selectedSection.title)")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("libraryHub.title")

            Spacer()

            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                .accessibilityIdentifier("libraryHub.searchField")

            if selectedSection == .build {
                buildHeaderActions
            }

            closeButton
        }
        .padding(20)
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text("Library / \(selectedSection.title)")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("libraryHub.title")

                Spacer(minLength: 0)

                closeButton
            }

            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("libraryHub.searchField")

            HStack(spacing: 8) {
                railButton(for: .run, icon: "play.circle", compact: true)
                railButton(for: .build, icon: "square.and.pencil", compact: true)
                railButton(for: .discover, icon: "sparkles.rectangle.stack", compact: true)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                compactSummaryChip(title: "Agents", value: "\(enabledAgents.count)")
                compactSummaryChip(title: "Groups", value: "\(enabledGroups.count)")
                compactSummaryChip(title: "Skills", value: "\(skills.count)")
                compactSummaryChip(title: "Integrations", value: "\(mcps.count)")
            }

            if selectedSection == .build {
                HStack(spacing: 10) {
                    buildHeaderActions
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .run:
            runContent
        case .build:
            buildContent
        case .discover:
            discoverContent
        }
    }

    private var runContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick actions")
                        .font(.headline)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 12)],
                        spacing: 12
                    ) {
                        actionButton(
                            title: "Start Agent",
                            subtitle: "Pick an installed agent",
                            systemImage: "cpu",
                            xrayId: "libraryHub.run.startAgentButton"
                        ) {
                            windowState.showNewSessionSheet = true
                            dismiss()
                        }

                        actionButton(
                            title: "Start Group",
                            subtitle: "Launch a saved team",
                            systemImage: "person.3",
                            xrayId: "libraryHub.run.startGroupButton"
                        ) {
                            windowState.showNewGroupThreadSheet = true
                            dismiss()
                        }

                        actionButton(
                            title: "Quick Chat",
                            subtitle: "Start without an agent",
                            systemImage: "plus.message",
                            xrayId: "libraryHub.run.quickChatButton"
                        ) {
                            createQuickChat()
                            dismiss()
                        }
                    }
                }

                if !recentLaunches.isEmpty {
                    sectionCard(title: "Recent launches") {
                        VStack(spacing: 10) {
                            ForEach(recentLaunches) { item in
                                recentLaunchRow(item)
                            }
                        }
                    }
                }

                sectionCard(title: "Agents") {
                    if filteredRunAgents.isEmpty {
                        emptyInlineState("No agents match your search.")
                    } else {
                        VStack(spacing: 10) {
                            ForEach(filteredRunAgents) { agent in
                                compactAgentRow(agent)
                            }
                        }
                    }
                }

                sectionCard(title: "Groups") {
                    if filteredRunGroups.isEmpty {
                        emptyInlineState("No groups match your search.")
                    } else {
                        VStack(spacing: 10) {
                            ForEach(filteredRunGroups) { group in
                                compactGroupRow(group)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .accessibilityIdentifier("libraryHub.runScrollView")
    }

    private var buildContent: some View {
        HStack(spacing: 0) {
            buildSidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Build Section", selection: $selectedBuildSection) {
                        ForEach(LibraryBuildSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .accessibilityIdentifier("libraryHub.build.sectionPicker")

                    if selectedBuildSection == .agents {
                        if filteredBuildAgents.isEmpty {
                            sectionCard(title: "Agents") {
                                emptyInlineState("No agents found for the current filters.")
                            }
                        } else {
                            sectionCard(title: "Agents") {
                                VStack(spacing: 12) {
                                    ForEach(filteredBuildAgents) { agent in
                                        buildAgentRow(agent)
                                    }
                                }
                            }
                        }
                    } else {
                        if filteredBuildGroups.isEmpty {
                            sectionCard(title: "Groups") {
                                emptyInlineState("No groups found for the current filters.")
                            }
                        } else {
                            sectionCard(title: "Groups") {
                                VStack(spacing: 12) {
                                    ForEach(filteredBuildGroups) { group in
                                        buildGroupRow(group)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .accessibilityIdentifier("libraryHub.buildScrollView")
        }
    }

    private var buildSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filters")
                .font(.headline)
            ForEach(BuildFilter.allCases) { filter in
                Button {
                    buildFilter = filter
                } label: {
                    HStack {
                        Text(filter.rawValue)
                        Spacer()
                        if buildFilter == filter {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(buildFilter == filter ? Color.accentColor.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("libraryHub.build.filter.\(filter.rawValue)")
            }
            Spacer()
        }
        .frame(minWidth: 180, maxWidth: 180, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(Color.secondary.opacity(0.04))
    }

    private var discoverContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Discover Section", selection: $selectedDiscoverSection) {
                    ForEach(LibraryDiscoverSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .accessibilityIdentifier("libraryHub.discover.sectionPicker")

                HStack(spacing: 12) {
                    discoverSummaryChip(title: "Agents", value: "\(enabledAgents.count)")
                    discoverSummaryChip(title: "Skills", value: "\(skills.count)")
                    discoverSummaryChip(title: "Integrations", value: "\(mcps.count)")
                }

                categoryChipsRow

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)],
                    spacing: 16
                ) {
                    switch selectedDiscoverSection {
                    case .agentTemplates:
                        ForEach(filteredCatalogAgents) { agent in
                            discoverAgentCard(agent)
                                .xrayId("libraryHub.discover.agentCard.\(agent.catalogId)")
                        }
                    case .skills:
                        ForEach(filteredCatalogSkills) { skill in
                            discoverSkillCard(skill)
                                .xrayId("libraryHub.discover.skillCard.\(skill.catalogId)")
                        }
                    case .integrations:
                        ForEach(filteredCatalogMCPs) { mcp in
                            discoverMCPCard(mcp)
                                .xrayId("libraryHub.discover.mcpCard.\(mcp.catalogId)")
                        }
                    }
                }
            }
            .padding(20)
        }
        .accessibilityIdentifier("libraryHub.discoverScrollView")
    }

    private var buildHeaderActions: some View {
        Group {
            Button {
                showingNewAgentEntry = true
            } label: {
                Label("New Agent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .appXrayTapProxy(id: "libraryHub.newAgentButton") {
                showingNewAgentEntry = true
            }

            Button {
                showingNewGroup = true
            } label: {
                Label("New Group", systemImage: "person.3.fill")
            }
            .buttonStyle(.bordered)
            .appXrayTapProxy(id: "libraryHub.newGroupButton") {
                showingNewGroup = true
            }
        }
    }

    private var closeButton: some View {
        Button {
            windowState.showLibraryHub = false
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .appXrayTapProxy(id: "libraryHub.closeButton") {
            windowState.showLibraryHub = false
            dismiss()
        }
        .accessibilityLabel("Close library")
    }

    private func railButton(for section: LibrarySection, icon: String, compact: Bool = false) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .frame(width: 20)
                Text(section.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selectedSection == section ? Color.accentColor : Color.primary)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 8 : 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("libraryHub.section.\(section.rawValue)")
        .accessibilityLabel(section.title)
    }

    private func summaryLine(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func compactSummaryChip(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        xrayId: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .appXrayTapProxy(id: xrayId, action: action)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func emptyInlineState(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }

    private func recentLaunchRow(_ launch: RecentLaunch) -> some View {
        HStack(spacing: 12) {
            Group {
                switch launch.kind {
                case .agent(let agent):
                    Image(systemName: agent.icon)
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                case .group(let group):
                    Text(group.icon)
                }
            }
            .font(.title3)
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(launch.title)
                    .font(.body.weight(.medium))
                Text("\(launch.subtitle) · \(relativeTimestamp(launch.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Start") {
                switch launch.kind {
                case .agent(let agent):
                    startSession(with: agent)
                case .group(let group):
                    startGroupChat(group)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .appXrayTapProxy(id: "libraryHub.run.recentStart.\(launch.id)") {
                switch launch.kind {
                case .agent(let agent):
                    startSession(with: agent)
                case .group(let group):
                    startGroupChat(group)
                }
            }
        }
    }

    private func compactAgentRow(_ agent: Agent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: agent.icon)
                .font(.title3)
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .frame(width: 30, height: 30)
                .background(Color.fromAgentColor(agent.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.body.weight(.medium))
                Text("\(agentOriginLabel(agent)) · \(AgentDefaults.label(for: agent.model)) · \(agent.skillIds.count) skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !agent.agentDescription.isEmpty {
                    Text(agent.agentDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button("Start") {
                startSession(with: agent)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .appXrayTapProxy(id: "libraryHub.run.agentStart.\(agent.id.uuidString)") {
                startSession(with: agent)
            }

            Menu {
                Button("Edit") { editingAgent = agent }
                Button("Duplicate") { duplicateAgent(agent) }
                Button("Manage in Build") {
                    selectedSection = .build
                    selectedBuildSection = .agents
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .xrayId("libraryHub.run.agentMore.\(agent.id.uuidString)")
        }
        .padding(.vertical, 2)
    }

    private func compactGroupRow(_ group: AgentGroup) -> some View {
        HStack(spacing: 12) {
            Text(group.icon)
                .font(.title3)
                .frame(width: 30, height: 30)
                .background(Color.fromAgentColor(group.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body.weight(.medium))
                Text("\(group.agentIds.count) agents · \(group.autoReplyEnabled ? "Auto-reply on" : "Auto-reply off")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !group.groupDescription.isEmpty {
                    Text(group.groupDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button("Start") {
                startGroupChat(group)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .appXrayTapProxy(id: "libraryHub.run.groupStart.\(group.id.uuidString)") {
                startGroupChat(group)
            }

            Menu {
                Button("Edit") { editingGroup = group }
                Button("Duplicate") { duplicateGroup(group) }
                Button("Manage in Build") {
                    selectedSection = .build
                    selectedBuildSection = .groups
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .xrayId("libraryHub.run.groupMore.\(group.id.uuidString)")
        }
        .padding(.vertical, 2)
    }

    private func buildAgentRow(_ agent: Agent) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: agent.icon)
                .font(.title2)
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .frame(width: 38, height: 38)
                .background(Color.fromAgentColor(agent.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(agent.name)
                    .font(.headline)
                Text("\(agentOriginLabel(agent)) · \(AgentDefaults.label(for: agent.model)) · \(agent.skillIds.count) skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !agent.agentDescription.isEmpty {
                    Text(agent.agentDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 8) {
                    Button("Start") { startSession(with: agent) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .appXrayTapProxy(id: "libraryHub.build.agentStart.\(agent.id.uuidString)") {
                            startSession(with: agent)
                        }
                    Button("Edit") { editingAgent = agent }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .appXrayTapProxy(id: "libraryHub.build.agentEdit.\(agent.id.uuidString)") {
                            editingAgent = agent
                        }
                    Button("Duplicate") { duplicateAgent(agent) }
                        .controlSize(.small)
                        .appXrayTapProxy(id: "libraryHub.build.agentDuplicate.\(agent.id.uuidString)") {
                            duplicateAgent(agent)
                        }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func buildGroupRow(_ group: AgentGroup) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(group.icon)
                .font(.title2)
                .frame(width: 38, height: 38)
                .background(Color.fromAgentColor(group.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(group.name)
                    .font(.headline)
                Text(groupMetadataLine(group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !group.groupDescription.isEmpty {
                    Text(group.groupDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 8) {
                    Button("Start") { startGroupChat(group) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .appXrayTapProxy(id: "libraryHub.build.groupStart.\(group.id.uuidString)") {
                            startGroupChat(group)
                        }
                    Button("Edit") { editingGroup = group }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .appXrayTapProxy(id: "libraryHub.build.groupEdit.\(group.id.uuidString)") {
                            editingGroup = group
                        }
                    Button("Duplicate") { duplicateGroup(group) }
                        .controlSize(.small)
                        .appXrayTapProxy(id: "libraryHub.build.groupDuplicate.\(group.id.uuidString)") {
                            duplicateGroup(group)
                        }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func discoverSummaryChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var categoryChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                discoverCategoryChip(title: "All")
                ForEach(currentDiscoverCategories, id: \.self) { category in
                    discoverCategoryChip(title: category)
                }
            }
        }
        .xrayId("libraryHub.discover.categoryRow")
    }

    private func discoverCategoryChip(title: String) -> some View {
        Button {
            selectedDiscoverCategory = title
        } label: {
            Text(title)
                .font(.caption.weight(selectedDiscoverCategory == title ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selectedDiscoverCategory == title ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .appXrayTapProxy(id: "libraryHub.discover.category.\(title)") {
            selectedDiscoverCategory = title
        }
    }

    private func discoverAgentCard(_ agent: CatalogAgent) -> some View {
        let installed = CatalogService.shared.isAgentInstalled(agent.catalogId, context: modelContext)
        return discoverCardChrome {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: agent.icon)
                        .font(.title2)
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name)
                            .font(.headline)
                        Text("\(AgentDefaults.label(for: agent.model)) · installs \(agent.requiredSkills.count) skills")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(installed ? "Installed in your library" : "Available in Build after install")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack {
                    Button("Preview") {
                        selectedItem = .agent(agent)
                    }
                    .controlSize(.small)
                    .xrayId("libraryHub.discover.agentPreview.\(agent.catalogId)")
                    Spacer()
                    installAction(installed: installed, catalogId: agent.catalogId) {
                        beginAgentInstall(agent)
                    }
                }
            }
        }
    }

    private func discoverSkillCard(_ skill: CatalogSkill) -> some View {
        let installed = CatalogService.shared.isSkillInstalled(skill.catalogId, context: modelContext)
        return discoverCardChrome {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: skill.icon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .font(.headline)
                        Text(skillMCPNeedsLine(skill))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(installed ? "Ready to use in editors" : "Adds to the agent builder capability pool")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack {
                    Button("Preview") {
                        selectedItem = .skill(skill)
                    }
                    .controlSize(.small)
                    .xrayId("libraryHub.discover.skillPreview.\(skill.catalogId)")
                    Spacer()
                    installAction(installed: installed, catalogId: skill.catalogId) {
                        CatalogService.shared.installSkill(skill.catalogId, into: modelContext)
                        try? modelContext.save()
                        listRevision += 1
                    }
                }
            }
        }
    }

    private func discoverMCPCard(_ mcp: CatalogMCP) -> some View {
        let installed = CatalogService.shared.isMCPInstalled(mcp.catalogId, context: modelContext)
        return discoverCardChrome {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: mcp.icon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mcp.name)
                            .font(.headline)
                        Text(mcp.transport.kind)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(mcp.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(installed ? "Installed as an integration" : "Available in editors and template installs")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack {
                    Button("Preview") {
                        selectedItem = .mcp(mcp)
                    }
                    .controlSize(.small)
                    .xrayId("libraryHub.discover.mcpPreview.\(mcp.catalogId)")
                    Spacer()
                    installAction(installed: installed, catalogId: mcp.catalogId) {
                        CatalogService.shared.installMCP(mcp.catalogId, into: modelContext)
                        try? modelContext.save()
                        listRevision += 1
                    }
                }
            }
        }
    }

    private func discoverCardChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func installAction(installed: Bool, catalogId: String, install: @escaping () -> Void) -> some View {
        if installed {
            Text("Installed")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(.green)
                .background(Color.green.opacity(0.14), in: Capsule())
        } else {
            Button("Install", action: install)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .appXrayTapProxy(id: "libraryHub.discover.install.\(catalogId)", action: install)
        }
    }

    private var filteredCatalogAgents: [CatalogAgent] {
        _ = listRevision
        return CatalogService.shared.allAgents().filter {
            matchesDiscoverCategory($0.category)
                && matchesDiscoverSearch($0.name, $0.description, $0.tags)
        }
    }

    private var filteredCatalogSkills: [CatalogSkill] {
        _ = listRevision
        return CatalogService.shared.allSkills().filter {
            matchesDiscoverCategory($0.category)
                && matchesDiscoverSearch($0.name, $0.description, $0.tags)
        }
    }

    private var filteredCatalogMCPs: [CatalogMCP] {
        _ = listRevision
        return CatalogService.shared.allMCPs().filter {
            matchesDiscoverCategory($0.category)
                && matchesDiscoverSearch($0.name, $0.description, $0.tags)
        }
    }

    private var currentDiscoverCategories: [String] {
        switch selectedDiscoverSection {
        case .agentTemplates:
            return CatalogService.shared.agentCategories()
        case .skills:
            return CatalogService.shared.skillCategories()
        case .integrations:
            return CatalogService.shared.mcpCategories()
        }
    }

    private var searchPlaceholder: String {
        switch selectedSection {
        case .run:
            return "Search launches..."
        case .build:
            return "Search definitions..."
        case .discover:
            return "Search templates..."
        }
    }

    private func matchesRunSearch(name: String, description: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(query)
            || description.localizedCaseInsensitiveContains(query)
    }

    private func matchesBuildSearch(name: String, description: String) -> Bool {
        matchesRunSearch(name: name, description: description)
    }

    private func matchesBuildFilter(originKind: String) -> Bool {
        switch buildFilter {
        case .all:
            return true
        case .mine:
            return originKind == "local"
        case .shared:
            return originKind == "peer" || originKind == "imported"
        case .builtin:
            return originKind == "builtin"
        }
    }

    private func matchesDiscoverCategory(_ category: String) -> Bool {
        selectedDiscoverCategory == "All" || selectedDiscoverCategory == category
    }

    private func matchesDiscoverSearch(_ name: String, _ description: String, _ tags: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return true }
        if name.lowercased().contains(query) { return true }
        if description.lowercased().contains(query) { return true }
        return tags.contains { $0.lowercased().contains(query) }
    }

    private func createQuickChat() {
        let conversation = Conversation(
            topic: "New Thread",
            projectId: windowState.selectedProjectId,
            threadKind: .freeform
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
    }

    private func startSession(with agent: Agent) {
        let session = Session(agent: agent, mode: .interactive)
        if session.workingDirectory.isEmpty {
            session.workingDirectory = agent.defaultWorkingDirectory ?? windowState.projectDirectory
        }
        let conversation = Conversation(
            topic: agent.name,
            sessions: [session],
            projectId: windowState.selectedProjectId,
            threadKind: .direct
        )
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(type: .agentSession(sessionId: session.id), displayName: agent.name)
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        session.conversations = [conversation]

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
        dismiss()
    }

    private func startGroupChat(_ group: AgentGroup) {
        if let conversationId = appState.startGroupChat(
            group: group,
            projectDirectory: windowState.projectDirectory,
            projectId: windowState.selectedProjectId,
            modelContext: modelContext
        ) {
            windowState.selectedConversationId = conversationId
            dismiss()
        }
    }

    private func duplicateAgent(_ agent: Agent) {
        let copy = Agent(
            name: "\(agent.name) Copy",
            agentDescription: agent.agentDescription,
            systemPrompt: agent.systemPrompt,
            provider: agent.provider,
            model: agent.model,
            icon: agent.icon,
            color: agent.color
        )
        copy.skillIds = agent.skillIds
        copy.extraMCPServerIds = agent.extraMCPServerIds
        copy.permissionSetId = agent.permissionSetId
        copy.maxTurns = agent.maxTurns
        copy.maxBudget = agent.maxBudget
        copy.defaultWorkingDirectory = agent.defaultWorkingDirectory
        modelContext.insert(copy)
        try? modelContext.save()
    }

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
        copy.autoReplyEnabled = group.autoReplyEnabled
        copy.autonomousCapable = group.autonomousCapable
        copy.coordinatorAgentId = group.coordinatorAgentId
        copy.agentRoles = group.agentRoles
        copy.workflow = group.workflow
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func groupMetadataLine(_ group: AgentGroup) -> String {
        var parts = ["\(group.agentIds.count) agents"]
        parts.append(group.autoReplyEnabled ? "Auto-reply on" : "Auto-reply off")
        if group.coordinatorAgentId != nil {
            parts.append("Coordinator set")
        }
        if let workflow = group.workflow, !workflow.isEmpty {
            parts.append("Workflow enabled")
        }
        return parts.joined(separator: " · ")
    }

    private func agentOriginLabel(_ agent: Agent) -> String {
        switch agent.origin {
        case .local: return "Local"
        case .peer: return "Shared"
        case .imported: return "Imported"
        case .builtin: return "Built-in"
        }
    }

    private func skillMCPNeedsLine(_ skill: CatalogSkill) -> String {
        if skill.requiredMCPs.isEmpty {
            return "No integrations needed"
        }
        let names = skill.requiredMCPs.map { CatalogService.shared.findMCP($0)?.name ?? $0 }
        return "Needs: " + names.joined(separator: ", ")
    }

    private func beginAgentInstall(_ agent: CatalogAgent) {
        let deps = CatalogService.shared.resolveDependencies(forAgent: agent, context: modelContext)
        agentInstallAlertTitle = "Install \(agent.name)?"
        var lines: [String] = []
        if !deps.skills.isEmpty || !deps.mcps.isEmpty {
            lines.append("This adds the template plus:")
            if !deps.skills.isEmpty {
                lines.append("• \(deps.skills.count) skills")
            }
            if !deps.mcps.isEmpty {
                lines.append("• \(deps.mcps.count) integrations")
            }
        } else if deps.missingSkillIds.isEmpty, deps.missingMCPIds.isEmpty {
            lines.append("No extra skills or integrations are required.")
        }
        if !deps.missingSkillIds.isEmpty || !deps.missingMCPIds.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Some catalog references are missing and will be skipped.")
        }
        if lines.isEmpty {
            lines.append("No extra skills or integrations are required.")
        }
        agentInstallAlertMessage = lines.joined(separator: "\n")
        pendingAgentInstall = agent
        showAgentInstallConfirmation = true
    }

    private func relativeTimestamp(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct LibraryNewAgentEntrySheet: View {
    let onCreateBlank: () -> Void
    let onCreateFromPrompt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Build > Agents > New Agent")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Choose how you want to create the agent")
                .font(.title3.weight(.semibold))

            HStack(spacing: 14) {
                creationOption(
                    title: "Create Blank",
                    subtitle: "Start from a standard agent editor",
                    systemImage: "square.and.pencil",
                    action: onCreateBlank
                )

                creationOption(
                    title: "From Prompt",
                    subtitle: "Describe the agent and generate a draft",
                    systemImage: "wand.and.stars",
                    action: onCreateFromPrompt
                )
            }
        }
        .padding(24)
        .xrayId("libraryHub.newAgentEntrySheet")
    }

    private func creationOption(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
