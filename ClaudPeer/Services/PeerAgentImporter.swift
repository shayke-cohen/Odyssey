import Foundation
import SwiftData

@MainActor
enum PeerAgentImporter {
    static func importFromWire(_ w: WireAgentExport, peerSourceId: UUID, modelContext: ModelContext) throws -> Agent {
        let skills = try modelContext.fetch(FetchDescriptor<Skill>())
        let mcps = try modelContext.fetch(FetchDescriptor<MCPServer>())
        let perms = try modelContext.fetch(FetchDescriptor<PermissionSet>())

        let skillByName = Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0) })
        let mcpByName = Dictionary(uniqueKeysWithValues: mcps.map { ($0.name, $0) })
        let permByName = Dictionary(uniqueKeysWithValues: perms.map { ($0.name, $0) })

        let uniqueName = disambiguateName(w.name, modelContext: modelContext)
        let agent = Agent(
            name: uniqueName,
            agentDescription: w.agentDescription,
            systemPrompt: w.systemPrompt,
            model: w.model,
            icon: w.icon,
            color: w.color
        )
        agent.skillIds = w.skillNames.compactMap { skillByName[$0]?.id }
        agent.extraMCPServerIds = w.extraMCPNames.compactMap { mcpByName[$0]?.id }
        agent.permissionSetId = w.permissionSetName.flatMap { permByName[$0]?.id }
        agent.maxTurns = w.maxTurns
        agent.maxBudget = w.maxBudget
        agent.maxThinkingTokens = w.maxThinkingTokens
        agent.defaultWorkingDirectory = w.defaultWorkingDirectory
        agent.githubRepo = w.githubRepo
        agent.githubDefaultBranch = w.githubDefaultBranch
        agent.instancePolicyKind = w.instancePolicyKind.isEmpty ? "spawn" : w.instancePolicyKind
        agent.instancePolicyPoolMax = w.instancePolicyPoolMax
        agent.origin = .peer(peerId: peerSourceId)
        agent.catalogId = nil

        modelContext.insert(agent)
        try modelContext.save()
        return agent
    }

    private static func disambiguateName(_ base: String, modelContext: ModelContext) -> String {
        let existing = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
        let names = Set(existing.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) (\(n))") {
            n += 1
        }
        return "\(base) (\(n))"
    }
}
