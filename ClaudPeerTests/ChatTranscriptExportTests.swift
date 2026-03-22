import XCTest
import SwiftData
@testable import ClaudPeer

@MainActor
final class ChatTranscriptExportTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testMarkdownIncludesChatToolSystemAndAttachments() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let agent = Agent(name: "Helper")
        ctx.insert(agent)
        let convo = Conversation(topic: "My Topic")
        let session = Session(agent: agent, workingDirectory: "/tmp")
        session.conversations = [convo]
        convo.sessions = [session]
        let user = Participant(type: .user, displayName: "You")
        user.conversation = convo
        convo.participants.append(user)
        let agentPart = Participant(type: .agentSession(sessionId: session.id), displayName: agent.name)
        agentPart.conversation = convo
        convo.participants.append(agentPart)

        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2025
        comps.month = 6
        comps.day = 15
        comps.hour = 10
        comps.minute = 30
        comps.second = 0
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        let t1 = cal.date(from: comps)!
        comps.minute = 31
        let t2 = cal.date(from: comps)!

        let mUser = ConversationMessage(senderParticipantId: user.id, text: "Hello ```world```", type: .chat, conversation: convo)
        mUser.timestamp = t1
        let att = MessageAttachment(mediaType: "image/png", fileName: "shot.png", fileSize: 100, message: mUser)
        mUser.attachments.append(att)

        let mTool = ConversationMessage(senderParticipantId: agentPart.id, text: "", type: .toolCall, conversation: convo)
        mTool.timestamp = t2
        mTool.toolName = "read_file"
        mTool.toolInput = "{\"path\":\"/tmp/a.txt\"}"

        let mResult = ConversationMessage(senderParticipantId: agentPart.id, text: "", type: .toolResult, conversation: convo)
        mResult.timestamp = t2
        mResult.toolName = "read_file"
        mResult.toolOutput = "contents"

        let mSys = ConversationMessage(senderParticipantId: nil, text: "Connected.", type: .system, conversation: convo)
        mSys.timestamp = t2

        convo.messages = [mUser, mTool, mResult, mSys]
        ctx.insert(convo)
        ctx.insert(session)
        ctx.insert(user)
        ctx.insert(agentPart)
        ctx.insert(mUser)
        ctx.insert(mTool)
        ctx.insert(mResult)
        ctx.insert(mSys)
        ctx.insert(att)

        let ordered = convo.messages.sorted { $0.timestamp < $1.timestamp }
        let snap = ChatTranscriptExport.snapshot(
            conversation: convo,
            messages: ordered,
            participants: convo.participants,
            streamingAppendix: nil
        )
        let md = ChatTranscriptExport.markdown(snap)

        XCTAssertTrue(md.contains("# My Topic"))
        XCTAssertTrue(md.contains("## You ·"))
        XCTAssertTrue(md.contains("Attachments: shot.png"))
        XCTAssertTrue(md.contains("Hello ``\\`world``\\`"))
        XCTAssertTrue(md.contains("## Tool call · \(agent.name) ·"))
        XCTAssertTrue(md.contains("read_file"))
        XCTAssertTrue(md.contains("```json"))
        XCTAssertTrue(md.contains("## Tool result · \(agent.name) ·"))
        XCTAssertTrue(md.contains("## System · Unknown ·"))
        XCTAssertTrue(md.contains("Connected."))
    }

    func testHtmlEscapesAndStructure() {
        let row = ChatTranscriptSnapshot.Row(kind: .chat(
            sender: "A & B",
            timestampISO: "2025-01-01T00:00:00.000Z",
            text: "Line1\n\n<script>x</script>",
            thinking: nil,
            attachmentNames: []
        ))
        let snap = ChatTranscriptSnapshot(
            title: "T <itle>",
            startedAtISO: "2025-01-01T00:00:00.000Z",
            rows: [row],
            streamingAppendix: nil
        )
        let html = ChatTranscriptExport.html(snap)
        XCTAssertTrue(html.contains("<title>T &lt;itle&gt;</title>"))
        XCTAssertTrue(html.contains("A &amp; B"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>x</script>"))
    }

    func testStreamingAppendixInMarkdown() {
        let snap = ChatTranscriptSnapshot(
            title: "Live",
            startedAtISO: nil,
            rows: [],
            streamingAppendix: ChatTranscriptStreamingAppendix(text: "typing…", thinking: "hmm", displayName: "Claude")
        )
        let md = ChatTranscriptExport.markdown(snap)
        XCTAssertTrue(md.contains("In progress (not yet saved)"))
        XCTAssertTrue(md.contains("**Claude**"))
        XCTAssertTrue(md.contains("typing…"))
        XCTAssertTrue(md.contains("hmm"))
    }

    func testEmptyTranscriptPlaceholder() {
        let snap = ChatTranscriptSnapshot(title: "Empty", startedAtISO: nil, rows: [], streamingAppendix: nil)
        XCTAssertTrue(ChatTranscriptExport.markdown(snap).contains("No messages"))
        XCTAssertTrue(ChatTranscriptExport.html(snap).contains("No messages"))
    }
}
