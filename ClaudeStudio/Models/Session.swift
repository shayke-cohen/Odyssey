import Foundation
import SwiftData

enum SessionStatus: String, Codable, Sendable {
    case active
    case paused
    case interrupted
    case completed
    case failed
}

enum SessionMode: String, Codable, Sendable {
    case interactive
    case autonomous
    case worker
}

@Model
final class Session {
    var id: UUID
    var claudeSessionId: String?
    var provider: String = AppSettings.defaultProvider
    var model: String?
    var agent: Agent?
    var mission: String?
    var status: SessionStatus
    var mode: SessionMode
    var workingDirectory: String
    var parentSessionId: UUID?
    var pid: Int?
    var startedAt: Date
    var lastActiveAt: Date
    var tokenCount: Int
    var totalCost: Double
    var toolCallCount: Int

    /// Watermark for group transcript injection: last `ConversationMessage.id` included in a prompt to this session.
    var lastInjectedMessageId: UUID?

    /// Inverse is declared on `Conversation.sessions`; omitting `inverse` here avoids a SwiftData macro cycle (SDK 26).
    @Relationship(deleteRule: .nullify)
    var conversations: [Conversation] = []

    init(
        agent: Agent?,
        mission: String? = nil,
        mode: SessionMode = .interactive,
        workingDirectory: String = ""
    ) {
        self.id = UUID()
        self.agent = agent
        self.mission = mission
        self.status = .active
        self.mode = mode
        self.workingDirectory = workingDirectory
        self.startedAt = Date()
        self.lastActiveAt = Date()
        self.tokenCount = 0
        self.totalCost = 0
        self.toolCallCount = 0
        self.lastInjectedMessageId = nil
        self.provider = AgentDefaults.resolveEffectiveProvider(agentSelection: agent?.provider)
        self.model = AgentDefaults.resolveEffectiveModel(agentSelection: agent?.model, provider: provider)
    }
}
