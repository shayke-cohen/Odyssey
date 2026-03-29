import Foundation

/// JSON payload exchanged between ClaudeStudio instances on the LAN (P2P v1).
struct WireAgentExport: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var agentDescription: String
    var systemPrompt: String
    var provider: String
    var model: String
    var maxTurns: Int?
    var maxBudget: Double?
    var maxThinkingTokens: Int?
    var icon: String
    var color: String
    var defaultWorkingDirectory: String?
    var skillNames: [String]
    var extraMCPNames: [String]
    var permissionSetName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, agentDescription, systemPrompt, provider, model, maxTurns, maxBudget, maxThinkingTokens
        case icon, color, defaultWorkingDirectory, skillNames, extraMCPNames, permissionSetName
    }

    init(
        id: UUID,
        name: String,
        agentDescription: String,
        systemPrompt: String,
        provider: String = ProviderSelection.system.rawValue,
        model: String,
        maxTurns: Int?,
        maxBudget: Double?,
        maxThinkingTokens: Int?,
        icon: String,
        color: String,
        defaultWorkingDirectory: String?,
        skillNames: [String],
        extraMCPNames: [String],
        permissionSetName: String?
    ) {
        self.id = id
        self.name = name
        self.agentDescription = agentDescription
        self.systemPrompt = systemPrompt
        self.provider = provider
        self.model = model
        self.maxTurns = maxTurns
        self.maxBudget = maxBudget
        self.maxThinkingTokens = maxThinkingTokens
        self.icon = icon
        self.color = color
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.skillNames = skillNames
        self.extraMCPNames = extraMCPNames
        self.permissionSetName = permissionSetName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        agentDescription = try c.decode(String.self, forKey: .agentDescription)
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ProviderSelection.system.rawValue
        model = try c.decode(String.self, forKey: .model)
        maxTurns = try c.decodeIfPresent(Int.self, forKey: .maxTurns)
        maxBudget = try c.decodeIfPresent(Double.self, forKey: .maxBudget)
        maxThinkingTokens = try c.decodeIfPresent(Int.self, forKey: .maxThinkingTokens)
        icon = try c.decode(String.self, forKey: .icon)
        color = try c.decode(String.self, forKey: .color)
        defaultWorkingDirectory = try c.decodeIfPresent(String.self, forKey: .defaultWorkingDirectory)
        skillNames = try c.decode([String].self, forKey: .skillNames)
        extraMCPNames = try c.decode([String].self, forKey: .extraMCPNames)
        permissionSetName = try c.decodeIfPresent(String.self, forKey: .permissionSetName)
    }
}

struct WireGroupExport: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var groupDescription: String
    var icon: String
    var color: String
    var groupInstruction: String
    var defaultMission: String?
    var agentNames: [String]
}

struct WireAgentExportList: Codable, Sendable {
    var agents: [WireAgentExport]
    var groups: [WireGroupExport]?
}
