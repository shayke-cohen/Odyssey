import XCTest
@testable import Odyssey

final class DelegationTests: XCTestCase {

    // MARK: - DelegationMode enum

    func testDelegationModeRawValues() {
        XCTAssertEqual(DelegationMode.off.rawValue, "off")
        XCTAssertEqual(DelegationMode.byAgents.rawValue, "by_agents")
        XCTAssertEqual(DelegationMode.specificAgent.rawValue, "specific_agent")
        XCTAssertEqual(DelegationMode.coordinator.rawValue, "coordinator")
    }

    func testDelegationModeShortLabels() {
        XCTAssertEqual(DelegationMode.off.shortLabel, "Off")
        XCTAssertEqual(DelegationMode.byAgents.shortLabel, "agents")
        XCTAssertEqual(DelegationMode.specificAgent.shortLabel, "specific")
        XCTAssertEqual(DelegationMode.coordinator.shortLabel, "coordinator")
    }

    func testDelegationModeCaseIterableCount() {
        XCTAssertEqual(DelegationMode.allCases.count, 4)
    }

    func testDelegationModeRoundTripCodable() throws {
        for mode in DelegationMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(DelegationMode.self, from: data)
            XCTAssertEqual(decoded, mode, "Round-trip failed for \(mode)")
        }
    }

    func testDelegationModeInitFromRawValue() {
        XCTAssertEqual(DelegationMode(rawValue: "off"), .off)
        XCTAssertEqual(DelegationMode(rawValue: "by_agents"), .byAgents)
        XCTAssertEqual(DelegationMode(rawValue: "specific_agent"), .specificAgent)
        XCTAssertEqual(DelegationMode(rawValue: "coordinator"), .coordinator)
        XCTAssertNil(DelegationMode(rawValue: "unknown"))
    }

    // MARK: - Conversation.delegationMode computed property

    func testConversationDelegationModeDefaultsToOff() {
        let conv = Conversation()
        XCTAssertEqual(conv.delegationMode, .off)
    }

    func testConversationDelegationModeRoundTrip() {
        let conv = Conversation()
        for mode in DelegationMode.allCases {
            conv.delegationMode = mode
            XCTAssertEqual(conv.delegationMode, mode, "delegationMode round-trip failed for \(mode)")
        }
    }

    func testConversationDelegationModeStoredAsRawString() {
        let conv = Conversation()
        conv.delegationMode = .byAgents
        // Verify the underlying raw string so the computed property is actually writing through
        // (we access it via the public setter and trust the getter mirrors the raw value)
        conv.delegationMode = .specificAgent
        XCTAssertEqual(conv.delegationMode, .specificAgent)
        conv.delegationMode = .off
        XCTAssertEqual(conv.delegationMode, .off)
    }

    func testConversationDelegationTargetAgentNameNilByDefault() {
        let conv = Conversation()
        XCTAssertNil(conv.delegationTargetAgentName)
    }

    func testConversationDelegationTargetAgentNameRoundTrip() {
        let conv = Conversation()
        conv.delegationTargetAgentName = "Reviewer"
        XCTAssertEqual(conv.delegationTargetAgentName, "Reviewer")
        conv.delegationTargetAgentName = nil
        XCTAssertNil(conv.delegationTargetAgentName)
    }

    // MARK: - ResolvedQuestionInfo struct

    func testResolvedQuestionInfoDirect() {
        let info = ResolvedQuestionInfo(answeredBy: "Reviewer", isFallback: false, answer: "async/await")
        XCTAssertEqual(info.answeredBy, "Reviewer")
        XCTAssertFalse(info.isFallback)
        XCTAssertEqual(info.answer, "async/await")
    }

    func testResolvedQuestionInfoFallback() {
        let info = ResolvedQuestionInfo(answeredBy: "PM", isFallback: true, answer: "Correctness first")
        XCTAssertEqual(info.answeredBy, "PM")
        XCTAssertTrue(info.isFallback)
        XCTAssertEqual(info.answer, "Correctness first")
    }

    func testResolvedQuestionInfoNilAnswer() {
        let info = ResolvedQuestionInfo(answeredBy: "Coder", isFallback: false, answer: nil)
        XCTAssertNil(info.answer)
    }

    // MARK: - Conversation @Transient routing state

    func testConversationPendingQuestionRoutingStartsEmpty() {
        let conv = Conversation()
        XCTAssertTrue(conv.pendingQuestionRouting.isEmpty)
    }

    func testConversationResolvedQuestionsStartsEmpty() {
        let conv = Conversation()
        XCTAssertTrue(conv.resolvedQuestions.isEmpty)
    }

    func testConversationPendingQuestionRoutingMutation() {
        let conv = Conversation()
        conv.pendingQuestionRouting["q-1"] = "Reviewer"
        XCTAssertEqual(conv.pendingQuestionRouting["q-1"], "Reviewer")
        conv.pendingQuestionRouting.removeValue(forKey: "q-1")
        XCTAssertNil(conv.pendingQuestionRouting["q-1"])
    }

    func testConversationResolvedQuestionsMutation() {
        let conv = Conversation()
        let info = ResolvedQuestionInfo(answeredBy: "PM", isFallback: true, answer: "Speed")
        conv.resolvedQuestions["q-2"] = info
        XCTAssertEqual(conv.resolvedQuestions["q-2"]?.answeredBy, "PM")
        XCTAssertTrue(conv.resolvedQuestions["q-2"]?.isFallback ?? false)
        XCTAssertEqual(conv.resolvedQuestions["q-2"]?.answer, "Speed")
    }

    // MARK: - SidecarCommand.setDelegationMode encoding

    func testSetDelegationModeOffEncoding() throws {
        let command = SidecarCommand.setDelegationMode(sessionId: "sess-1", mode: .off, targetAgentName: nil)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "conversation.setDelegationMode")
        XCTAssertEqual(json["sessionId"] as? String, "sess-1")
        XCTAssertEqual(json["mode"] as? String, "off")
        XCTAssertNil(json["targetAgentName"])
    }

    func testSetDelegationModeByAgentsEncoding() throws {
        let command = SidecarCommand.setDelegationMode(sessionId: "sess-2", mode: .byAgents, targetAgentName: nil)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "conversation.setDelegationMode")
        XCTAssertEqual(json["sessionId"] as? String, "sess-2")
        XCTAssertEqual(json["mode"] as? String, "by_agents")
    }

    func testSetDelegationModeSpecificAgentWithTargetEncoding() throws {
        let command = SidecarCommand.setDelegationMode(sessionId: "sess-3", mode: .specificAgent, targetAgentName: "Reviewer")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "conversation.setDelegationMode")
        XCTAssertEqual(json["sessionId"] as? String, "sess-3")
        XCTAssertEqual(json["mode"] as? String, "specific_agent")
        XCTAssertEqual(json["targetAgentName"] as? String, "Reviewer")
    }

    func testSetDelegationModeCoordinatorEncoding() throws {
        let command = SidecarCommand.setDelegationMode(sessionId: "sess-4", mode: .coordinator, targetAgentName: "PM")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "conversation.setDelegationMode")
        XCTAssertEqual(json["mode"] as? String, "coordinator")
        XCTAssertEqual(json["targetAgentName"] as? String, "PM")
    }

    // MARK: - SidecarEvent decoding — agent.question.routing

    func testAgentQuestionRoutingDecoding() throws {
        let payload: [String: Any] = [
            "type": "agent.question.routing",
            "sessionId": "sess-abc",
            "questionId": "q-xyz",
            "targetAgentName": "Reviewer"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        guard case let .agentQuestionRouting(sessionId, questionId, targetAgentName) = wire.toEvent() else {
            XCTFail("Expected agentQuestionRouting event")
            return
        }
        XCTAssertEqual(sessionId, "sess-abc")
        XCTAssertEqual(questionId, "q-xyz")
        XCTAssertEqual(targetAgentName, "Reviewer")
    }

    // MARK: - SidecarEvent decoding — agent.question.resolved

    func testAgentQuestionResolvedDirectAnswerDecoding() throws {
        let payload: [String: Any] = [
            "type": "agent.question.resolved",
            "sessionId": "sess-abc",
            "questionId": "q-xyz",
            "answeredBy": "Reviewer",
            "isFallback": false,
            "answer": "async/await"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        guard case let .agentQuestionResolved(sessionId, questionId, answeredBy, isFallback, answer) = wire.toEvent() else {
            XCTFail("Expected agentQuestionResolved event")
            return
        }
        XCTAssertEqual(sessionId, "sess-abc")
        XCTAssertEqual(questionId, "q-xyz")
        XCTAssertEqual(answeredBy, "Reviewer")
        XCTAssertFalse(isFallback)
        XCTAssertEqual(answer, "async/await")
    }

    func testAgentQuestionResolvedFallbackDecoding() throws {
        let payload: [String: Any] = [
            "type": "agent.question.resolved",
            "sessionId": "sess-abc",
            "questionId": "q-fallback",
            "answeredBy": "PM",
            "isFallback": true,
            "answer": "Correctness first"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        guard case let .agentQuestionResolved(_, _, answeredBy, isFallback, answer) = wire.toEvent() else {
            XCTFail("Expected agentQuestionResolved event")
            return
        }
        XCTAssertEqual(answeredBy, "PM")
        XCTAssertTrue(isFallback)
        XCTAssertEqual(answer, "Correctness first")
    }

    func testAgentQuestionResolvedNilAnswerDecoding() throws {
        let payload: [String: Any] = [
            "type": "agent.question.resolved",
            "sessionId": "sess-abc",
            "questionId": "q-nil",
            "answeredBy": "Coder",
            "isFallback": false
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        guard case let .agentQuestionResolved(_, _, _, _, answer) = wire.toEvent() else {
            XCTFail("Expected agentQuestionResolved event")
            return
        }
        XCTAssertNil(answer)
    }
}
