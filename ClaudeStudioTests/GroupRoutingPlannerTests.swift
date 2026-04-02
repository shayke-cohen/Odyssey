import SwiftData
import XCTest
@testable import ClaudeStudio

final class GroupRoutingPlannerTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Agent.self,
            Session.self,
            Conversation.self,
            Participant.self,
            ConversationMessage.self,
            MessageAttachment.self,
            AgentGroup.self,
            configurations: config
        )
    }

    private func makeSession(agent: Agent, startedAt: TimeInterval) -> Session {
        let session = Session(agent: agent, workingDirectory: "/tmp")
        session.startedAt = Date(timeIntervalSince1970: startedAt)
        return session
    }

    func testMentionAwareUserWaveRoutesOnlyMentionedAgents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let coder = Agent(name: "Coder")
        let reviewer = Agent(name: "Reviewer")
        context.insert(coder)
        context.insert(reviewer)

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .mentionAware,
            sessions: [
                makeSession(agent: coder, startedAt: 1),
                makeSession(agent: reviewer, startedAt: 2)
            ],
            sourceGroup: nil,
            mentionedAgents: [reviewer],
            mentionedAll: false
        )

        XCTAssertEqual(plan.recipientAgentNames, ["Reviewer"])
        XCTAssertEqual(plan.deliveryReason, .directMention)
    }

    func testMentionAwareUserWaveRoutesToAllForAtAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let coder = Agent(name: "Coder")
        let reviewer = Agent(name: "Reviewer")
        context.insert(coder)
        context.insert(reviewer)

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .mentionAware,
            sessions: [
                makeSession(agent: coder, startedAt: 1),
                makeSession(agent: reviewer, startedAt: 2)
            ],
            sourceGroup: nil,
            mentionedAgents: [],
            mentionedAll: true
        )

        XCTAssertEqual(plan.recipientAgentNames, ["Coder", "Reviewer"])
        XCTAssertEqual(plan.deliveryReason, .broadcast)
    }

    func testMentionAwareUserWaveRoutesToCoordinatorWhenNoMention() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let coder = Agent(name: "Coder")
        let reviewer = Agent(name: "Reviewer")
        context.insert(coder)
        context.insert(reviewer)
        let group = AgentGroup(name: "Team", agentIds: [coder.id, reviewer.id])
        group.coordinatorAgentId = reviewer.id
        context.insert(group)

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .mentionAware,
            sessions: [
                makeSession(agent: coder, startedAt: 1),
                makeSession(agent: reviewer, startedAt: 2)
            ],
            sourceGroup: group,
            mentionedAgents: [],
            mentionedAll: false
        )

        XCTAssertEqual(plan.recipientAgentNames, ["Reviewer"])
        XCTAssertEqual(plan.deliveryReason, .coordinatorLead)
        XCTAssertEqual(plan.coordinatorAgentName, "Reviewer")
    }

    func testMentionAwareUserWaveFallsBackToAllWithoutCoordinator() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let coder = Agent(name: "Coder")
        let reviewer = Agent(name: "Reviewer")
        context.insert(coder)
        context.insert(reviewer)

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .mentionAware,
            sessions: [
                makeSession(agent: coder, startedAt: 1),
                makeSession(agent: reviewer, startedAt: 2)
            ],
            sourceGroup: nil,
            mentionedAgents: [],
            mentionedAll: false
        )

        XCTAssertEqual(plan.recipientAgentNames, ["Coder", "Reviewer"])
        XCTAssertEqual(plan.deliveryReason, .implicitFallback)
    }

    func testBroadUserWavePreservesSendToAllBehavior() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let coder = Agent(name: "Coder")
        let reviewer = Agent(name: "Reviewer")
        context.insert(coder)
        context.insert(reviewer)

        let plan = GroupRoutingPlanner.planUserWave(
            routingMode: .broad,
            sessions: [
                makeSession(agent: coder, startedAt: 1),
                makeSession(agent: reviewer, startedAt: 2)
            ],
            sourceGroup: nil,
            mentionedAgents: [coder],
            mentionedAll: false
        )

        XCTAssertEqual(plan.recipientAgentNames, ["Coder", "Reviewer"])
        XCTAssertEqual(plan.deliveryReason, .directMention)
    }

    func testAutonomousUserWaveAlwaysRoutesToCoordinator() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let coder = Agent(name: "Coder")
        let reviewer = Agent(name: "Reviewer")
        context.insert(coder)
        context.insert(reviewer)
        let group = AgentGroup(name: "Team", agentIds: [coder.id, reviewer.id])
        group.coordinatorAgentId = reviewer.id
        group.autonomousCapable = true
        context.insert(group)

        let plan = GroupRoutingPlanner.planUserWave(
            executionMode: .autonomous,
            routingMode: .mentionAware,
            sessions: [
                makeSession(agent: coder, startedAt: 1),
                makeSession(agent: reviewer, startedAt: 2)
            ],
            sourceGroup: group,
            mentionedAgents: [coder],
            mentionedAll: false
        )

        XCTAssertEqual(plan.recipientAgentNames, ["Reviewer"])
        XCTAssertEqual(plan.deliveryReason, .coordinatorLead)
        XCTAssertEqual(plan.coordinatorAgentName, "Reviewer")
    }

    func testWorkerUserWaveFallsBackToFirstSessionWithoutCoordinator() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let coder = Agent(name: "Coder")
        let reviewer = Agent(name: "Reviewer")
        context.insert(coder)
        context.insert(reviewer)

        let plan = GroupRoutingPlanner.planUserWave(
            executionMode: .worker,
            routingMode: .mentionAware,
            sessions: [
                makeSession(agent: coder, startedAt: 1),
                makeSession(agent: reviewer, startedAt: 2)
            ],
            sourceGroup: nil,
            mentionedAgents: [reviewer],
            mentionedAll: false
        )

        XCTAssertEqual(plan.recipientAgentNames, ["Coder"])
        XCTAssertEqual(plan.deliveryReason, .coordinatorLead)
        XCTAssertEqual(plan.coordinatorAgentName, "Coder")
    }

    func testMentionAwarePeerWaveRequiresExplicitMention() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let coder = Agent(name: "Coder")
        let reviewer = Agent(name: "Reviewer")
        context.insert(coder)
        context.insert(reviewer)

        let plan = GroupRoutingPlanner.planPeerWave(
            routingMode: .mentionAware,
            triggerText: "I pushed a draft",
            otherSessions: [
                makeSession(agent: coder, startedAt: 1),
                makeSession(agent: reviewer, startedAt: 2)
            ]
        )

        XCTAssertNil(plan)
    }

    func testBroadPeerWaveKeepsGenericFanout() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let coder = Agent(name: "Coder")
        let reviewer = Agent(name: "Reviewer")
        context.insert(coder)
        context.insert(reviewer)

        let plan = try XCTUnwrap(GroupRoutingPlanner.planPeerWave(
            routingMode: .broad,
            triggerText: "I pushed a draft",
            otherSessions: [
                makeSession(agent: coder, startedAt: 1),
                makeSession(agent: reviewer, startedAt: 2)
            ]
        ))

        XCTAssertEqual(plan.candidateSessionIds.count, 2)
        XCTAssertEqual(Set(plan.deliveryReasons.values), Set([.generic]))
    }
}
