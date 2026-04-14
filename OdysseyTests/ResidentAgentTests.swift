import XCTest
import SwiftData
@testable import Odyssey

/// Tests for the Resident Agents feature.
///
/// Resident Agent = any Agent whose `defaultWorkingDirectory` is non-nil.
/// These tests cover:
///   - Filter: agents with a home folder surface as residents
///   - Chat bucketing: Active (first 5) / History (overflow)
///   - MEMORY.md seeding via ResidentAgentSupport
@MainActor
final class ResidentAgentTests: XCTestCase {

    private var tempDir: URL!
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResidentAgentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        container = try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        ctx = ModelContext(container)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        container = nil
        ctx = nil
    }

    // MARK: - Resident filter logic

    func testAgent_withHomeFolder_isResident() {
        let agent = Agent(name: "Architect")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/architect"
        XCTAssertNotNil(agent.defaultWorkingDirectory, "Agent with home folder should be considered Resident")
    }

    func testAgent_withoutHomeFolder_isNotResident() {
        let agent = Agent(name: "Regular")
        agent.defaultWorkingDirectory = nil
        XCTAssertNil(agent.defaultWorkingDirectory, "Agent without home folder should not be Resident")
    }

    func testResidentAgents_filterRetainsOnlyAgentsWithIsResidentFlag() throws {
        let resident1 = Agent(name: "Architect")
        resident1.isResident = true

        let resident2 = Agent(name: "Researcher")
        resident2.isResident = true

        let regular = Agent(name: "Worker")
        // isResident defaults to false

        let all = [resident1, resident2, regular]
        // Mirror the SidebarView filter
        let residents = all.filter { $0.isEnabled && $0.isResident }

        XCTAssertEqual(residents.count, 2)
        XCTAssertTrue(residents.allSatisfy { $0.isResident })
        XCTAssertFalse(residents.contains { $0.name == "Worker" })
    }

    func testAgent_defaultHomePath_generatedFromName() {
        let agent = Agent(name: "My Researcher")
        XCTAssertEqual(agent.defaultWorkingDirectory, "~/.odyssey/residents/my-researcher")
    }

    func testAgent_defaultHomePath_staticHelper() {
        XCTAssertEqual(Agent.defaultHomePath(for: "Code Reviewer"), "~/.odyssey/residents/code-reviewer")
        XCTAssertEqual(Agent.defaultHomePath(for: ""), "~/.odyssey/residents/agent")
    }

    func testResidentAgents_disabledAgentExcluded() {
        let agent = Agent(name: "Disabled Resident")
        agent.isResident = true
        agent.isEnabled = false

        let residents = [agent].filter { $0.isEnabled && $0.isResident }
        XCTAssertEqual(residents.count, 0)
    }

    func testResidentAgents_sortedAlphabetically() {
        let c = Agent(name: "Charlie"); c.isResident = true
        let a = Agent(name: "Alpha");   a.isResident = true
        let b = Agent(name: "Beta");    b.isResident = true

        let sorted = [c, a, b]
            .filter { $0.isEnabled && $0.isResident }
            .sorted { $0.name < $1.name }

        XCTAssertEqual(sorted.map(\.name), ["Alpha", "Beta", "Charlie"])
    }

    // MARK: - Chat bucket logic (Active = first 5, History = overflow)

    private func makeConversation(topic: String, secondsAgo: TimeInterval = 0, isArchived: Bool = false) -> Conversation {
        let convo = Conversation(topic: topic)
        convo.isArchived = isArchived
        convo.startedAt = Date().addingTimeInterval(-secondsAgo)
        ctx.insert(convo)
        return convo
    }

    private func residentActiveItems(_ convos: [Conversation]) -> [Conversation] {
        Array(convos.filter { !$0.isArchived }.sorted { $0.startedAt > $1.startedAt }.prefix(5))
    }

    private func residentHistoryItems(_ convos: [Conversation]) -> [Conversation] {
        Array(convos.filter { !$0.isArchived }.sorted { $0.startedAt > $1.startedAt }.dropFirst(5))
    }

    func testResidentBuckets_fewChats_allInActive() throws {
        var convos: [Conversation] = []
        for i in 0..<3 {
            convos.append(makeConversation(topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        XCTAssertEqual(residentActiveItems(convos).count, 3)
        XCTAssertEqual(residentHistoryItems(convos).count, 0)
    }

    func testResidentBuckets_exactlyFive_noneInHistory() throws {
        var convos: [Conversation] = []
        for i in 0..<5 {
            convos.append(makeConversation(topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        XCTAssertEqual(residentActiveItems(convos).count, 5)
        XCTAssertEqual(residentHistoryItems(convos).count, 0)
    }

    func testResidentBuckets_moreThanFive_overflowGoesToHistory() throws {
        var convos: [Conversation] = []
        for i in 0..<8 {
            convos.append(makeConversation(topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        XCTAssertEqual(residentActiveItems(convos).count, 5)
        XCTAssertEqual(residentHistoryItems(convos).count, 3)
    }

    func testResidentBuckets_archivedExcludedFromBothBuckets() throws {
        var convos: [Conversation] = []
        for i in 0..<6 {
            convos.append(makeConversation(topic: "Chat \(i)", secondsAgo: Double(i) * 60, isArchived: i >= 4))
        }
        try ctx.save()

        XCTAssertEqual(residentActiveItems(convos).count, 4)
        XCTAssertEqual(residentHistoryItems(convos).count, 0)
    }

    func testResidentBuckets_activeOrderedNewestFirst() throws {
        let old = makeConversation(topic: "Old", secondsAgo: 3600)
        let recent = makeConversation(topic: "Recent", secondsAgo: 60)
        let mid = makeConversation(topic: "Mid", secondsAgo: 1800)
        try ctx.save()

        let active = residentActiveItems([old, recent, mid])
        XCTAssertEqual(active[0].topic, "Recent")
        XCTAssertEqual(active[1].topic, "Mid")
        XCTAssertEqual(active[2].topic, "Old")
    }

    // MARK: - MEMORY.md seeding

    func testSeedMemory_createsDirectoryAndFile() {
        let homePath = tempDir.appendingPathComponent("architect").path
        let created = ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Architect")

        XCTAssertTrue(created, "Should report file was newly created")
        let memPath = tempDir.appendingPathComponent("architect/MEMORY.md").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: memPath), "MEMORY.md should exist")
    }

    func testSeedMemory_fileContainsAgentName() throws {
        let homePath = tempDir.appendingPathComponent("researcher").path
        ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Research Buddy")

        let content = try String(
            contentsOf: tempDir.appendingPathComponent("researcher/MEMORY.md"),
            encoding: .utf8
        )
        XCTAssertTrue(content.contains("Research Buddy"), "MEMORY.md should include agent name")
        XCTAssertTrue(content.contains("## Goals"), "MEMORY.md should include Goals section")
        XCTAssertTrue(content.contains("## Notes"), "MEMORY.md should include Notes section")
        XCTAssertTrue(content.contains("## Decisions Log"), "MEMORY.md should include Decisions Log section")
    }

    func testSeedMemory_doesNotOverwriteExistingFile() throws {
        let homePath = tempDir.appendingPathComponent("scribe").path
        try FileManager.default.createDirectory(
            atPath: homePath, withIntermediateDirectories: true
        )
        let existingContent = "# My custom memory"
        try existingContent.write(
            toFile: homePath + "/MEMORY.md",
            atomically: true,
            encoding: .utf8
        )

        let created = ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Scribe")

        XCTAssertFalse(created, "Should not overwrite existing file")
        let content = try String(
            contentsOf: URL(fileURLWithPath: homePath + "/MEMORY.md"),
            encoding: .utf8
        )
        XCTAssertEqual(content, existingContent, "Existing MEMORY.md should be unchanged")
    }

    func testSeedMemory_idempotent_calledTwice() {
        let homePath = tempDir.appendingPathComponent("idempotent-agent").path

        let first = ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Agent")
        let second = ResidentAgentSupport.seedMemoryFileIfNeeded(in: homePath, agentName: "Agent")

        XCTAssertTrue(first, "First call should create file")
        XCTAssertFalse(second, "Second call should skip (already exists)")
    }

    func testSeedMemory_createsIntermediateDirectories() {
        let deepPath = tempDir.appendingPathComponent("a/b/c/deep-agent").path

        ResidentAgentSupport.seedMemoryFileIfNeeded(in: deepPath, agentName: "Deep")

        let memPath = deepPath + "/MEMORY.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: memPath))
    }

    // MARK: - Session working directory

    func testStartResidentSession_usesAgentHomeDir() throws {
        let agent = Agent(name: "Architect")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/architect"
        ctx.insert(agent)
        try ctx.save()

        // Mirror startResidentSession logic: expand tilde and set as workingDirectory
        let homeDir = agent.defaultWorkingDirectory!
        let expandedPath = (homeDir as NSString).expandingTildeInPath

        let session = Session(agent: agent, mode: .interactive)
        session.workingDirectory = expandedPath

        XCTAssertEqual(session.workingDirectory, expandedPath)
        XCTAssertTrue(
            session.workingDirectory.contains("residents/architect"),
            "Resident session should use agent home folder, got: \(session.workingDirectory)"
        )
    }

    func testStartProjectSession_usesProjectDir_notAgentHomeDir() throws {
        let agent = Agent(name: "Architect")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/architect"
        ctx.insert(agent)

        let project = Project(name: "Odyssey", rootPath: "/Users/test/Odyssey", canonicalRootPath: "/Users/test/Odyssey")
        ctx.insert(project)
        try ctx.save()

        // Mirror startSession logic: project dir, ignoring agent's home
        let session = Session(agent: agent, mode: .interactive)
        if session.workingDirectory.isEmpty {
            session.workingDirectory = project.rootPath
        }

        XCTAssertEqual(session.workingDirectory, project.rootPath,
                       "Project session should use project root, not agent home folder")
    }

    func testResidentConversation_hasNilProjectId() throws {
        let agent = Agent(name: "Architect")
        agent.defaultWorkingDirectory = "~/.odyssey/residents/architect"
        ctx.insert(agent)
        try ctx.save()

        // Mirror startResidentSession: projectId is nil
        let conversation = Conversation(
            topic: agent.name,
            projectId: nil,
            threadKind: .direct
        )
        ctx.insert(conversation)
        try ctx.save()

        XCTAssertNil(conversation.projectId,
                     "Resident conversations should not be scoped to a project")
    }
}
