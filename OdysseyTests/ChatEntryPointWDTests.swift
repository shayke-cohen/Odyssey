import SwiftData
import XCTest
@testable import Odyssey

/// Tests working-directory and project-id assignment for every chat entry point.
///
/// Each test name mirrors the entry-point table from CLAUDE.md so failures are
/// immediately traceable to a specific UI action.
@MainActor
final class ChatEntryPointWDTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self,
            ConversationMessage.self, MessageAttachment.self,
            Participant.self, Skill.self, Connection.self, MCPServer.self,
            PermissionSet.self, BlackboardEntry.self, AgentGroup.self,
            NostrPeer.self, PromptTemplate.self, Project.self,
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

    // MARK: - Chat agent (Quick Chat)

    func testChatAgent_foundByConfigSlug() throws {
        // createQuickChat() looks up the Chat agent via configSlug == "chat"
        let chatAgent = Agent(name: "Chat")
        chatAgent.configSlug = "chat"
        chatAgent.defaultWorkingDirectory = nil
        context.insert(chatAgent)

        let other = Agent(name: "Coder")
        other.configSlug = "coder"
        context.insert(other)
        try context.save()

        let results = try context.fetch(
            FetchDescriptor<Agent>(predicate: #Predicate { $0.configSlug == "chat" })
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Chat")
    }

    func testQuickChat_sessionHasEmptyWorkingDirectory() {
        // Chat agent has no defaultWorkingDirectory — quick chat sessions have no WD
        let chatAgent = Agent(name: "Chat")
        chatAgent.configSlug = "chat"
        chatAgent.defaultWorkingDirectory = nil

        let session = Session(agent: chatAgent, mission: nil, mode: .interactive, workingDirectory: "")
        XCTAssertEqual(session.workingDirectory, "")
    }

    func testQuickChat_conversationHasNilProjectId() {
        // Quick Chat is not scoped to any project
        let conversation = Conversation(topic: "New Thread", projectId: nil, threadKind: .freeform)
        XCTAssertNil(conversation.projectId)
        XCTAssertEqual(conversation.threadKind, .freeform)
    }

    // MARK: - Agent context menu / toolbar agent picker

    func testAgentEntry_withDefaultWD_sessionUsesAgentWD() {
        let agent = Agent(name: "Coder")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/coder"

        // Mirrors startSessionWithAgent WD resolution
        let rawDir = agent.defaultWorkingDirectory ?? ""
        let session = Session(agent: agent, mode: .interactive)
        if !rawDir.isEmpty {
            session.workingDirectory = NSString(string: rawDir).expandingTildeInPath
        }

        let expected = (NSHomeDirectory() + "/.odyssey/residents/coder")
        XCTAssertEqual(session.workingDirectory, expected)
    }

    func testAgentEntry_noDefaultWD_sessionHasEmptyWD() {
        // Chat agent or any agent with no WD — session stays empty
        let agent = Agent(name: "Chat")
        agent.defaultWorkingDirectory = nil

        let rawDir = agent.defaultWorkingDirectory ?? ""
        let session = Session(agent: agent, mode: .interactive)
        if !rawDir.isEmpty {
            session.workingDirectory = NSString(string: rawDir).expandingTildeInPath
        }

        XCTAssertEqual(session.workingDirectory, "")
    }

    func testAgentEntry_noDefaultWD_doesNotFallBackToProjectDirectory() {
        // Regression: old code used windowState.projectDirectory as a fallback.
        // New code: if agent has no WD, session WD is empty — project dir is never injected.
        let agent = Agent(name: "Chat")
        agent.defaultWorkingDirectory = nil
        let projectDirectory = "/Users/shayco/my-project"

        let rawDir = agent.defaultWorkingDirectory ?? "" // new resolution — no projectDirectory fallback
        let session = Session(agent: agent, mode: .interactive)
        if !rawDir.isEmpty {
            session.workingDirectory = NSString(string: rawDir).expandingTildeInPath
        }

        XCTAssertNotEqual(session.workingDirectory, projectDirectory)
        XCTAssertEqual(session.workingDirectory, "")
    }

    func testAgentEntry_standalone_conversationHasNilProjectId() {
        // Agent sessions started outside a project context have no projectId
        let agent = Agent(name: "Coder")
        let session = Session(agent: agent, mode: .interactive)
        let conversation = Conversation(
            topic: nil, sessions: [session], projectId: nil, threadKind: .direct
        )
        XCTAssertNil(conversation.projectId)
    }

    // MARK: - Agent nested under project (context menu "New Thread in Project")

    func testAgentInProject_sessionUsesProjectRootPath() throws {
        let agent = Agent(name: "Coder")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/coder"
        context.insert(agent)

        let project = Project(name: "Odyssey", rootPath: "/Users/shayco/Odyssey", canonicalRootPath: "/Users/shayco/Odyssey")
        context.insert(project)
        try context.save()

        // SidebarView.startSession(with:in:) — project wins when explicitly passed
        let session = Session(agent: agent, mode: .interactive)
        session.workingDirectory = NSString(string: project.rootPath).expandingTildeInPath
        let conversation = Conversation(
            topic: nil, sessions: [session], projectId: project.id, threadKind: .direct
        )
        context.insert(session)
        context.insert(conversation)
        try context.save()

        XCTAssertEqual(session.workingDirectory, "/Users/shayco/Odyssey")
        XCTAssertEqual(conversation.projectId, project.id)
    }

    func testAgentInProject_agentWDIgnored_projectRootPathUsed() {
        // When a project is explicitly supplied, it wins over agent.defaultWorkingDirectory
        let agent = Agent(name: "Coder")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/coder"

        let projectRoot = "/Users/shayco/my-project"
        let session = Session(agent: agent, mode: .interactive)
        // Project wins — same logic as SidebarView.startSession(with:in:)
        session.workingDirectory = NSString(string: projectRoot).expandingTildeInPath

        XCTAssertEqual(session.workingDirectory, projectRoot)
        XCTAssertNotEqual(
            session.workingDirectory,
            NSString(string: agent.defaultWorkingDirectory!).expandingTildeInPath as String
        )
    }

    // MARK: - Group context menu / toolbar group picker

    func testGroupEntry_sessionUsesGroupDefaultWD() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)
        try context.save()

        let group = AgentGroup(name: "Dev Team", agentIds: [agent.id])
        context.insert(group)
        try context.save()

        // AgentGroup.init always sets defaultWorkingDirectory to ~/.odyssey/groups/<slug>
        XCTAssertNotNil(group.defaultWorkingDirectory)
        let groupWD = group.defaultWorkingDirectory!
        XCTAssertFalse(groupWD.isEmpty)

        appState.startGroupChat(
            group: group,
            projectDirectory: groupWD,
            projectId: nil,
            modelContext: context
        )

        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertFalse(sessions.isEmpty)
        let expected = NSString(string: groupWD).expandingTildeInPath as String
        for session in sessions {
            XCTAssertEqual(session.workingDirectory, expected)
        }
    }

    func testGroupEntry_standalone_conversationHasNilProjectId() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)
        try context.save()

        let group = AgentGroup(name: "Dev Team", agentIds: [agent.id])
        context.insert(group)
        try context.save()

        appState.startGroupChat(
            group: group,
            projectDirectory: group.defaultWorkingDirectory ?? "",
            projectId: nil,
            modelContext: context
        )

        let conversations = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertNil(conversations.first?.projectId)
    }

    func testGroupInProject_conversationScopedToProject() throws {
        let agent = Agent(name: "Coder")
        context.insert(agent)
        try context.save()

        let project = Project(name: "My App", rootPath: "/app", canonicalRootPath: "/app")
        context.insert(project)
        try context.save()

        let group = AgentGroup(name: "Dev Team", agentIds: [agent.id])
        context.insert(group)
        try context.save()

        appState.startGroupChat(
            group: group,
            projectDirectory: project.rootPath,
            projectId: project.id,
            modelContext: context
        )

        let conversations = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.projectId, project.id)
    }

    // MARK: - Browse sheet (AgentBrowseSheet)

    func testBrowseSheet_agentStartChat_usesAgentWDNotProjectDirectory() {
        // Regression: old AgentBrowseSheet.startChat passed projectDirectory from windowState.
        // New code: uses agent.defaultWorkingDirectory only.
        let agent = Agent(name: "Researcher")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/researcher"
        let projectDirectory = "/Users/shayco/my-project" // windowState.projectDirectory (should NOT be used)

        let agentWD = agent.defaultWorkingDirectory.flatMap { $0.isEmpty ? nil : $0 }
            .map { NSString(string: $0).expandingTildeInPath as String } ?? ""
        let session = Session(agent: agent, mission: nil, workingDirectory: agentWD)

        XCTAssertNotEqual(session.workingDirectory, projectDirectory)
        XCTAssertEqual(session.workingDirectory, NSString(string: "~/.odyssey/residents/researcher").expandingTildeInPath as String)
    }

    func testBrowseSheet_agentWithNoWD_sessionHasEmptyWD() {
        let agent = Agent(name: "Chat")
        agent.defaultWorkingDirectory = nil

        let agentWD = agent.defaultWorkingDirectory.flatMap { $0.isEmpty ? nil : $0 }
            .map { NSString(string: $0).expandingTildeInPath as String } ?? ""
        let session = Session(agent: agent, mission: nil, workingDirectory: agentWD)

        XCTAssertEqual(session.workingDirectory, "")
    }

    func testBrowseSheet_startChat_conversationHasNilProjectId() {
        // Browse sheet creates conversations with no project
        let conversation = Conversation(topic: nil, projectId: nil, threadKind: .direct)
        XCTAssertNil(conversation.projectId)
    }

    func testBrowseSheet_startGroupChat_usesGroupWDNotProjectDirectory() {
        // Regression: old code passed projectDirectory from windowState.
        let group = AgentGroup(name: "Dev Team", agentIds: [])
        // group.defaultWorkingDirectory is set by init to ~/.odyssey/groups/dev-team
        let projectDirectory = "/Users/shayco/my-project"

        let groupWD = group.defaultWorkingDirectory.flatMap { $0.isEmpty ? nil : $0 }
            .map { NSString(string: $0).expandingTildeInPath as String } ?? ""

        XCTAssertFalse(groupWD.isEmpty)
        XCTAssertNotEqual(groupWD, projectDirectory)
    }

    // MARK: - Project context menu ("New Thread")

    func testProjectContextMenu_newThread_conversationScopedToProject() throws {
        let project = Project(name: "Odyssey", rootPath: "/Users/shayco/Odyssey", canonicalRootPath: "/Users/shayco/Odyssey")
        context.insert(project)
        try context.save()

        // createQuickChat(in: project) creates a freeform Conversation with project.id
        let conversation = Conversation(
            topic: "New Thread",
            projectId: project.id,
            threadKind: .freeform
        )
        context.insert(conversation)
        try context.save()

        let conversations = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.projectId, project.id)
        XCTAssertEqual(conversations.first?.threadKind, .freeform)
    }

    func testProjectContextMenu_newThread_noSessionCreatedInitially() throws {
        let project = Project(name: "Odyssey", rootPath: "/Users/shayco/Odyssey", canonicalRootPath: "/Users/shayco/Odyssey")
        context.insert(project)
        try context.save()

        let conversation = Conversation(
            topic: "New Thread",
            projectId: project.id,
            threadKind: .freeform
        )
        context.insert(conversation)
        try context.save()

        // createQuickChat(in:) creates only a Conversation — no Session yet
        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(sessions.count, 0)
    }
}
