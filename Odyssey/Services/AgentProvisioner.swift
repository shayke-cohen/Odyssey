import Foundation
import SwiftData

@MainActor
final class AgentProvisioner {
    struct RuntimeModeSettings: Sendable, Equatable {
        let interactive: Bool
        let instancePolicy: String?
        let instancePolicyPoolMax: Int?
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func provision(
        agent: Agent,
        mission: String?,
        mode: SessionMode = .interactive,
        workingDirOverride: String? = nil,
        providerOverride: String? = nil,
        modelOverride: String? = nil
    ) -> (AgentConfig, Session) {
        let session = Session(
            agent: agent,
            mission: mission,
            mode: mode,
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
        let mcpServers = filteredMCPServers(
            resolveMCPServers(ids: resolveEffectiveMCPServerIDs(agent: agent, skills: skills)),
            provider: session.provider,
            model: session.model
        )
        let permissions = resolvePermissions(id: agent.permissionSetId)

        let allowedTools = permissions?.allowRules ?? ["Read", "Write", "Bash", "Grep", "Glob"]

        let runtimeSettings = Self.runtimeModeSettings(agent: agent, mode: session.mode)

        var systemPrompt = agent.systemPrompt
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
            interactive: runtimeSettings.interactive ? true : nil,
            instancePolicy: runtimeSettings.instancePolicy,
            instancePolicyPoolMax: runtimeSettings.instancePolicyPoolMax
        )
    }

    static func runtimeModeSettings(agent: Agent?, mode: SessionMode) -> RuntimeModeSettings {
        switch mode {
        case .worker:
            return RuntimeModeSettings(
                interactive: false,
                instancePolicy: AgentInstancePolicy.singleton.rawValue,
                instancePolicyPoolMax: nil
            )
        case .autonomous:
            return RuntimeModeSettings(
                interactive: false,
                instancePolicy: AgentInstancePolicy.spawn.rawValue,
                instancePolicyPoolMax: nil
            )
        case .interactive:
            guard let agent else {
                return RuntimeModeSettings(interactive: true, instancePolicy: nil, instancePolicyPoolMax: nil)
            }

            let instancePolicy: String?
            switch agent.instancePolicy {
            case .agentDefault:
                instancePolicy = nil
            case .spawn, .singleton, .pool:
                instancePolicy = agent.instancePolicy.rawValue
            }

            let poolMax = agent.instancePolicy == .pool ? agent.instancePolicyPoolMax : nil
            return RuntimeModeSettings(
                interactive: true,
                instancePolicy: instancePolicy,
                instancePolicyPoolMax: poolMax
            )
        }
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
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        let byId = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }

    private func resolveMCPServers(ids: [UUID]) -> [MCPServer] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<MCPServer>(predicate: #Predicate { mcp in
            ids.contains(mcp.id) && mcp.isEnabled
        })
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        let byId = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }

    private func resolveEffectiveMCPServerIDs(agent: Agent, skills: [Skill]) -> [UUID] {
        var ordered: [UUID] = []
        var seen = Set<UUID>()

        for id in agent.extraMCPServerIds where seen.insert(id).inserted {
            ordered.append(id)
        }

        for skill in skills {
            for id in skill.mcpServerIds where seen.insert(id).inserted {
                ordered.append(id)
            }
        }

        return ordered
    }

    private func filteredMCPServers(_ servers: [MCPServer], provider: String, model: String?) -> [MCPServer] {
        let usesLocalClaudeLoop = provider == ProviderSelection.claude.rawValue
            && AgentDefaults.isOllamaBackedClaudeModel(model)
        guard provider == ProviderSelection.mlx.rawValue
            || provider == ProviderSelection.foundation.rawValue
            || usesLocalClaudeLoop else {
            return servers
        }

        // Local providers and Ollama-backed Claude sessions keep built-in tools, but we skip the
        // heavyweight ambient MCPs that can block local session startup while they bootstrap
        // external runtimes.
        let blockedNames = Set(["Argus", "AppXray", "Octocode"])
        return servers.filter { !blockedNames.contains($0.name) }
    }

    private func resolvePermissions(id: UUID?) -> PermissionSet? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<PermissionSet>(predicate: #Predicate { perm in
            perm.id == id
        })
        return try? modelContext.fetch(descriptor).first
    }
}
