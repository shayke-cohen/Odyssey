import XCTest
import SwiftData
@testable import ClaudPeer

@MainActor
final class GroupAssemblerTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            AgentGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testAssembleForCodingTask() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let coder = Agent(name: "Coder", agentDescription: "Expert software engineer that writes and refactors code")
        let reviewer = Agent(name: "Reviewer", agentDescription: "Reviews code for quality and correctness")
        let tester = Agent(name: "Tester", agentDescription: "Validates and tests software")
        let writer = Agent(name: "Writer", agentDescription: "Writes documentation and content")
        ctx.insert(coder)
        ctx.insert(reviewer)
        ctx.insert(tester)
        ctx.insert(writer)

        let result = GroupAssembler.assembleGroup(
            task: "Implement a new login page and review the code",
            availableAgents: [coder, reviewer, tester, writer]
        )

        XCTAssertFalse(result.agentIds.isEmpty)
        XCTAssertTrue(result.agentIds.contains(coder.id), "Coder should be recommended for coding task")
        XCTAssertTrue(result.agentIds.contains(reviewer.id), "Reviewer should be recommended for review task")
        XCTAssertFalse(result.suggestedName.isEmpty)
        XCTAssertTrue(result.suggestedInstruction.contains("login"))
    }

    func testAssembleForResearchTask() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let researcher = Agent(name: "Researcher", agentDescription: "Researches topics and gathers insights")
        let analyst = Agent(name: "Analyst", agentDescription: "Analyzes data and provides metrics")
        let coder = Agent(name: "Coder", agentDescription: "Writes and implements code")
        ctx.insert(researcher)
        ctx.insert(analyst)
        ctx.insert(coder)

        let result = GroupAssembler.assembleGroup(
            task: "Research competitive analysis and analyze market data",
            availableAgents: [researcher, analyst, coder]
        )

        XCTAssertTrue(result.agentIds.contains(researcher.id))
        XCTAssertTrue(result.agentIds.contains(analyst.id))
    }

    func testAssembleReturnsAtLeastTwoAgents() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let a1 = Agent(name: "A1", agentDescription: "General agent")
        let a2 = Agent(name: "A2", agentDescription: "Another agent")
        let a3 = Agent(name: "A3", agentDescription: "Third agent")
        ctx.insert(a1)
        ctx.insert(a2)
        ctx.insert(a3)

        let result = GroupAssembler.assembleGroup(
            task: "Something completely unrelated to any agent",
            availableAgents: [a1, a2, a3]
        )

        XCTAssertGreaterThanOrEqual(result.agentIds.count, 2)
    }

    func testAssembleReasoningNotEmpty() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let agent = Agent(name: "Coder", agentDescription: "Writes code")
        let agent2 = Agent(name: "Tester", agentDescription: "Tests code")
        ctx.insert(agent)
        ctx.insert(agent2)

        let result = GroupAssembler.assembleGroup(
            task: "Build and test a feature",
            availableAgents: [agent, agent2]
        )

        XCTAssertFalse(result.reasoning.isEmpty)
    }

    func testAssembleSuggestedNameDerivedFromTask() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let agent = Agent(name: "A", agentDescription: "Agent")
        let agent2 = Agent(name: "B", agentDescription: "Agent")
        ctx.insert(agent)
        ctx.insert(agent2)

        let result = GroupAssembler.assembleGroup(
            task: "Deploy the application to production",
            availableAgents: [agent, agent2]
        )

        XCTAssertTrue(result.suggestedName.contains("Deploy"))
    }
}
