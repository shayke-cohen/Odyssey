import SwiftUI
import SwiftData

struct AgentPreviewCard: View {
    let spec: GeneratedAgentSpec
    let onSave: (Agent) -> Void
    let onSaveAndStart: ((Agent) -> Void)?
    let onEditFull: ((GeneratedAgentSpec) -> Void)?
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    @State private var name: String
    @State private var description: String
    @State private var icon: String
    @State private var color: String
    @State private var model: String
    @State private var matchedSkillIds: Set<String>
    @State private var matchedMCPIds: Set<String>
    @State private var systemPrompt: String
    @State private var showSystemPrompt = false

    init(
        spec: GeneratedAgentSpec,
        onSave: @escaping (Agent) -> Void,
        onSaveAndStart: ((Agent) -> Void)? = nil,
        onEditFull: ((GeneratedAgentSpec) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.spec = spec
        self.onSave = onSave
        self.onSaveAndStart = onSaveAndStart
        self.onEditFull = onEditFull
        self.onCancel = onCancel
        _name = State(initialValue: spec.name)
        _description = State(initialValue: spec.description)
        _icon = State(initialValue: spec.icon)
        _color = State(initialValue: spec.color)
        _model = State(initialValue: spec.model)
        _matchedSkillIds = State(initialValue: Set(spec.matchedSkillIds))
        _matchedMCPIds = State(initialValue: Set(spec.matchedMCPIds))
        _systemPrompt = State(initialValue: spec.systemPrompt)
    }

    private static let validColors = ["blue", "red", "green", "purple", "orange", "teal", "pink", "indigo", "gray"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: icon + name
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(Color.fromAgentColor(color))
                    .frame(width: 40, height: 40)
                    .background(Color.fromAgentColor(color).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .xrayId("agentPreview.iconDisplay")

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Agent Name", text: $name)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .xrayId("agentPreview.nameField")
                    TextField("Description", text: $description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)
                        .xrayId("agentPreview.descriptionField")
                }
                Spacer()
            }

            // Pickers row
            HStack(spacing: 16) {
                // Icon field
                HStack(spacing: 4) {
                    Text("Icon:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("SF Symbol", text: $icon)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .xrayId("agentPreview.iconField")
                }

                // Color picker
                HStack(spacing: 4) {
                    Text("Color:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $color) {
                        ForEach(Self.validColors, id: \.self) { c in
                            HStack(spacing: 4) {
                                Circle().fill(Color.fromAgentColor(c)).frame(width: 8, height: 8)
                                Text(c.capitalized)
                            }.tag(c)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    .xrayId("agentPreview.colorPicker")
                }

                // Model picker
                HStack(spacing: 4) {
                    Text("Model:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $model) {
                        Text("Sonnet").tag("sonnet")
                        Text("Opus").tag("opus")
                        Text("Haiku").tag("haiku")
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .xrayId("agentPreview.modelPicker")
                }
            }

            // Skills chips
            if !matchedSkillIds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skills")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(allSkills.filter { matchedSkillIds.contains($0.id.uuidString) }) { skill in
                            HStack(spacing: 4) {
                                Text(skill.name)
                                    .font(.caption)
                                Button {
                                    matchedSkillIds.remove(skill.id.uuidString)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .xrayId("agentPreview.skill.remove.\(skill.id.uuidString)")
                                .accessibilityLabel("Remove \(skill.name)")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    .xrayId("agentPreview.skillChips")
                }
            }

            // MCP chips
            if !matchedMCPIds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCP Servers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(allMCPs.filter { matchedMCPIds.contains($0.id.uuidString) }) { mcp in
                            HStack(spacing: 4) {
                                Text(mcp.name)
                                    .font(.caption)
                                Button {
                                    matchedMCPIds.remove(mcp.id.uuidString)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .xrayId("agentPreview.mcp.remove.\(mcp.id.uuidString)")
                                .accessibilityLabel("Remove \(mcp.name)")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    .xrayId("agentPreview.mcpChips")
                }
            }

            // System prompt (expandable)
            DisclosureGroup("System Prompt (\(systemPrompt.count) chars)", isExpanded: $showSystemPrompt) {
                TextEditor(text: $systemPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 100, maxHeight: 200)
                    .padding(4)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .xrayId("agentPreview.systemPromptEditor")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .xrayId("agentPreview.systemPromptDisclosure")

            // Action buttons
            HStack {
                if let onEditFull {
                    Button {
                        onEditFull(currentSpec)
                    } label: {
                        Label("Edit in Full Editor", systemImage: "slider.horizontal.3")
                            .font(.caption)
                    }
                    .xrayId("agentPreview.editFullButton")
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .xrayId("agentPreview.cancelButton")

                if let onSaveAndStart {
                    Button("Save & Start") {
                        let agent = buildAgent()
                        onSaveAndStart(agent)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
                    .xrayId("agentPreview.saveAndStartButton")
                }

                Button("Save") {
                    let agent = buildAgent()
                    onSave(agent)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .xrayId("agentPreview.saveButton")
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var currentSpec: GeneratedAgentSpec {
        GeneratedAgentSpec(
            name: name,
            description: description,
            systemPrompt: systemPrompt,
            model: model,
            icon: icon,
            color: color,
            matchedSkillIds: Array(matchedSkillIds),
            matchedMCPIds: Array(matchedMCPIds),
            maxTurns: spec.maxTurns,
            maxBudget: spec.maxBudget
        )
    }

    private func buildAgent() -> Agent {
        let agent = Agent(
            name: name,
            agentDescription: description,
            systemPrompt: systemPrompt,
            model: model,
            icon: icon,
            color: color
        )
        agent.skillIds = matchedSkillIds.compactMap { UUID(uuidString: $0) }
        agent.extraMCPServerIds = matchedMCPIds.compactMap { UUID(uuidString: $0) }
        agent.maxTurns = spec.maxTurns
        agent.maxBudget = spec.maxBudget
        return agent
    }
}

// MARK: - Flow Layout

/// A simple horizontal flow layout that wraps items to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return LayoutResult(
            size: CGSize(width: maxX, height: y + rowHeight),
            positions: positions
        )
    }
}
