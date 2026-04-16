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
    @State private var adjustment = ""
    @State private var showingFullEditor = false
    @State private var specForEditor: GeneratedAgentSpec?
    @State private var generationStepIndex: Int = 0

    private let generationSteps = [
        "Analyzing intent…",
        "Picking skills…",
        "Drafting system prompt…",
        "Selecting MCPs…"
    ]

    private struct StarterChip {
        let label: String
        let slug: String
        let prompt: String
    }

    private let starterChips: [StarterChip] = [
        StarterChip(
            label: "Code reviewer",
            slug: "codeReviewer",
            prompt: "A code reviewer focused on security, OWASP top 10, and code clarity. Provides constructive feedback with specific examples."
        ),
        StarterChip(
            label: "PR summarizer",
            slug: "prSummarizer",
            prompt: "Summarizes pull requests by reading the diff, extracting key changes, and writing concise release notes."
        ),
        StarterChip(
            label: "Marketing writer",
            slug: "marketingWriter",
            prompt: "Writes marketing copy for technical products. Focuses on benefits, clear language, and authentic voice."
        ),
        StarterChip(
            label: "DevOps helper",
            slug: "devopsHelper",
            prompt: "Diagnoses build/deploy issues, reads logs, suggests fixes for CI/CD pipelines and infrastructure problems."
        ),
        StarterChip(
            label: "Researcher",
            slug: "researcher",
            prompt: "Investigates topics deeply, cites sources, summarizes findings, and identifies gaps in knowledge."
        )
    ]

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
                    scarcityWarning
                    promptSection
                    if appState.isGeneratingAgent {
                        loadingSection
                    }
                    if let error = appState.generateAgentError {
                        errorSection(error)
                    }
                    if let spec = appState.generatedAgentSpec {
                        adjustmentSection
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
        .onChange(of: appState.isGeneratingAgent) { _, isGenerating in
            if isGenerating {
                startGenerationStepSimulation()
            } else {
                generationStepIndex = 0
            }
        }
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

    // MARK: - Scarcity Warning (Improvement 6)

    @ViewBuilder
    private var scarcityWarning: some View {
        if allSkills.isEmpty || allMCPs.isEmpty {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.orange)
                Text("No \(allSkills.isEmpty ? "skills" : "MCPs") installed yet — open the Catalog to install some, then your agent will have more capabilities.")
                    .font(.callout)
                Spacer()
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .xrayId("agentFromPrompt.scarcityWarning")
        }
    }

    // MARK: - Prompt Section

    @ViewBuilder
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Describe the agent you want to create")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Improvement 1: Starter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(starterChips, id: \.slug) { chip in
                        Button {
                            prompt = chip.prompt
                        } label: {
                            Text(chip.label)
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .xrayId("agentFromPrompt.starterChip.\(chip.slug)")
                    }
                }
            }

            // Improvement 3: Real placeholder overlay on TextEditor
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
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("Describe the agent — its purpose, what it should do, what it should avoid.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .xrayId("agentFromPrompt.promptEditor")

            HStack {
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

            // Improvement 7: Generation cost indicator
            Text("Each generation uses ~1500 tokens (≈$0.01-0.02 with Claude Opus).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .xrayId("agentFromPrompt.costFooter")
        }
    }

    // MARK: - Adjustment Section (Improvement 4)

    @ViewBuilder
    private var adjustmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refine the result")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Adjust: e.g. 'make it more concise', 'add web search'", text: $adjustment)
                    .textFieldStyle(.roundedBorder)
                    .xrayId("agentFromPrompt.adjustmentField")
                Button("Regenerate with adjustments") {
                    let combined = "\(prompt)\n\nAdjustments: \(adjustment)"
                    prompt = combined
                    adjustment = ""
                    generateAgent()
                }
                .buttonStyle(.bordered)
                .disabled(adjustment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isGeneratingAgent)
                .xrayId("agentFromPrompt.regenerateButton")
            }
        }
    }

    // MARK: - Loading (Improvement 2: streaming progress steps)

    @ViewBuilder
    private var loadingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(generationSteps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 10) {
                    if index < generationStepIndex {
                        // Completed step
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .frame(width: 16)
                    } else if index == generationStepIndex {
                        // Current step
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16)
                    } else {
                        // Pending step
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 10, height: 10)
                            .frame(width: 16)
                    }
                    Text(step)
                        .font(.callout)
                        .foregroundStyle(index <= generationStepIndex ? .primary : .tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
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

    private func startGenerationStepSimulation() {
        generationStepIndex = 0
        Task {
            for step in 1..<generationSteps.count {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard appState.isGeneratingAgent else { break }
                await MainActor.run {
                    generationStepIndex = step
                }
            }
        }
    }

    private func cleanupAndDismiss() {
        // Improvement 5: Log the save event (toast deferred — no existing system)
        print("[AgentFromPromptSheet] Agent saved successfully.")
        appState.generatedAgentSpec = nil
        appState.generateAgentError = nil
        appState.isGeneratingAgent = false
        dismiss()
    }
}
