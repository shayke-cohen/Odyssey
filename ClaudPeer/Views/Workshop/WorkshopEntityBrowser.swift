import SwiftUI
import SwiftData

enum WorkshopTab: String, CaseIterable, Identifiable {
    case agents = "Agents"
    case groups = "Groups"
    case skills = "Skills"
    case mcps = "MCPs"
    case permissions = "Permissions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agents: return "cpu"
        case .groups: return "person.3"
        case .skills: return "book"
        case .mcps: return "server.rack"
        case .permissions: return "lock.shield"
        }
    }
}

struct WorkshopEntityBrowser: View {
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.name) private var groups: [AgentGroup]
    @Query(sort: \Skill.name) private var skills: [Skill]
    @Query(sort: \MCPServer.name) private var mcps: [MCPServer]
    @Query(sort: \PermissionSet.name) private var permissions: [PermissionSet]

    @Binding var selectedTab: WorkshopTab
    @Binding var selectedEntityContext: String?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Entity Type", selection: $selectedTab) {
                ForEach(WorkshopTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .xrayId("workshop.tabPicker")

            TextField("Search \(selectedTab.rawValue.lowercased())...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .xrayId("workshop.searchField")

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    switch selectedTab {
                    case .agents:
                        ForEach(filteredAgents) { agent in
                            WorkshopEntityRow(
                                icon: agent.icon,
                                color: agent.color,
                                name: agent.name,
                                subtitle: agent.agentDescription,
                                isEnabled: agent.isEnabled,
                                badges: [agent.model, "\(agent.skillIds.count) skills"]
                            ) {
                                selectedEntityContext = agentContextString(agent)
                            }
                            .xrayId("workshop.agentRow.\(agent.id.uuidString)")
                        }
                    case .groups:
                        ForEach(filteredGroups) { group in
                            WorkshopEntityRow(
                                icon: group.icon,
                                color: group.color,
                                name: group.name,
                                subtitle: group.groupDescription,
                                isEnabled: group.isEnabled,
                                badges: ["\(group.agentIds.count) agents"]
                            ) {
                                selectedEntityContext = groupContextString(group)
                            }
                            .xrayId("workshop.groupRow.\(group.id.uuidString)")
                        }
                    case .skills:
                        ForEach(filteredSkills) { skill in
                            WorkshopEntityRow(
                                icon: "book.fill",
                                color: "blue",
                                name: skill.name,
                                subtitle: skill.skillDescription,
                                isEnabled: skill.isEnabled,
                                badges: [skill.category, "v\(skill.version)"]
                            ) {
                                selectedEntityContext = skillContextString(skill)
                            }
                            .xrayId("workshop.skillRow.\(skill.id.uuidString)")
                        }
                    case .mcps:
                        ForEach(filteredMCPs) { mcp in
                            WorkshopEntityRow(
                                icon: "server.rack",
                                color: "purple",
                                name: mcp.name,
                                subtitle: mcp.serverDescription,
                                isEnabled: mcp.isEnabled,
                                badges: [mcp.transportKind]
                            ) {
                                selectedEntityContext = mcpContextString(mcp)
                            }
                            .xrayId("workshop.mcpRow.\(mcp.id.uuidString)")
                        }
                    case .permissions:
                        ForEach(filteredPermissions) { perm in
                            WorkshopEntityRow(
                                icon: "lock.shield.fill",
                                color: "orange",
                                name: perm.name,
                                subtitle: "\(perm.allowRules.count) allow, \(perm.denyRules.count) deny",
                                isEnabled: perm.isEnabled,
                                badges: [perm.permissionMode]
                            ) {
                                selectedEntityContext = permContextString(perm)
                            }
                            .xrayId("workshop.permRow.\(perm.id.uuidString)")
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .xrayId("workshop.entityList")
        }
    }

    // MARK: - Filtered collections

    private var filteredAgents: [Agent] {
        guard !searchText.isEmpty else { return Array(agents) }
        return agents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.agentDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredGroups: [AgentGroup] {
        guard !searchText.isEmpty else { return Array(groups) }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.groupDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredSkills: [Skill] {
        guard !searchText.isEmpty else { return Array(skills) }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.skillDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredMCPs: [MCPServer] {
        guard !searchText.isEmpty else { return Array(mcps) }
        return mcps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.serverDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredPermissions: [PermissionSet] {
        guard !searchText.isEmpty else { return Array(permissions) }
        return permissions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Context strings

    private func agentContextString(_ a: Agent) -> String {
        """
        [Context: User selected agent "\(a.name)" (slug: \(a.configSlug ?? "unknown"))]
        Model: \(a.model), Icon: \(a.icon), Color: \(a.color)
        Skills: \(a.skillIds.count), MCPs: \(a.extraMCPServerIds.count)
        Enabled: \(a.isEnabled), Policy: \(a.instancePolicyKind)
        Budget: $\(String(format: "%.2f", a.maxBudget ?? 0)), Max turns: \(a.maxTurns ?? 0)
        Description: \(a.agentDescription)
        """
    }

    private func groupContextString(_ g: AgentGroup) -> String {
        """
        [Context: User selected group "\(g.name)" (slug: \(g.configSlug ?? "unknown"))]
        Agents: \(g.agentIds.count), Auto-reply: \(g.autoReplyEnabled), Autonomous: \(g.autonomousCapable)
        Description: \(g.groupDescription)
        Instruction: \(g.groupInstruction.isEmpty ? "none" : g.groupInstruction)
        """
    }

    private func skillContextString(_ s: Skill) -> String {
        """
        [Context: User selected skill "\(s.name)" (slug: \(s.configSlug ?? "unknown"))]
        Category: \(s.category), Version: \(s.version), Enabled: \(s.isEnabled)
        Description: \(s.skillDescription)
        """
    }

    private func mcpContextString(_ m: MCPServer) -> String {
        """
        [Context: User selected MCP server "\(m.name)" (slug: \(m.configSlug ?? "unknown"))]
        Transport: \(m.transportKind), Enabled: \(m.isEnabled)
        Description: \(m.serverDescription)
        """
    }

    private func permContextString(_ p: PermissionSet) -> String {
        """
        [Context: User selected permission preset "\(p.name)" (slug: \(p.configSlug ?? "unknown"))]
        Allow: \(p.allowRules.joined(separator: ", "))
        Deny: \(p.denyRules.joined(separator: ", "))
        Mode: \(p.permissionMode), Enabled: \(p.isEnabled)
        """
    }
}
