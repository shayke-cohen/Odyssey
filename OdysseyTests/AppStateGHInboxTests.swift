import XCTest
import SwiftData
@testable import Odyssey

@MainActor
final class AppStateGHInboxTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!

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
        appState = AppState()
        appState.modelContext = context
    }

    override func tearDown() async throws {
        appState = nil
        container = nil
        context = nil
    }

    // MARK: - GH1: ghIssueRunNow creates a new session when none exists

    func testGH1_ghIssueRunNow_createsSessionWhenNone() throws {
        let agent = Agent(name: "Dev", systemPrompt: "dev")
        context.insert(agent)

        let conv = Conversation(topic: "GH #1: Fix bug", threadKind: .autonomous)
        conv.githubIssueNumber = 1
        conv.githubIssueRepo = "owner/repo"
        conv.githubIssueUrl = "https://github.com/owner/repo/issues/1"
        context.insert(conv)
        try context.save()

        appState.ghIssueRunNow(conv, agentOverride: agent)

        let sessions = (conv.sessions ?? [])
        XCTAssertEqual(sessions.count, 1, "Should have created one session")
        XCTAssertEqual(sessions.first?.agent?.name, "Dev")
        XCTAssertEqual(sessions.first?.mode, .autonomous)
    }

    // MARK: - GH2: ghIssueRunNow with override stores ghOverrideAgentId

    func testGH2_ghIssueRunNow_storesAgentOverride() throws {
        let agent = Agent(name: "Override Agent", systemPrompt: "")
        context.insert(agent)

        let conv = Conversation(topic: "GH #2: Feature", threadKind: .autonomous)
        conv.githubIssueNumber = 2
        conv.githubIssueRepo = "owner/repo"
        context.insert(conv)
        try context.save()

        appState.ghIssueRunNow(conv, agentOverride: agent)

        XCTAssertEqual(conv.ghOverrideAgentId, agent.id)
    }

    // MARK: - GH3: handleGHIssueClosed archives the conversation

    func testGH3_handleGHIssueClosed_archivesConversation() throws {
        let conv = Conversation(topic: "GH #5: Close me", threadKind: .autonomous)
        conv.githubIssueNumber = 5
        conv.githubIssueRepo = "owner/repo"
        conv.isArchived = false
        context.insert(conv)
        try context.save()

        appState.handleEventForTesting(.ghIssueClosed(repo: "owner/repo", number: 5))

        XCTAssertTrue(conv.isArchived, "Conversation should be archived after issue close")
    }

    // MARK: - GH4: handleGHIssueClosed does nothing for unknown issue

    func testGH4_handleGHIssueClosed_unknownIssue_doesNotCrash() {
        // Should not throw or crash when no matching conversation exists
        appState.handleEventForTesting(.ghIssueClosed(repo: "owner/repo", number: 9999))
        // Test passes if no crash
    }
}
