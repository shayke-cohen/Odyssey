import SwiftUI
import SwiftData

struct NewSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \Session.startedAt, order: .reverse) private var recentSessions: [Session]

    /// Agents selected for this conversation (one or more = group-capable).
    @State private var selectedAgentIds: Set<UUID> = []
    @State private var isFreeformChat = false
    @State private var providerOverride = AgentDefaults.inheritMarker
    @State private var modelOverride = AgentDefaults.inheritMarker
    @State private var sessionMode: SessionMode = .interactive
    @State private var mission = ""
    @State private var showAdvancedOptions = false

    @State private var showCreateFromPrompt = false
    @State private var createFromPromptText = ""
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    private var enabledAgents: [Agent] {
        agents.filter { $0.isEnabled }
    }

    private var recentAgents: [Agent] {
        var seen = Set<UUID>()
        var result: [Agent] = []
        for session in recentSessions {
            guard let agent = session.agent, agent.isEnabled, !seen.contains(agent.id) else { continue }
            seen.insert(agent.id)
            result.append(agent)
            if result.count >= 3 { break }
        }
        return result
    }

    private var orderedSelectedAgents: [Agent] {
        agents.filter { selectedAgentIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canStartSession: Bool {
        isFreeformChat || !selectedAgentIds.isEmpty
    }

    private var selectedSingleAgent: Agent? {
        orderedSelectedAgents.count == 1 ? orderedSelectedAgents.first : nil
    }

    private var allowsSessionOverrides: Bool {
        !isFreeformChat && selectedSingleAgent != nil
    }

    private var effectiveProviderForOverrides: String {
        AgentDefaults.resolveEffectiveProvider(
            sessionOverride: providerOverride,
            agentSelection: selectedSingleAgent?.provider
        )
    }

    private var localProviderReport: LocalProviderStatusReport {
        LocalProviderSupport.statusReport()
    }

    private var localProviderSummary: String? {
        switch effectiveProviderForOverrides {
        case ProviderSelection.foundation.rawValue:
            return localProviderReport.foundationSummary
        case ProviderSelection.mlx.rawValue:
            return localProviderReport.mlxSummary
        default:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    createFromPromptSection
                    projectInfoRow
                    optionsSection
                    if !recentAgents.isEmpty {
                        recentAgentsRow
                    }
                    agentPicker
                    if !orderedSelectedAgents.isEmpty {
                        Text("Selected: \(orderedSelectedAgents.map(\.name).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .xrayId("newSession.selectedAgentsSummary")
                    }
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 620)
        .onChange(of: providerOverride) { _, _ in
            modelOverride = AgentDefaults.availableThreadModelChoices(
                for: effectiveProviderForOverrides,
                inheritLabel: "Inherit from Agent"
            ).contains(where: { $0.id == AgentDefaults.normalizedModelSelection(modelOverride) })
                ? AgentDefaults.normalizedModelSelection(modelOverride)
                : AgentDefaults.inheritMarker
        }
    }

    // MARK: - Project Info

    @ViewBuilder
    private var projectInfoRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text("Project:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(windowState.projectName)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
        }
        .padding(.vertical, 4)
        .xrayId("newSession.projectInfo")
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("New Thread")
                .font(.title2)
                .fontWeight(.semibold)
                .xrayId("newSession.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .xrayId("newSession.closeButton")
            .accessibilityLabel("Close")
        }
        .padding(16)
    }

    // MARK: - Create from Prompt

    @ViewBuilder
    private var createFromPromptSection: some View {
        DisclosureGroup("Create agent from prompt", isExpanded: $showCreateFromPrompt) {
            VStack(alignment: .leading, spacing: 10) {
                if appState.generatedAgentSpec == nil && !appState.isGeneratingAgent {
                    HStack(spacing: 8) {
                        TextField("Describe an agent to create...", text: $createFromPromptText)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("newSession.fromPrompt.textField")
                        Button {
                            generateAgentFromPrompt()
                        } label: {
                            Label("Generate", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(createFromPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .xrayId("newSession.fromPrompt.generateButton")
                    }
                    Text("e.g. \"A code reviewer focused on security\"")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if appState.isGeneratingAgent {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .xrayId("newSession.fromPrompt.loading")
                }

                if let error = appState.generateAgentError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                        Button("Retry") { generateAgentFromPrompt() }
                            .controlSize(.small)
                            .xrayId("newSession.fromPrompt.retryButton")
                    }
                }

                if let spec = appState.generatedAgentSpec {
                    AgentPreviewCard(
                        spec: spec,
                        onSave: { agent in
                            modelContext.insert(agent)
                            try? modelContext.save()
                            isFreeformChat = false
                            selectedAgentIds = [agent.id]
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                        },
                        onSaveAndStart: { agent in
                            modelContext.insert(agent)
                            try? modelContext.save()
                            isFreeformChat = false
                            selectedAgentIds = [agent.id]
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                            Task { await createSessionAsync() }
                        },
                        onCancel: {
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                        }
                    )
                }
            }
            .padding(.top, 8)
        }
        .font(.headline)
        .xrayId("newSession.fromPrompt.disclosure")
    }

    private func generateAgentFromPrompt() {
        let skillEntries = allSkills.map { skill in
            SkillCatalogEntry(
                id: skill.id.uuidString,
                name: skill.name,
                description: skill.skillDescription,
                category: skill.category
            )
        }
        let mcpEntries = allMCPs.map { mcp in
            MCPCatalogEntry(
                id: mcp.id.uuidString,
                name: mcp.name,
                description: mcp.serverDescription
            )
        }
        appState.requestAgentGeneration(
            prompt: createFromPromptText.trimmingCharacters(in: .whitespacesAndNewlines),
            skills: skillEntries,
            mcps: mcpEntries
        )
    }

    // MARK: - Recent Agents

    @ViewBuilder
    private var recentAgentsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(recentAgents) { agent in
                    Button {
                        isFreeformChat = false
                        selectedAgentIds = [agent.id]
                        providerOverride = AgentDefaults.inheritMarker
                        modelOverride = AgentDefaults.inheritMarker
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: agent.icon)
                                .foregroundStyle(Color.fromAgentColor(agent.color))
                            Text(agent.name)
                                .font(.callout)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedAgentIds == [agent.id] && !isFreeformChat
                            ? Color.fromAgentColor(agent.color).opacity(0.12)
                            : Color.clear
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    selectedAgentIds == [agent.id] && !isFreeformChat
                                        ? Color.fromAgentColor(agent.color)
                                        : .secondary.opacity(0.3),
                                    lineWidth: selectedAgentIds == [agent.id] && !isFreeformChat ? 2 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .xrayId("newSession.recentAgent.\(agent.id.uuidString)")
                }
                Spacer()
            }
        }
    }

    // MARK: - Agent Picker

    @ViewBuilder
    private var agentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Agents (select one or more)")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 10)
            ], spacing: 10) {
                agentPickerCard(
                    icon: "bubble.left.and.bubble.right",
                    name: "Freeform",
                    detail: "No agent",
                    color: .secondary,
                    isSelected: isFreeformChat && selectedAgentIds.isEmpty,
                    identifier: "newSession.agentCard.freeform"
                ) {
                    isFreeformChat = true
                    selectedAgentIds.removeAll()
                    providerOverride = AgentDefaults.inheritMarker
                    modelOverride = AgentDefaults.inheritMarker
                }

                ForEach(enabledAgents) { agent in
                    agentPickerCard(
                        icon: agent.icon,
                        name: agent.name,
                        detail: AgentDefaults.label(for: agent.model),
                        color: Color.fromAgentColor(agent.color),
                        isSelected: selectedAgentIds.contains(agent.id),
                        identifier: "newSession.agentCard.\(agent.id.uuidString)"
                    ) {
                        isFreeformChat = false
                        if selectedAgentIds.contains(agent.id) {
                            selectedAgentIds.remove(agent.id)
                        } else {
                            selectedAgentIds.insert(agent.id)
                            providerOverride = AgentDefaults.inheritMarker
                            modelOverride = AgentDefaults.inheritMarker
                        }
                    }
                }
            }
        }
    }

    private func agentPickerCard(icon: String, name: String, detail: String, color: Color, isSelected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(isSelected ? color.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? color.opacity(1.0) : color.opacity(0.0), lineWidth: 2)
            }
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.secondary.opacity(0.2), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(name)
        .xrayId(identifier)
    }

    // MARK: - Options

    @ViewBuilder
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Thread Setup")
                    .font(.headline)
                    .xrayId("newSession.optionsTitle")
                Text("Pick how this thread should behave, then give it a clear goal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .xrayId("newSession.optionsSubtitle")
            }

            modeCards

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Goal")
                        .font(.subheadline.weight(.semibold))
                        .xrayId("newSession.goalTitle")
                    Text(goalPromptLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .xrayId("newSession.goalCaption")
                }

                TextField(goalPlaceholder, text: $mission, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
                    .xrayId("newSession.missionField")

                Text(goalHelpText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .xrayId("newSession.goalHelp")
            }

            if allowsSessionOverrides {
                advancedOverridesSection
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
        .xrayId("newSession.optionsDisclosure")
    }

    @ViewBuilder
    private var modeCards: some View {
        HStack(spacing: 12) {
            modeCard(
                mode: .interactive,
                title: "Interactive",
                subtitle: "Waits for you",
                detail: "Opens the thread and lets you steer each turn.",
                icon: "hand.tap.fill",
                accent: .blue
            )
            modeCard(
                mode: .autonomous,
                title: "Autonomous",
                subtitle: "Runs once",
                detail: "Starts immediately, works hands-off, then stops when done.",
                icon: "sparkles.rectangle.stack",
                accent: .orange
            )
            modeCard(
                mode: .worker,
                title: "Worker",
                subtitle: "Stays on call",
                detail: "Starts now, finishes the first job, then waits in the same thread.",
                icon: "shippingbox.fill",
                accent: .green
            )
        }
    }

    private func modeCard(
        mode: SessionMode,
        title: String,
        subtitle: String,
        detail: String,
        icon: String,
        accent: Color
    ) -> some View {
        let isSelected = sessionMode == mode
        return Button {
            sessionMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(isSelected ? accent : .secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(isSelected ? accent.opacity(0.14) : Color.secondary.opacity(0.08))
                        )

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.headline)
                        .foregroundStyle(isSelected ? accent : .secondary.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? accent : .secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .padding(14)
            .background(isSelected ? accent.opacity(0.10) : Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? accent.opacity(0.9) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .xrayId("newSession.modeCard.\(mode.rawValue)")
        .accessibilityIdentifier("newSession.modeCard.\(mode.rawValue)")
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var advancedOverridesSection: some View {
        DisclosureGroup("Advanced agent overrides", isExpanded: $showAdvancedOptions) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider")
                        .font(.subheadline.weight(.semibold))
                    Picker("", selection: $providerOverride) {
                        Text("Inherit from Agent").tag(AgentDefaults.inheritMarker)
                        Text("Claude").tag(ProviderSelection.claude.rawValue)
                        Text("Codex").tag(ProviderSelection.codex.rawValue)
                        Text("Foundation").tag(ProviderSelection.foundation.rawValue)
                        Text("MLX").tag(ProviderSelection.mlx.rawValue)
                    }
                    .labelsHidden()
                    .xrayId("newSession.providerPicker")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.subheadline.weight(.semibold))
                    Picker("", selection: $modelOverride) {
                        ForEach(
                            AgentDefaults.availableThreadModelChoices(
                                for: effectiveProviderForOverrides,
                                inheritLabel: "Inherit from Agent"
                            )
                        ) { choice in
                            Text(choice.label).tag(choice.id)
                        }
                    }
                    .labelsHidden()
                    .xrayId("newSession.modelPicker")
                }

                if let localProviderSummary {
                    Text(localProviderSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .xrayId("newSession.localProviderSummary")
                }
            }
            .padding(.top, 10)
        }
        .xrayId("newSession.advancedOptionsDisclosure")
    }

    private var goalPromptLabel: String {
        switch sessionMode {
        case .interactive:
            return "Optional context for the thread"
        case .autonomous:
            return "Required if you want it to start right away"
        case .worker:
            return "Defines the first job and worker focus"
        }
    }

    private var goalPlaceholder: String {
        switch sessionMode {
        case .interactive:
            return "Describe what this thread is for, or leave it blank and start chatting..."
        case .autonomous:
            return "What should this thread do immediately?"
        case .worker:
            return "What should this worker handle now and be ready to handle again later?"
        }
    }

    private var goalHelpText: String {
        switch sessionMode {
        case .interactive:
            return "This becomes shared context in the thread header and initial instructions, but the thread still waits for your first message."
        case .autonomous:
            return "The goal is posted into the transcript and sent immediately so the run can begin without another click."
        case .worker:
            return "The goal launches the first run now. After it finishes, the same thread returns to standby for the next job."
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(startActionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .xrayId("newSession.footerSummary")
                Text("⌘N this sheet  ·  ⌘⇧N quick chat")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Quick Chat") {
                createQuickChat()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .xrayId("newSession.quickChatButton")
            Button(primaryActionTitle) {
                Task { await createSessionAsync() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(!canStartSession)
            .xrayId("newSession.startSessionButton")
        }
        .padding(16)
    }

    private var startActionSummary: String {
        let selectionSummary: String
        if isFreeformChat || orderedSelectedAgents.isEmpty {
            selectionSummary = "Freeform thread"
        } else if orderedSelectedAgents.count == 1, let agent = orderedSelectedAgents.first {
            selectionSummary = "\(agent.name)"
        } else {
            selectionSummary = "\(orderedSelectedAgents.count)-agent group"
        }

        switch sessionMode {
        case .interactive:
            return "\(selectionSummary) will wait for your first message."
        case .autonomous:
            return "\(selectionSummary) will launch the goal as soon as the thread opens."
        case .worker:
            return "\(selectionSummary) will run the first job, then stay ready in the same thread."
        }
    }

    private var primaryActionTitle: String {
        switch sessionMode {
        case .interactive:
            return "Start Thread"
        case .autonomous:
            return "Launch Autonomous Thread"
        case .worker:
            return "Start Worker Thread"
        }
    }

    // MARK: - Actions

    private func createSessionAsync() async {
        let missionText = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectDir = windowState.projectDirectory
        let executionMode: ConversationExecutionMode = {
            switch sessionMode {
            case .interactive: return .interactive
            case .autonomous: return .autonomous
            case .worker: return .worker
            }
        }()

        // Freeform chat
        if isFreeformChat || selectedAgentIds.isEmpty {
            let conversation = Conversation(
                topic: "New Thread",
                projectId: windowState.selectedProjectId,
                threadKind: .freeform
            )
            conversation.executionMode = executionMode
            let userParticipant = Participant(type: .user, displayName: "You")
            userParticipant.conversation = conversation
            conversation.participants.append(userParticipant)

            let session = Session(
                agent: nil,
                mission: missionText.isEmpty ? nil : missionText,
                mode: sessionMode,
                workingDirectory: projectDir
            )
            session.conversations = [conversation]
            conversation.sessions.append(session)
            let agentParticipant = Participant(
                type: .agentSession(sessionId: session.id),
                displayName: AgentDefaults.displayName(forProvider: session.provider)
            )
            agentParticipant.conversation = conversation
            conversation.participants.append(agentParticipant)

            modelContext.insert(session)
            modelContext.insert(conversation)
            try? modelContext.save()
            windowState.selectedConversationId = conversation.id
            if executionMode != .interactive, !missionText.isEmpty {
                windowState.autoSendText = missionText
            }
            dismiss()
            return
        }

        let selectedList = orderedSelectedAgents
        guard !selectedList.isEmpty else {
            dismiss()
            return
        }

        let topic: String
        if selectedList.count == 1 {
            topic = selectedList[0].name
        } else {
            topic = selectedList.map(\.name).joined(separator: ", ")
        }

        let conversation = Conversation(
            topic: topic,
            projectId: windowState.selectedProjectId,
            threadKind: selectedList.count > 1 ? .group : .direct
        )
        conversation.executionMode = executionMode
        if selectedList.count > 1 {
            conversation.routingMode = .mentionAware
        }
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        for agent in selectedList {
            let session = Session(
                agent: agent,
                mission: missionText.isEmpty ? nil : missionText,
                mode: sessionMode,
                workingDirectory: projectDir
            )

            if selectedList.count == 1 {
                session.provider = AgentDefaults.resolveEffectiveProvider(
                    sessionOverride: providerOverride,
                    agentSelection: agent.provider
                )
                session.model = AgentDefaults.resolveEffectiveModel(
                    sessionOverride: modelOverride,
                    agentSelection: agent.model,
                    provider: session.provider
                )
            }

            session.conversations = [conversation]
            conversation.sessions.append(session)

            let agentParticipant = Participant(
                type: .agentSession(sessionId: session.id),
                displayName: agent.name
            )
            agentParticipant.conversation = conversation
            conversation.participants.append(agentParticipant)

            modelContext.insert(session)
        }

        modelContext.insert(conversation)
        try? modelContext.save()
        windowState.selectedConversationId = conversation.id
        if executionMode != .interactive, !missionText.isEmpty {
            windowState.autoSendText = missionText
        }
        dismiss()
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
        dismiss()
    }
}
