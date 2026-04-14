// Sources/OdysseyCore/Protocol/WireTypes.swift
import Foundation

/// Wire representation of a conversation/thread as returned by the REST API.
/// The iOS app reads these from GET /api/v1/conversations.
public struct ConversationSummaryWire: Codable, Sendable, Identifiable {
    public let id: String
    public let topic: String
    /// ISO 8601 timestamp string, e.g. "2026-04-13T10:00:00Z"
    public let lastMessageAt: String
    public let lastMessagePreview: String
    public let unread: Bool
    public let participants: [ParticipantWire]
    public let projectId: String?
    public let projectName: String?
    public let workingDirectory: String?

    public init(
        id: String,
        topic: String,
        lastMessageAt: String,
        lastMessagePreview: String,
        unread: Bool,
        participants: [ParticipantWire],
        projectId: String?,
        projectName: String?,
        workingDirectory: String?
    ) {
        self.id = id
        self.topic = topic
        self.lastMessageAt = lastMessageAt
        self.lastMessagePreview = lastMessagePreview
        self.unread = unread
        self.participants = participants
        self.projectId = projectId
        self.projectName = projectName
        self.workingDirectory = workingDirectory
    }
}

/// Wire representation of a single message as returned by the REST API.
public struct MessageWire: Codable, Sendable, Identifiable {
    public let id: String
    public let text: String
    /// Message type raw value: "chat", "toolCall", "toolResult", "system", etc.
    public let type: String
    public let senderParticipantId: String?
    /// ISO 8601 timestamp string
    public let timestamp: String
    public let isStreaming: Bool
    /// Present when type == "toolCall" — the tool name
    public let toolName: String?
    /// Present when type == "toolResult" — the tool output
    public let toolOutput: String?
    /// Extended thinking text, if any
    public let thinkingText: String?

    public init(
        id: String,
        text: String,
        type: String,
        senderParticipantId: String?,
        timestamp: String,
        isStreaming: Bool,
        toolName: String?,
        toolOutput: String?,
        thinkingText: String?
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.senderParticipantId = senderParticipantId
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.toolName = toolName
        self.toolOutput = toolOutput
        self.thinkingText = thinkingText
    }
}

/// Wire representation of a conversation participant.
public struct ParticipantWire: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let isAgent: Bool
    /// True if this participant is the local Mac user (as opposed to a remote peer).
    public let isLocal: Bool

    public init(id: String, displayName: String, isAgent: Bool, isLocal: Bool) {
        self.id = id
        self.displayName = displayName
        self.isAgent = isAgent
        self.isLocal = isLocal
    }
}

/// Wire representation of a project as returned by GET /api/v1/projects.
public struct ProjectSummaryWire: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let rootPath: String
    public let icon: String
    public let color: String
    public let isPinned: Bool
    public let pinnedAgentIds: [String]

    public init(
        id: String,
        name: String,
        rootPath: String,
        icon: String,
        color: String,
        isPinned: Bool,
        pinnedAgentIds: [String]
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.icon = icon
        self.color = color
        self.isPinned = isPinned
        self.pinnedAgentIds = pinnedAgentIds
    }
}
