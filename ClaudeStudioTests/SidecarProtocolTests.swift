import XCTest
@testable import ClaudPeer

final class SidecarProtocolTests: XCTestCase {

    // MARK: - Command Encoding

    func testDelegateTaskEncoding() throws {
        let command = SidecarCommand.delegateTask(
            sessionId: "conv-123",
            toAgent: "Coder",
            task: "implement login",
            context: "Use OAuth 2.0",
            waitForResult: true
        )
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "delegate.task")
        XCTAssertEqual(json["sessionId"] as? String, "conv-123")
        XCTAssertEqual(json["toAgent"] as? String, "Coder")
        XCTAssertEqual(json["task"] as? String, "implement login")
        XCTAssertEqual(json["context"] as? String, "Use OAuth 2.0")
        XCTAssertEqual(json["waitForResult"] as? Bool, true)
    }

    func testSessionCreateEncoding() throws {
        let config = AgentConfig(
            name: "TestBot",
            systemPrompt: "Say hi",
            allowedTools: ["Read"],
            mcpServers: [],
            model: "claude-sonnet-4-6",
            maxTurns: 5,
            maxBudget: nil,
            maxThinkingTokens: nil,
            workingDirectory: "/tmp",
            skills: []
        )
        let command = SidecarCommand.sessionCreate(conversationId: "conv-456", agentConfig: config)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.create")
        XCTAssertEqual(json["conversationId"] as? String, "conv-456")
        let agentConfig = json["agentConfig"] as? [String: Any]
        XCTAssertEqual(agentConfig?["name"] as? String, "TestBot")
        XCTAssertEqual(agentConfig?["model"] as? String, "claude-sonnet-4-6")
    }

    func testSessionMessageEncoding() throws {
        let command = SidecarCommand.sessionMessage(sessionId: "sess-789", text: "Hello agent")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.message")
        XCTAssertEqual(json["sessionId"] as? String, "sess-789")
        XCTAssertEqual(json["text"] as? String, "Hello agent")
    }

    func testSessionForkEncoding() throws {
        let command = SidecarCommand.sessionFork(parentSessionId: "parent-1", childSessionId: "child-2")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.fork")
        XCTAssertEqual(json["sessionId"] as? String, "parent-1")
        XCTAssertEqual(json["childSessionId"] as? String, "child-2")
    }

    func testSessionForkedDecoding() throws {
        let jsonStr = """
        {"type":"session.forked","parentSessionId":"p1","childSessionId":"c2"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .sessionForked(let p, let c) = event {
            XCTAssertEqual(p, "p1")
            XCTAssertEqual(c, "c2")
        } else {
            XCTFail("Expected .sessionForked, got \(String(describing: event))")
        }
    }

    // MARK: - Incoming Wire Message Decoding

    func testPeerChatDecoding() throws {
        let jsonStr = """
        {"type":"peer.chat","channelId":"ch-1","from":"AgentA","message":"discuss design"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .peerChat(let channelId, let from, let message) = event {
            XCTAssertEqual(channelId, "ch-1")
            XCTAssertEqual(from, "AgentA")
            XCTAssertEqual(message, "discuss design")
        } else {
            XCTFail("Expected .peerChat event, got \(String(describing: event))")
        }
    }

    func testPeerDelegateDecoding() throws {
        let jsonStr = """
        {"type":"peer.delegate","from":"Orchestrator","to":"Coder","task":"implement feature"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .peerDelegate(let from, let to, let task) = event {
            XCTAssertEqual(from, "Orchestrator")
            XCTAssertEqual(to, "Coder")
            XCTAssertEqual(task, "implement feature")
        } else {
            XCTFail("Expected .peerDelegate event, got \(String(describing: event))")
        }
    }

    func testBlackboardUpdateDecoding() throws {
        let jsonStr = """
        {"type":"blackboard.update","key":"pipeline.phase","value":"research","writtenBy":"Orchestrator"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .blackboardUpdate(let key, let value, let writtenBy) = event {
            XCTAssertEqual(key, "pipeline.phase")
            XCTAssertEqual(value, "research")
            XCTAssertEqual(writtenBy, "Orchestrator")
        } else {
            XCTFail("Expected .blackboardUpdate event, got \(String(describing: event))")
        }
    }

    func testUnknownTypeReturnsNil() throws {
        let jsonStr = """
        {"type":"unknown.event","sessionId":"123"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        XCTAssertNil(wire.toEvent())
    }
}
