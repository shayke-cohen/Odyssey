import SwiftUI
import SwiftData

struct AgentFromPromptSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    let onSave: (Agent) -> Void
    let onSaveAndStart: ((Agent) -> Void)?

    @State private var prompt = ""
    @State private var showingFullEditor = false
    @State private var specForEditor: GeneratedAgentSpec?

    init(onSave: @escaping (Agent) -> Void, onSaveAndStart: ((Agent) -> Void)? = nil) {
        self.onSave = onSave
        self.onSaveAndStart = onSaveAndStart
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    promptSection
                    if appState.isGeneratingAgent {
                        loadingSection
                    }
                    if let error = appState.generateAgentError {
                        errorSection(error)
                    }
                    if let spec = appState.generatedAgentSpec {
                        AgentPreviewCard(
                            spec: spec,
                            onSave: { agent in
                                modelContext.insert(agent)
                                try? modelContext.save()
                                onSave(agent)
                                cleanupAndDismiss()
                            },
                            onSaveAndStart: onSaveAndStart.map { callback in
                                { agent in
                                    modelContext.insert(agent)
                                    try? modelContext.save()
                                    callback(agent)
                                    cleanupAndDismiss()
                                }
                            },
                            onEditFull: { updatedSpec in
                                specForEditor = updatedSpec
                                showingFullEditor = true
                            },
                            onCancel: {
                                appState.generatedAgentSpec = nil
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .animation(.easeInOut(duration: 0.25), value: appState.generatedAgentSpec != nil)
        .animation(.easeInOut(duration: 0.25), value: appState.isGeneratingAgent)
        .sheet(isPresented: $showingFullEditor) {
            if let spec = specForEditor {
                let prefilled = Agent(
                    name: spec.name,
                    agentDescription: spec.description,
                    systemPrompt: spec.systemPrompt,
                    model: spec.model,
                    icon: spec.icon,
                    color: spec.color
                )
                AgentEditorView(agent: prefilled) { savedAgent in
                    onSave(savedAgent)
                    showingFullEditor = false
                    cleanupAndDismiss()
                }
                .frame(minWidth: 600, minHeight: 500)
                .onAppear {
                    prefilled.skillIds = spec.matchedSkillIds.compactMap { UUID(uuidString: $0) }
                    prefilled.extraMCPServerIds = spec.matchedMCPIds.compactMap { UUID(uuidString: $0) }
                    prefilled.maxTurns = spec.maxTurns
                    prefilled.maxBudget = spec.maxBudget
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Create Agent from Prompt")
                .font(.title3)
                .fontWeight(.semibold)
                .xrayId("agentFromPrompt.title")
            Spacer()
            Button { cleanupAndDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .xrayId("agentFromPrompt.closeButton")
            .accessibilityLabel("Close")
        }
        .padding()
    }

    // MARK: - Prompt Section

    @ViewBuilder
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Describe the agent you want to create")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .xrayId("agentFromPrompt.promptEditor")

            HStack {
                Text("e.g. \"A code reviewer focused on security and OWASP top 10\"")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    generateAgent()
                } label: {
                    Label("Generate", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isGeneratingAgent)
                .xrayId("agentFromPrompt.generateButton")
            }
        }
    }

    // MARK: - Loading

    @ViewBuilder
    private var loadingSection: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Generating agent definition...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
        .xrayId("agentFromPrompt.loadingIndicator")
    }

    // MARK: - Error

    @ViewBuilder
    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Generation failed")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                generateAgent()
            }
            .buttonStyle(.bordered)
            .xrayId("agentFromPrompt.retryButton")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.red.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .xrayId("agentFromPrompt.errorSection")
    }

    // MARK: - Actions

    private func generateAgent() {
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
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            skills: skillEntries,
            mcps: mcpEntries
        )
    }

    private func cleanupAndDismiss() {
        appState.generatedAgentSpec = nil
        appState.generateAgentError = nil
        appState.isGeneratingAgent = false
        dismiss()
    }
}
