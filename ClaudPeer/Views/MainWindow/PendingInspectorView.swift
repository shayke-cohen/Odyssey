import SwiftUI
import SwiftData

/// Inspector panel content for pending (not yet materialized) agent or group selections.
struct PendingInspectorView: View {
    let agent: Agent?
    let group: AgentGroup?

    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var allAgents: [Agent]
    @Query private var allConversations: [Conversation]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let group {
                    groupContent(group)
                } else if let agent {
                    agentContent(agent)
                }
            }
            .padding()
        }
        .frame(minWidth: 220, idealWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .xrayId("pendingInspector")
    }

    // MARK: - Agent Content

    @ViewBuilder
    private func agentContent(_ agent: Agent) -> some View {
        // Header
        VStack(spacing: 8) {
            Image(systemName: agent.icon)
                .font(.title)
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .frame(width: 48, height: 48)
                .background(Color.fromAgentColor(agent.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(agent.name)
                .font(.headline)

            if !agent.agentDescription.isEmpty {
                Text(agent.agentDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .xrayId("pendingInspector.agentHeader")

        Divider()

        // Details
        VStack(alignment: .leading, spacing: 8) {
            Label("Details", systemImage: "info.circle")
                .font(.headline)

            InfoRow(label: "Model", value: agent.model)
            InfoRow(label: "Instance Policy", value: policyLabel(agent.instancePolicy))
            if let dir = agent.defaultWorkingDirectory, !dir.isEmpty {
                InfoRow(label: "Working Dir", value: (dir as NSString).lastPathComponent)
            }
            if let repo = agent.githubRepo, !repo.isEmpty {
                InfoRow(label: "GitHub", value: repo)
            }
        }
        .xrayId("pendingInspector.agentDetails")

        // Skills
        if !agent.skillIds.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Skills", systemImage: "lightbulb")
                    .font(.headline)
                Text("\(agent.skillIds.count) skill\(agent.skillIds.count == 1 ? "" : "s") attached")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        // Recent conversations
        let agentConversations = recentConversationsForAgent(agent)
        if !agentConversations.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Recent Chats", systemImage: "clock")
                    .font(.headline)
                ForEach(agentConversations.prefix(5)) { conv in
                    Button {
                        appState.selectedConversationId = conv.id
                    } label: {
                        HStack {
                            Text(conv.topic ?? "Untitled")
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(conv.startedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recentConversationsForAgent(_ agent: Agent) -> [Conversation] {
        allConversations
            .filter { conv in
                conv.sessions.contains { $0.agent?.id == agent.id }
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func policyLabel(_ policy: InstancePolicy) -> String {
        switch policy {
        case .spawn: return "New each time"
        case .singleton: return "Singleton"
        case .pool(let max): return "Pool (\(max) max)"
        }
    }

    // MARK: - Group Content

    @ViewBuilder
    private func groupContent(_ group: AgentGroup) -> some View {
        // Header
        VStack(spacing: 8) {
            Text(group.icon)
                .font(.title)
                .frame(width: 48, height: 48)
                .background(Color.fromAgentColor(group.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(group.name)
                .font(.headline)

            HStack(spacing: 4) {
                if group.autonomousCapable {
                    miniPill("Autonomous", color: .orange)
                }
                if group.workflow != nil {
                    miniPill("Workflow", color: .teal)
                }
            }

            if !group.groupDescription.isEmpty {
                Text(group.groupDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .xrayId("pendingInspector.groupHeader")

        // Workflow
        if let steps = group.workflow, !steps.isEmpty {
            Divider()
            groupWorkflowSection(steps, group: group)
        }

        // Team
        Divider()
        groupTeamSection(group)

        // Instruction
        if !group.groupInstruction.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Instruction", systemImage: "text.quote")
                    .font(.headline)
                Text(group.groupInstruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }
        }

        // Recent chats
        let groupConversations = allConversations
            .filter { $0.sourceGroupId == group.id }
            .sorted { $0.startedAt > $1.startedAt }
        if !groupConversations.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Recent Chats", systemImage: "clock")
                    .font(.headline)
                ForEach(groupConversations.prefix(5)) { conv in
                    Button {
                        appState.selectedConversationId = conv.id
                    } label: {
                        HStack {
                            Text(conv.topic ?? "Untitled")
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(conv.startedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func groupWorkflowSection(_ steps: [WorkflowStep], group: AgentGroup) -> some View {
        let agentById = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })

        VStack(alignment: .leading, spacing: 8) {
            Label("Workflow", systemImage: "arrow.triangle.branch")
                .font(.headline)

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 22, height: 22)
                        Text("\(index + 1)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.stepLabel ?? "Step \(index + 1)")
                            .font(.caption)
                        if let agent = agentById[step.agentId] {
                            Text(agent.name)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func groupTeamSection(_ group: AgentGroup) -> some View {
        let agentById = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        let resolved = group.agentIds.compactMap { agentById[$0] }

        VStack(alignment: .leading, spacing: 8) {
            Label("Team", systemImage: "person.3")
                .font(.headline)

            ForEach(resolved) { agent in
                HStack(spacing: 8) {
                    Image(systemName: agent.icon)
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .background(Color.fromAgentColor(agent.color).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agent.name)
                            .font(.caption)
                        let role = group.roleFor(agentId: agent.id)
                        if role != .participant {
                            Text(role.rawValue.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private func miniPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
