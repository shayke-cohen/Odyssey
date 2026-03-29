import Foundation
import SwiftData

@MainActor
final class AgentProvisioner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func provision(
        agent: Agent,
        mission: String?,
        workingDirOverride: String? = nil,
        providerOverride: String? = nil,
        modelOverride: String? = nil
    ) -> (AgentConfig, Session) {
        let session = Session(
            agent: agent,
            mission: mission,
            mode: .interactive,
            workingDirectory: resolveWorkingDirectory(override: workingDirOverride)
        )
        session.provider = AgentDefaults.resolveEffectiveProvider(
            sessionOverride: providerOverride,
            agentSelection: agent.provider
        )
        session.model = AgentDefaults.resolveEffectiveModel(
            sessionOverride: modelOverride,
            agentSelection: agent.model,
            provider: session.provider
        )

        return (buildConfig(agent: agent, session: session), session)
    }

    func config(for session: Session) -> AgentConfig? {
        guard let agent = session.agent else { return nil }
        return buildConfig(agent: agent, session: session)
    }

    private func buildConfig(agent: Agent, session: Session) -> AgentConfig {
        let skills = resolveSkills(ids: agent.skillIds)
        let mcpServers = resolveMCPServers(ids: agent.extraMCPServerIds)
        let permissions = resolvePermissions(id: agent.permissionSetId)

        var allowedTools = permissions?.allowRules ?? ["Read", "Write", "Bash", "Grep", "Glob"]
        allowedTools.append(contentsOf: [
            "peer_chat_start", "peer_chat_reply", "peer_chat_listen",
            "peer_chat_close", "peer_chat_invite",
            "peer_send_message", "peer_delegate_task", "peer_receive_messages",
            "peer_list_agents", "peer_broadcast",
            "blackboard_read", "blackboard_write", "blackboard_query", "blackboard_subscribe",
            "workspace_create", "workspace_join", "workspace_list",
        ])

        let isInteractive = session.mode == .interactive
        if isInteractive {
            allowedTools.append("ask_user")
        }

        var systemPrompt = agent.systemPrompt
        if !skills.isEmpty {
            systemPrompt += "\n\n# Available Skills\n"
            for skill in skills {
                systemPrompt += "\n## \(skill.name)\n\(skill.content)\n"
            }
        }
        if let mission = session.mission {
            systemPrompt += "\n\n# Current Mission\n\(mission)\n"
        }

        return AgentConfig(
            name: agent.name,
            systemPrompt: systemPrompt,
            allowedTools: allowedTools,
            mcpServers: mcpServers.map { mcp in
                switch mcp.transport {
                case .stdio(let command, let args, let env):
                    return AgentConfig.MCPServerConfig(
                        name: mcp.name, command: command, args: args, env: env, url: nil
                    )
                case .http(let url, _):
                    return AgentConfig.MCPServerConfig(
                        name: mcp.name, command: nil, args: nil, env: nil, url: url
                    )
                }
            },
            provider: session.provider,
            model: session.model ?? AgentDefaults.resolveEffectiveModel(
                agentSelection: agent.model,
                provider: session.provider
            ),
            maxTurns: agent.maxTurns,
            maxBudget: agent.maxBudget,
            maxThinkingTokens: agent.maxThinkingTokens,
            workingDirectory: session.workingDirectory,
            skills: skills.map { AgentConfig.SkillContent(name: $0.name, content: $0.content) },
            interactive: isInteractive ? true : nil
        )
    }

    private func resolveWorkingDirectory(override: String?) -> String {
        if let explicit = override, !explicit.isEmpty { return explicit }
        return NSHomeDirectory() // defensive fallback — should always have override from worktree
    }

    private func resolveSkills(ids: [UUID]) -> [Skill] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Skill>(predicate: #Predicate { skill in
            ids.contains(skill.id) && skill.isEnabled
        })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func resolveMCPServers(ids: [UUID]) -> [MCPServer] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<MCPServer>(predicate: #Predicate { mcp in
            ids.contains(mcp.id) && mcp.isEnabled
        })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func resolvePermissions(id: UUID?) -> PermissionSet? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<PermissionSet>(predicate: #Predicate { perm in
            perm.id == id
        })
        return try? modelContext.fetch(descriptor).first
    }
}
