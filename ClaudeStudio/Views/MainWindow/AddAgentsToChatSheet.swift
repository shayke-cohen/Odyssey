import SwiftUI
import SwiftData

/// Add one or more agents to an existing conversation (new `Session` + participant each).
struct AddAgentsToChatSheet: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query private var allConversations: [Conversation]

    @State private var selectedIds: Set<UUID> = []

    private var conversation: Conversation? {
        allConversations.first { $0.id == conversationId }
    }

    private var existingAgentIds: Set<UUID> {
        guard let convo = conversation else { return [] }
        return Set(
            convo.sessions.compactMap(\.agent?.id)
        )
    }

    private var addableAgents: [Agent] {
        agents.filter { !existingAgentIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add agents")
                .font(.headline)
                .xrayId("addAgents.title")

            Text("Selected agents join this conversation and receive the next messages.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(addableAgents) { agent in
                        Toggle(isOn: Binding(
                            get: { selectedIds.contains(agent.id) },
                            set: { on in
                                if on { selectedIds.insert(agent.id) } else { selectedIds.remove(agent.id) }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: agent.icon)
                                    .foregroundStyle(Color.fromAgentColor(agent.color))
                                Text(agent.name)
                            }
                        }
                        .xrayId("addAgents.toggle.\(agent.id.uuidString)")
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 280)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .xrayId("addAgents.cancelButton")
                Spacer()
                Button("Add") { addSelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIds.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    .xrayId("addAgents.confirmButton")
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func addSelected() {
        guard let convo = conversation else {
            dismiss()
            return
        }
        let primaryWd = (convo.primarySession?.workingDirectory ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mission = convo.primarySession?.mission
        let mode = convo.primarySession?.mode ?? .interactive

        for agent in agents where selectedIds.contains(agent.id) {
            let wd = !primaryWd.isEmpty ? primaryWd : ""
            let session = Session(
                agent: agent,
                mission: mission,
                mode: mode,
                workingDirectory: wd
            )
            session.conversations = [convo]
            convo.sessions.append(session)

            let agentParticipant = Participant(
                type: .agentSession(sessionId: session.id),
                displayName: agent.name
            )
            agentParticipant.conversation = convo
            convo.participants.append(agentParticipant)

            modelContext.insert(session)
        }

        GroupWorkingDirectory.ensureShared(
            for: convo,
            instanceDefault: appState.instanceWorkingDirectory,
            modelContext: modelContext
        )
        try? modelContext.save()
        dismiss()
    }
}
