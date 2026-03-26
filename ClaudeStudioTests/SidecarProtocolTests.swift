import XCTest
@testable import ClaudeStudio

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

    // MARK: - Task Board Command Encoding

    func testTaskCreateEncoding() throws {
        let task = TaskWireSwift(
            id: "task-1",
            title: "Fix bug",
            description: "Login broken",
            status: "ready",
            priority: "high",
            labels: ["auth"],
            result: nil,
            parentTaskId: nil,
            assignedAgentId: nil,
            assignedGroupId: nil,
            conversationId: nil,
            createdAt: "2026-03-25T00:00:00Z",
            startedAt: nil,
            completedAt: nil
        )
        let command = SidecarCommand.taskCreate(task: task)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "task.create")
        let taskJson = json["task"] as? [String: Any]
        XCTAssertEqual(taskJson?["id"] as? String, "task-1")
        XCTAssertEqual(taskJson?["title"] as? String, "Fix bug")
        XCTAssertEqual(taskJson?["status"] as? String, "ready")
        XCTAssertEqual(taskJson?["priority"] as? String, "high")
        XCTAssertEqual(taskJson?["labels"] as? [String], ["auth"])
    }

    func testTaskClaimEncoding() throws {
        let command = SidecarCommand.taskClaim(taskId: "task-42", agentName: "Orchestrator")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "task.claim")
        XCTAssertEqual(json["taskId"] as? String, "task-42")
        XCTAssertEqual(json["agentName"] as? String, "Orchestrator")
    }

    func testTaskListEncoding() throws {
        let command = SidecarCommand.taskList(filter: TaskListFilter(status: "ready"))
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "task.list")
        let filter = json["filter"] as? [String: Any]
        XCTAssertEqual(filter?["status"] as? String, "ready")
    }

    func testTaskListEncodingNoFilter() throws {
        let command = SidecarCommand.taskList(filter: nil)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "task.list")
    }

    // MARK: - Task Board Event Decoding

    func testTaskCreatedDecoding() throws {
        let jsonStr = """
        {"type":"task.created","task":{"id":"t-1","title":"Fix bug","description":"","status":"ready","priority":"high","labels":["auth"],"createdAt":"2026-03-25T00:00:00Z"}}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .taskCreated(let task) = event {
            XCTAssertEqual(task.id, "t-1")
            XCTAssertEqual(task.title, "Fix bug")
            XCTAssertEqual(task.status, "ready")
            XCTAssertEqual(task.priority, "high")
            XCTAssertEqual(task.labels, ["auth"])
        } else {
            XCTFail("Expected .taskCreated event, got \(String(describing: event))")
        }
    }

    func testTaskUpdatedDecoding() throws {
        let jsonStr = """
        {"type":"task.updated","task":{"id":"t-2","title":"Deploy","description":"","status":"done","priority":"medium","labels":[],"result":"Deployed v2.1","createdAt":"2026-03-25T00:00:00Z","completedAt":"2026-03-25T01:00:00Z"}}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .taskUpdated(let task) = event {
            XCTAssertEqual(task.id, "t-2")
            XCTAssertEqual(task.status, "done")
            XCTAssertEqual(task.result, "Deployed v2.1")
            XCTAssertEqual(task.completedAt, "2026-03-25T01:00:00Z")
        } else {
            XCTFail("Expected .taskUpdated event, got \(String(describing: event))")
        }
    }

    func testTaskListResultDecoding() throws {
        let jsonStr = """
        {"type":"task.list.result","tasks":[{"id":"t-1","title":"A","description":"","status":"ready","priority":"low","labels":[],"createdAt":"2026-03-25T00:00:00Z"},{"id":"t-2","title":"B","description":"","status":"done","priority":"high","labels":["x"],"createdAt":"2026-03-25T00:00:00Z"}]}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .taskListResult(let tasks) = event {
            XCTAssertEqual(tasks.count, 2)
            XCTAssertEqual(tasks[0].title, "A")
            XCTAssertEqual(tasks[1].title, "B")
        } else {
            XCTFail("Expected .taskListResult event, got \(String(describing: event))")
        }
    }

    func testTaskListResultEmptyDecoding() throws {
        let jsonStr = """
        {"type":"task.list.result"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .taskListResult(let tasks) = event {
            XCTAssertEqual(tasks.count, 0)
        } else {
            XCTFail("Expected .taskListResult event, got \(String(describing: event))")
        }
    }
}
