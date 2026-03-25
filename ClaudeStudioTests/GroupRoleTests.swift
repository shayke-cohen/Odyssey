import XCTest
import SwiftData
@testable import ClaudPeer

@MainActor
final class GroupRoleTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            AgentGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - GroupRole

    func testRoleDisplayNames() {
        XCTAssertEqual(GroupRole.participant.displayName, "Participant")
        XCTAssertEqual(GroupRole.coordinator.displayName, "Coordinator")
        XCTAssertEqual(GroupRole.scribe.displayName, "Scribe")
        XCTAssertEqual(GroupRole.observer.displayName, "Observer")
    }

    func testParticipantRoleHasEmptySnippet() {
        XCTAssertTrue(GroupRole.participant.systemPromptSnippet.isEmpty)
    }

    func testCoordinatorRoleHasSnippet() {
        let snippet = GroupRole.coordinator.systemPromptSnippet
        XCTAssertTrue(snippet.contains("coordinator"))
        XCTAssertTrue(snippet.contains("delegate"))
    }

    func testScribeRoleHasBlackboardInstruction() {
        let snippet = GroupRole.scribe.systemPromptSnippet
        XCTAssertTrue(snippet.contains("scribe"))
        XCTAssertTrue(snippet.contains("blackboard"))
    }

    func testObserverRoleHasRestriction() {
        let snippet = GroupRole.observer.systemPromptSnippet
        XCTAssertTrue(snippet.contains("observer"))
        XCTAssertTrue(snippet.contains("directly addressed"))
    }

    func testAllCasesCount() {
        XCTAssertEqual(GroupRole.allCases.count, 4)
    }

    // MARK: - AgentGroup.agentRoles JSON round-trip

    func testAgentRolesRoundTrip() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let group = AgentGroup(name: "Test Group")
        ctx.insert(group)

        let id1 = UUID()
        let id2 = UUID()
        group.agentRoles = [id1: "coordinator", id2: "observer"]

        // Read back
        let roles = group.agentRoles
        XCTAssertEqual(roles[id1], "coordinator")
        XCTAssertEqual(roles[id2], "observer")
    }

    func testAgentRolesEmptyByDefault() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let group = AgentGroup(name: "Empty")
        ctx.insert(group)

        XCTAssertTrue(group.agentRoles.isEmpty)
    }

    func testRoleForAgentId() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let group = AgentGroup(name: "Test")
        ctx.insert(group)

        let coordId = UUID()
        let observerId = UUID()
        let unknownId = UUID()
        group.agentRoles = [coordId: "coordinator", observerId: "observer"]

        XCTAssertEqual(group.roleFor(agentId: coordId), .coordinator)
        XCTAssertEqual(group.roleFor(agentId: observerId), .observer)
        XCTAssertEqual(group.roleFor(agentId: unknownId), .participant)
    }

    // MARK: - AgentGroup.workflow JSON round-trip

    func testWorkflowRoundTrip() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let group = AgentGroup(name: "Workflow Group")
        ctx.insert(group)

        let step1 = WorkflowStep(agentId: UUID(), instruction: "Research the topic", autoAdvance: true, stepLabel: "Research")
        let step2 = WorkflowStep(agentId: UUID(), instruction: "Write the code", condition: "approved", autoAdvance: true, stepLabel: "Code")
        let step3 = WorkflowStep(agentId: UUID(), instruction: "Review the code", autoAdvance: false, stepLabel: "Review")

        group.workflow = [step1, step2, step3]

        let loaded = group.workflow
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 3)
        XCTAssertEqual(loaded?[0].instruction, "Research the topic")
        XCTAssertEqual(loaded?[0].stepLabel, "Research")
        XCTAssertTrue(loaded?[0].autoAdvance ?? false)
        XCTAssertEqual(loaded?[1].condition, "approved")
        XCTAssertFalse(loaded?[2].autoAdvance ?? true)
    }

    func testWorkflowNilByDefault() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let group = AgentGroup(name: "No Workflow")
        ctx.insert(group)

        XCTAssertNil(group.workflow)
    }

    func testWorkflowSetToNil() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let group = AgentGroup(name: "Clear Workflow")
        ctx.insert(group)

        group.workflow = [WorkflowStep(agentId: UUID(), instruction: "test", autoAdvance: true)]
        XCTAssertNotNil(group.workflow)

        group.workflow = nil
        XCTAssertNil(group.workflow)
        XCTAssertNil(group.workflowJSON)
    }

    // MARK: - AgentGroup new fields defaults

    func testNewFieldsDefaults() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let group = AgentGroup(name: "Defaults")
        ctx.insert(group)

        XCTAssertTrue(group.autoReplyEnabled)
        XCTAssertFalse(group.autonomousCapable)
        XCTAssertNil(group.coordinatorAgentId)
        XCTAssertNil(group.agentRolesJSON)
        XCTAssertNil(group.workflowJSON)
    }
}
