import XCTest
import SwiftData
@testable import Odyssey

@MainActor
final class GroupSummaryTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            AgentGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testSummaryWithTwoAgents() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let coder = Agent(name: "Coder", icon: "chevron.left.forwardslash.chevron.right", color: "blue")
        let reviewer = Agent(name: "Reviewer", icon: "eye", color: "green")
        ctx.insert(coder)
        ctx.insert(reviewer)

        let s1 = Session(agent: coder, workingDirectory: "/tmp")
        let s2 = Session(agent: reviewer, workingDirectory: "/tmp")
        ctx.insert(s1)
        ctx.insert(s2)

        let convo = Conversation(topic: "Test")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants = (convo.participants ?? []) + [user]

        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: "Coder")
        p1.conversation = convo
        convo.participants = (convo.participants ?? []) + [p1]

        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: "Reviewer")
        p2.conversation = convo
        convo.participants = (convo.participants ?? []) + [p2]

        // Coder messages
        let m1 = ConversationMessage(senderParticipantId: p1.id, text: "I implemented the feature.", type: .chat, conversation: convo)
        let m2 = ConversationMessage(senderParticipantId: p1.id, text: "Fixed the bug.", type: .chat, conversation: convo)
        let m3 = ConversationMessage(senderParticipantId: p1.id, text: "", type: .toolCall, conversation: convo)
        m3.toolName = "Write"

        // Reviewer messages
        let m4 = ConversationMessage(senderParticipantId: p2.id, text: "LGTM, ship it.", type: .chat, conversation: convo)

        convo.messages = [m1, m2, m3, m4]
        ctx.insert(convo)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(m1)
        ctx.insert(m2)
        ctx.insert(m3)
        ctx.insert(m4)

        let summary = GroupSummaryBuilder.buildSummary(conversation: convo)

        XCTAssertEqual(summary.contributions.count, 2)
        XCTAssertEqual(summary.totalMessages, 3) // 2 coder + 1 reviewer chat messages
        XCTAssertEqual(summary.totalToolCalls, 1)

        let coderContrib = summary.contributions.first { $0.agentName == "Coder" }
        XCTAssertNotNil(coderContrib)
        XCTAssertEqual(coderContrib?.messageCount, 2)
        XCTAssertEqual(coderContrib?.toolCallCount, 1)

        let reviewerContrib = summary.contributions.first { $0.agentName == "Reviewer" }
        XCTAssertNotNil(reviewerContrib)
        XCTAssertEqual(reviewerContrib?.messageCount, 1)
        XCTAssertEqual(reviewerContrib?.toolCallCount, 0)
    }

    func testSummaryEmptyConversation() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let convo = Conversation(topic: "Empty")
        ctx.insert(convo)

        let summary = GroupSummaryBuilder.buildSummary(conversation: convo)

        XCTAssertEqual(summary.contributions.count, 0)
        XCTAssertEqual(summary.totalMessages, 0)
        XCTAssertEqual(summary.totalToolCalls, 0)
        XCTAssertEqual(summary.duration, 0)
    }

    func testSummaryKeyActionsLimitedToThree() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let agent = Agent(name: "Talker")
        ctx.insert(agent)
        let session = Session(agent: agent, workingDirectory: "/tmp")
        ctx.insert(session)

        let convo = Conversation(topic: "Chatty")
        session.conversations = [convo]
        convo.sessions = [session]

        let participant = Participant(type: .agentSession(sessionId: session.id), displayName: "Talker")
        participant.conversation = convo
        convo.participants = (convo.participants ?? []) + [participant]

        for i in 1...5 {
            let msg = ConversationMessage(senderParticipantId: participant.id, text: "Message \(i)", type: .chat, conversation: convo)
            convo.messages = (convo.messages ?? []) + [msg]
            ctx.insert(msg)
        }

        ctx.insert(convo)
        ctx.insert(participant)

        let summary = GroupSummaryBuilder.buildSummary(conversation: convo)
        let contrib = summary.contributions.first
        XCTAssertNotNil(contrib)
        XCTAssertEqual(contrib?.keyActions.count, 3) // suffix(3)
        XCTAssertEqual(contrib?.messageCount, 5)
    }

    func testFormatForStorage() throws {
        let summary = GroupSummaryBuilder.GroupSummary(
            contributions: [
                GroupSummaryBuilder.AgentContribution(
                    agentName: "Coder",
                    agentIcon: "cpu",
                    agentColor: "blue",
                    messageCount: 5,
                    toolCallCount: 3,
                    keyActions: ["Wrote login.swift", "Fixed auth bug"]
                )
            ],
            totalMessages: 5,
            totalToolCalls: 3,
            duration: 180
        )

        let text = GroupSummaryBuilder.formatForStorage(summary)
        XCTAssertTrue(text.contains("Group Activity Summary"))
        XCTAssertTrue(text.contains("3m"))
        XCTAssertTrue(text.contains("Coder: 5 messages, 3 tool calls"))
        XCTAssertTrue(text.contains("Wrote login.swift"))
    }
}
