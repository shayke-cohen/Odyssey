import XCTest
import SwiftData
@testable import ClaudPeer

@MainActor
final class GroupPromptBuilderTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testSingleSessionReturnsRawUserText() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let agent = Agent(name: "Solo")
        ctx.insert(agent)
        let convo = Conversation()
        let session = Session(agent: agent, workingDirectory: "/tmp")
        session.conversations = [convo]
        convo.sessions = [session]
        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        ctx.insert(convo)
        ctx.insert(session)
        ctx.insert(user)

        let text = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: session,
            latestUserMessageText: "Hello",
            participants: convo.participants
        )
        XCTAssertEqual(text, "Hello")
    }

    func testTwoSessionsIncludesGroupTranscript() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let m1 = ConversationMessage(senderParticipantId: user.id, text: "Hi room", type: .chat, conversation: convo)
        convo.messages.append(m1)

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(m1)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Next",
            participants: convo.participants
        )
        XCTAssertTrue(built.contains("Group thread"))
        XCTAssertTrue(built.contains("[You]:"))
        XCTAssertTrue(built.contains("Hi room"))
        XCTAssertTrue(built.contains("You are A1"))
        XCTAssertTrue(built.contains("Next"))
    }

    func testWatermarkOmitsEarlierMessages() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let oldMsg = ConversationMessage(senderParticipantId: user.id, text: "OLD", type: .chat, conversation: convo)
        let newMsg = ConversationMessage(senderParticipantId: user.id, text: "NEW", type: .chat, conversation: convo)
        convo.messages.append(contentsOf: [oldMsg, newMsg])
        s1.lastInjectedMessageId = oldMsg.id

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(oldMsg)
        ctx.insert(newMsg)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Latest",
            participants: convo.participants
        )
        XCTAssertFalse(built.contains("OLD"))
        XCTAssertTrue(built.contains("NEW"))
    }

    func testShouldUseGroupInjection() {
        XCTAssertFalse(GroupPromptBuilder.shouldUseGroupInjection(sessionCount: 1))
        XCTAssertFalse(GroupPromptBuilder.shouldUseGroupInjection(sessionCount: 0))
        XCTAssertTrue(GroupPromptBuilder.shouldUseGroupInjection(sessionCount: 2))
    }

    func testAdvanceWatermarkSetsLastInjectedMessageId() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let agent = Agent(name: "A")
        ctx.insert(agent)
        let session = Session(agent: agent, workingDirectory: "/tmp")
        let msg = ConversationMessage(text: "Reply", type: .chat)
        ctx.insert(session)
        ctx.insert(msg)

        XCTAssertNil(session.lastInjectedMessageId)
        GroupPromptBuilder.advanceWatermark(session: session, assistantMessage: msg)
        XCTAssertEqual(session.lastInjectedMessageId, msg.id)
    }

    func testNonChatMessagesExcludedFromTranscript() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let userChat = ConversationMessage(senderParticipantId: user.id, text: "visible", type: .chat, conversation: convo)
        let systemMsg = ConversationMessage(senderParticipantId: nil, text: "HIDDEN_SYSTEM", type: .system, conversation: convo)
        convo.messages.append(contentsOf: [userChat, systemMsg])

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(userChat)
        ctx.insert(systemMsg)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Next",
            participants: convo.participants
        )
        XCTAssertTrue(built.contains("visible"))
        XCTAssertFalse(built.contains("HIDDEN_SYSTEM"))
    }

    func testAgentMessageUsesParticipantDisplayName() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: "Display A1")
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let fromAgent = ConversationMessage(senderParticipantId: p1.id, text: "from agent line", type: .chat, conversation: convo)
        convo.messages.append(fromAgent)

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(fromAgent)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s2,
            latestUserMessageText: "Q",
            participants: convo.participants
        )
        XCTAssertTrue(built.contains("Display A1: from agent line"))
    }

    func testTranscriptTruncationPrefixWhenHuge() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let huge = String(repeating: "x", count: GroupPromptBuilder.maxInjectedCharacters + 5_000)
        let m1 = ConversationMessage(senderParticipantId: user.id, text: huge, type: .chat, conversation: convo)
        convo.messages.append(m1)

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(m1)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "short",
            participants: convo.participants
        )
        XCTAssertTrue(built.contains("… (truncated)"))
        XCTAssertTrue(built.count < huge.count + 500)
    }

    func testHighlightedMentionAgentNamesAppearInGroupPrompt() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)

        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]

        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)

        let m1 = ConversationMessage(senderParticipantId: user.id, text: "Hi", type: .chat, conversation: convo)
        convo.messages.append(m1)

        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)
        ctx.insert(m1)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Hey",
            participants: convo.participants,
            highlightedMentionAgentNames: ["A2"]
        )
        XCTAssertTrue(built.contains("specifically mentioned by name: A2"))
    }

    func testPeerNotifyPrompt() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let agent = Agent(name: "Beta")
        ctx.insert(agent)
        let session = Session(agent: agent, workingDirectory: "/tmp")
        ctx.insert(session)

        let prompt = GroupPromptBuilder.buildPeerNotifyPrompt(
            senderLabel: "Alpha",
            peerMessageText: "Hello group",
            recipientSession: session
        )
        XCTAssertTrue(prompt.contains("Group chat: peer message"))
        XCTAssertTrue(prompt.contains("Alpha: Hello group"))
        XCTAssertTrue(prompt.contains("You are Beta"))
    }

    func testSenderDisplayLabel() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let user = Participant(type: .user, displayName: "You")
        let convo = Conversation()
        user.conversation = convo
        convo.participants.append(user)
        ctx.insert(convo)
        ctx.insert(user)

        let msg = ConversationMessage(senderParticipantId: user.id, text: "x", type: .chat, conversation: convo)
        convo.messages.append(msg)
        ctx.insert(msg)

        XCTAssertEqual(
            GroupPromptBuilder.senderDisplayLabel(for: msg, participants: convo.participants),
            "[You]"
        )
    }

    func testGroupPeerFanOutContextBudgetAndDedup() {
        let t1 = UUID()
        let t2 = UUID()
        let msg = UUID()

        let ctx = GroupPeerFanOutContext(maxAdditionalSidecarTurns: 2)
        XCTAssertTrue(ctx.trySchedulePeerDelivery(targetSessionId: t1, triggerMessageId: msg))
        XCTAssertTrue(ctx.trySchedulePeerDelivery(targetSessionId: t2, triggerMessageId: msg))
        XCTAssertFalse(ctx.trySchedulePeerDelivery(targetSessionId: t1, triggerMessageId: msg))
        XCTAssertFalse(ctx.trySchedulePeerDelivery(targetSessionId: t2, triggerMessageId: UUID()))
    }

    /// Same target may receive another delivery when the trigger message id differs (new peer line).
    func testGroupPeerFanOutContextSameTargetNewTriggerUsesBudget() {
        let target = UUID()
        let ctx = GroupPeerFanOutContext(maxAdditionalSidecarTurns: 2)
        XCTAssertTrue(ctx.trySchedulePeerDelivery(targetSessionId: target, triggerMessageId: UUID()))
        XCTAssertTrue(ctx.trySchedulePeerDelivery(targetSessionId: target, triggerMessageId: UUID()))
        XCTAssertFalse(ctx.trySchedulePeerDelivery(targetSessionId: target, triggerMessageId: UUID()))
    }

    func testSenderDisplayLabelForAgentParticipant() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        ctx.insert(a1)
        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        s1.conversations = [convo]
        convo.sessions = [s1]
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: "Display A1")
        p1.conversation = convo
        convo.participants.append(p1)
        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(p1)

        let msg = ConversationMessage(senderParticipantId: p1.id, text: "hi", type: .chat, conversation: convo)
        convo.messages.append(msg)
        ctx.insert(msg)

        XCTAssertEqual(
            GroupPromptBuilder.senderDisplayLabel(for: msg, participants: convo.participants),
            "Display A1"
        )
    }

    func testPeerNotifyPromptEmptyMessageBody() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let agent = Agent(name: "R")
        ctx.insert(agent)
        let session = Session(agent: agent, workingDirectory: "/tmp")
        ctx.insert(session)

        let prompt = GroupPromptBuilder.buildPeerNotifyPrompt(
            senderLabel: "S",
            peerMessageText: "   \n",
            recipientSession: session
        )
        XCTAssertTrue(prompt.contains("S: (empty)"))
    }

    func testPeerNotifyPromptFreeformAssistantName() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let session = Session(agent: nil, workingDirectory: "/tmp")
        ctx.insert(session)

        let prompt = GroupPromptBuilder.buildPeerNotifyPrompt(
            senderLabel: "X",
            peerMessageText: "y",
            recipientSession: session
        )
        XCTAssertTrue(prompt.contains("You are Assistant"))
    }

    func testHighlightedMentionMultipleAgentNames() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let a1 = Agent(name: "A1")
        let a2 = Agent(name: "A2")
        ctx.insert(a1)
        ctx.insert(a2)
        let convo = Conversation()
        let s1 = Session(agent: a1, workingDirectory: "/tmp")
        let s2 = Session(agent: a2, workingDirectory: "/tmp")
        s1.conversations = [convo]
        s2.conversations = [convo]
        convo.sessions = [s1, s2]
        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let p1 = Participant(type: .agentSession(sessionId: s1.id), displayName: a1.name)
        p1.conversation = convo
        convo.participants.append(p1)
        let p2 = Participant(type: .agentSession(sessionId: s2.id), displayName: a2.name)
        p2.conversation = convo
        convo.participants.append(p2)
        ctx.insert(convo)
        ctx.insert(s1)
        ctx.insert(s2)
        ctx.insert(user)
        ctx.insert(p1)
        ctx.insert(p2)

        let built = GroupPromptBuilder.buildMessageText(
            conversation: convo,
            targetSession: s1,
            latestUserMessageText: "Hi",
            participants: convo.participants,
            highlightedMentionAgentNames: ["A2", "A1"]
        )
        XCTAssertTrue(built.contains("A2, A1"))
    }
}
