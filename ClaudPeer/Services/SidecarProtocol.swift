import Foundation

enum SidecarCommand: Sendable {
    case sessionCreate(conversationId: String, agentConfig: AgentConfig)
    case sessionMessage(sessionId: String, text: String, attachments: [WireAttachment] = [])
    case sessionResume(sessionId: String, claudeSessionId: String)
    case sessionFork(parentSessionId: String, childSessionId: String)
    case sessionPause(sessionId: String)
    case agentRegister(agents: [AgentDefinitionWire])
    case delegateTask(sessionId: String, toAgent: String, task: String, context: String?, waitForResult: Bool)

    func encodeToJSON() throws -> Data {
        let encoder = JSONEncoder()
        switch self {
        case .sessionCreate(let conversationId, let agentConfig):
            return try encoder.encode(
                SessionCreateWire(type: "session.create", conversationId: conversationId, agentConfig: agentConfig)
            )
        case .sessionMessage(let sessionId, let text, let attachments):
            return try encoder.encode(
                SessionMessageWire(
                    type: "session.message",
                    sessionId: sessionId,
                    text: text,
                    attachments: attachments.isEmpty ? nil : attachments
                )
            )
        case .sessionResume(let sessionId, let claudeSessionId):
            return try encoder.encode(
                SessionResumeWire(type: "session.resume", sessionId: sessionId, claudeSessionId: claudeSessionId)
            )
        case .sessionFork(let parentSessionId, let childSessionId):
            return try encoder.encode(
                SessionForkWire(type: "session.fork", sessionId: parentSessionId, childSessionId: childSessionId)
            )
        case .sessionPause(let sessionId):
            return try encoder.encode(
                SessionIdWire(type: "session.pause", sessionId: sessionId)
            )
        case .agentRegister(let agents):
            return try encoder.encode(
                AgentRegisterWire(type: "agent.register", agents: agents)
            )
        case .delegateTask(let sessionId, let toAgent, let task, let context, let waitForResult):
            return try encoder.encode(
                DelegateTaskWire(type: "delegate.task", sessionId: sessionId, toAgent: toAgent, task: task, context: context, waitForResult: waitForResult)
            )
        }
    }
}

struct AgentDefinitionWire: Codable, Sendable {
    let name: String
    let config: AgentConfig
    let instancePolicy: String
}

private struct AgentRegisterWire: Encodable {
    let type: String
    let agents: [AgentDefinitionWire]
}

private struct SessionCreateWire: Encodable {
    let type: String
    let conversationId: String
    let agentConfig: AgentConfig
}

private struct SessionMessageWire: Encodable {
    let type: String
    let sessionId: String
    let text: String
    let attachments: [WireAttachment]?
}

struct WireAttachment: Codable, Sendable {
    let data: String
    let mediaType: String
    let fileName: String?
}

private struct SessionResumeWire: Encodable {
    let type: String
    let sessionId: String
    let claudeSessionId: String
}

private struct SessionIdWire: Encodable {
    let type: String
    let sessionId: String
}

private struct SessionForkWire: Encodable {
    let type: String
    let sessionId: String
    let childSessionId: String
}

private struct DelegateTaskWire: Encodable {
    let type: String
    let sessionId: String
    let toAgent: String
    let task: String
    let context: String?
    let waitForResult: Bool
}

struct AgentConfig: Codable, Sendable {
    let name: String
    let systemPrompt: String
    let allowedTools: [String]
    let mcpServers: [MCPServerConfig]
    let model: String
    let maxTurns: Int?
    let maxBudget: Double?
    let maxThinkingTokens: Int?
    let workingDirectory: String
    let skills: [SkillContent]

    struct MCPServerConfig: Codable, Sendable {
        let name: String
        let command: String?
        let args: [String]?
        let env: [String: String]?
        let url: String?
    }

    struct SkillContent: Codable, Sendable {
        let name: String
        let content: String
    }
}

enum SidecarEvent: Sendable {
    case streamToken(sessionId: String, text: String)
    case streamThinking(sessionId: String, text: String)
    case streamToolCall(sessionId: String, tool: String, input: String)
    case streamToolResult(sessionId: String, tool: String, output: String)
    case sessionResult(sessionId: String, result: String, cost: Double)
    case sessionError(sessionId: String, error: String)
    case peerChat(channelId: String, from: String, message: String)
    case peerDelegate(from: String, to: String, task: String)
    case blackboardUpdate(key: String, value: String, writtenBy: String)
    case sessionForked(parentSessionId: String, childSessionId: String)
    case streamImage(sessionId: String, imageData: String, mediaType: String, fileName: String?)
    case streamFileCard(sessionId: String, filePath: String, fileType: String, fileName: String)
    case connected
    case disconnected
}


struct IncomingWireMessage: Codable, Sendable {
    let type: String
    let sessionId: String?
    let text: String?
    let tool: String?
    let input: String?
    let output: String?
    let result: String?
    let cost: Double?
    let error: String?
    let channelId: String?
    let from: String?
    let to: String?
    let message: String?
    let task: String?
    let key: String?
    let value: String?
    let writtenBy: String?
    let parentSessionId: String?
    let childSessionId: String?
    let imageData: String?
    let mediaType: String?
    let filePath: String?
    let fileType: String?
    let fileName: String?

    func toEvent() -> SidecarEvent? {
        switch type {
        case "stream.token":
            guard let sid = sessionId, let t = text else { return nil }
            return .streamToken(sessionId: sid, text: t)
        case "stream.thinking":
            guard let sid = sessionId, let t = text else { return nil }
            return .streamThinking(sessionId: sid, text: t)
        case "stream.toolCall":
            guard let sid = sessionId, let t = tool else { return nil }
            return .streamToolCall(sessionId: sid, tool: t, input: input ?? "")
        case "stream.toolResult":
            guard let sid = sessionId, let t = tool else { return nil }
            return .streamToolResult(sessionId: sid, tool: t, output: output ?? "")
        case "session.result":
            guard let sid = sessionId else { return nil }
            return .sessionResult(sessionId: sid, result: result ?? "", cost: cost ?? 0)
        case "session.error":
            guard let sid = sessionId else { return nil }
            return .sessionError(sessionId: sid, error: error ?? "Unknown error")
        case "peer.chat":
            guard let ch = channelId, let f = from, let m = message else { return nil }
            return .peerChat(channelId: ch, from: f, message: m)
        case "peer.delegate":
            guard let f = from, let t = to, let tk = task else { return nil }
            return .peerDelegate(from: f, to: t, task: tk)
        case "blackboard.update":
            guard let k = key, let v = value, let w = writtenBy else { return nil }
            return .blackboardUpdate(key: k, value: v, writtenBy: w)
        case "session.forked":
            guard let p = parentSessionId, let c = childSessionId else { return nil }
            return .sessionForked(parentSessionId: p, childSessionId: c)
        case "stream.image":
            guard let sid = sessionId, let img = imageData, let mt = mediaType else { return nil }
            return .streamImage(sessionId: sid, imageData: img, mediaType: mt, fileName: fileName)
        case "stream.fileCard":
            guard let sid = sessionId, let fp = filePath, let ft = fileType, let fn = fileName else { return nil }
            return .streamFileCard(sessionId: sid, filePath: fp, fileType: ft, fileName: fn)
        default:
            return nil
        }
    }
}
