import SwiftData
import XCTest
@testable import Odyssey

/// Tests for Conversation deletion cascade behavior.
///
/// **Decision (2026-04-26):** Conversation owns its `messages` and `participants`
/// (`.cascade`), but `sessions` use `.nullify` because the schema permits N:M
/// (a Session can belong to multiple Conversations via fork lineage) and Sessions
/// hold provider state that must outlive any one thread.
@MainActor
final class ConversationCascadeTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self,
            ConversationMessage.self, MessageAttachment.self,
            Participant.self, Skill.self, Connection.self, MCPServer.self,
            PermissionSet.self, BlackboardEntry.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    func testDeletingConversation_cascadeDeletesMessages() throws {
        let convo = Conversation(topic: "Test")
        context.insert(convo)

        for i in 0..<5 {
            let msg = ConversationMessage(text: "msg \(i)", conversation: convo)
            context.insert(msg)
        }
        try context.save()

        let beforeFetch = FetchDescriptor<ConversationMessage>()
        XCTAssertEqual(try context.fetch(beforeFetch).count, 5)

        context.delete(convo)
        try context.save()

        let after = try context.fetch(beforeFetch)
        XCTAssertEqual(after.count, 0,
                       "Deleting a Conversation should cascade-delete its messages, not orphan them")
    }

    func testDeletingConversation_cascadeDeletesParticipants() throws {
        let convo = Conversation(topic: "Test")
        context.insert(convo)

        let p1 = Participant(type: .user, displayName: "Alice")
        let p2 = Participant(type: .user, displayName: "Bob")
        p1.conversation = convo
        p2.conversation = convo
        context.insert(p1)
        context.insert(p2)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Participant>()).count, 2)

        context.delete(convo)
        try context.save()

        let after = try context.fetch(FetchDescriptor<Participant>())
        XCTAssertEqual(after.count, 0,
                       "Deleting a Conversation should cascade-delete its participants")
    }

    func testDeletingConversation_cascadeDeletesMessageAttachments() throws {
        let convo = Conversation(topic: "Test")
        context.insert(convo)

        let msg = ConversationMessage(text: "with attachment", conversation: convo)
        context.insert(msg)
        let attachment = MessageAttachment(
            mediaType: "image/png", fileName: "shot.png", fileSize: 100, message: msg
        )
        context.insert(attachment)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<MessageAttachment>()).count, 1)

        context.delete(convo)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<MessageAttachment>()).count, 0,
                       "Cascading message deletes should also cascade their attachments — otherwise attachments orphan")
    }

    func testDeletingConversation_doesNotDeleteSessions() throws {
        // Sessions remain (.nullify) because they may belong to other conversations
        // via fork lineage and they hold provider state.
        let convo = Conversation(topic: "Test")
        let session = Session(agent: nil)
        session.conversations = [convo]
        context.insert(convo)
        context.insert(session)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Session>()).count, 1)

        context.delete(convo)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(remaining.count, 1,
                       "Deleting a Conversation must NOT delete its Sessions; only nullify the back-reference")
    }
}
