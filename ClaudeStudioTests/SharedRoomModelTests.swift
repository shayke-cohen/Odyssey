import XCTest
@testable import ClaudeStudio

final class SharedRoomModelTests: XCTestCase {
    func testRemoteUserParticipantRoundTripsTypeAndIdentity() {
        let participant = Participant(
            type: .remoteUser(userId: "user-1", participantId: "part-1", homeNodeId: "node-A"),
            displayName: "Alice"
        )

        if case .remoteUser(let userId, let participantId, let homeNodeId) = participant.type {
            XCTAssertEqual(userId, "user-1")
            XCTAssertEqual(participantId, "part-1")
            XCTAssertEqual(homeNodeId, "node-A")
        } else {
            XCTFail("Expected remote user participant")
        }
        XCTAssertFalse(participant.isLocalParticipant)
    }

    func testRemoteAgentParticipantRoundTripsTypeAndIdentity() {
        let participant = Participant(
            type: .remoteAgent(
                participantId: "agent-part-1",
                homeNodeId: "node-B",
                ownerUserId: "user-2",
                agentName: "Reviewer"
            ),
            displayName: "Reviewer"
        )

        if case .remoteAgent(let participantId, let homeNodeId, let ownerUserId, let agentName) = participant.type {
            XCTAssertEqual(participantId, "agent-part-1")
            XCTAssertEqual(homeNodeId, "node-B")
            XCTAssertEqual(ownerUserId, "user-2")
            XCTAssertEqual(agentName, "Reviewer")
        } else {
            XCTFail("Expected remote agent participant")
        }
        XCTAssertFalse(participant.isLocalParticipant)
    }

    func testConversationSharedRoomFlagUsesRoomId() {
        let conversation = Conversation(topic: "Shared Room")
        XCTAssertFalse(conversation.isSharedRoom)

        conversation.roomId = "room-abc"
        XCTAssertTrue(conversation.isSharedRoom)
    }

    func testConversationMessageStoresRoomEnvelopeFields() {
        let message = ConversationMessage(text: "Hello room", type: .chat)
        message.roomMessageId = "msg-1"
        message.roomRootMessageId = "root-1"
        message.roomParentMessageId = "parent-1"
        message.roomOriginNodeId = "node-1"
        message.roomOriginParticipantId = "participant-1"
        message.roomHostSequence = 42
        message.roomDeliveryMode = .cloudSync

        XCTAssertEqual(message.roomMessageId, "msg-1")
        XCTAssertEqual(message.roomRootMessageId, "root-1")
        XCTAssertEqual(message.roomParentMessageId, "parent-1")
        XCTAssertEqual(message.roomOriginNodeId, "node-1")
        XCTAssertEqual(message.roomOriginParticipantId, "participant-1")
        XCTAssertEqual(message.roomHostSequence, 42)
        XCTAssertEqual(message.roomDeliveryMode, .cloudSync)
    }
}
