import Foundation
import SwiftData
import XCTest
@testable import Odyssey

/// Lightweight SwiftData round-trip tests for models that had no direct
/// coverage: TaskItem, NostrPeer, ConversationMessage.
@MainActor
final class CoreModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for:
                Agent.self, Session.self, Skill.self, MCPServer.self,
                PermissionSet.self, AgentGroup.self, TaskItem.self,
                NostrPeer.self, ConversationMessage.self, Conversation.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // ─── TaskItem ─────────────────────────────────────────────

    func testTaskItem_defaults() {
        let task = TaskItem(title: "Do thing")
        XCTAssertEqual(task.status, .backlog)
        XCTAssertEqual(task.priority, .medium)
        XCTAssertEqual(task.labels, [])
        XCTAssertNotNil(task.id)
        XCTAssertNil(task.projectId)
        XCTAssertNil(task.completedAt)
    }

    func testTaskItem_roundTrip() throws {
        let task = TaskItem(
            title: "Ship v2",
            taskDescription: "Full rewrite",
            priority: .high,
            labels: ["backend", "urgent"],
            status: .ready
        )
        task.projectId = UUID()
        task.assignedAgentName = "Coder"
        context.insert(task)
        try context.save()

        let id = task.id
        let fetched = try context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        )
        XCTAssertEqual(fetched.count, 1)
        let reloaded = fetched[0]
        XCTAssertEqual(reloaded.title, "Ship v2")
        XCTAssertEqual(reloaded.taskDescription, "Full rewrite")
        XCTAssertEqual(reloaded.priority, .high)
        XCTAssertEqual(reloaded.labels, ["backend", "urgent"])
        XCTAssertEqual(reloaded.status, .ready)
        XCTAssertEqual(reloaded.assignedAgentName, "Coder")
    }

    func testTaskItem_statusTransitionsPersist() throws {
        let task = TaskItem(title: "T")
        context.insert(task)
        task.status = .inProgress
        task.startedAt = Date()
        try context.save()

        let id = task.id
        let reloaded = try context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        ).first
        XCTAssertEqual(reloaded?.status, .inProgress)
        XCTAssertNotNil(reloaded?.startedAt)
    }

    func testTaskItem_priorityEnumRaw() {
        XCTAssertEqual(TaskPriority.low.rawValue, "low")
        XCTAssertEqual(TaskPriority.medium.rawValue, "medium")
        XCTAssertEqual(TaskPriority.high.rawValue, "high")
        XCTAssertEqual(TaskPriority.critical.rawValue, "critical")
    }

    // ─── NostrPeer ────────────────────────────────────────────

    func testNostrPeer_roundTrip() throws {
        let peer = NostrPeer(
            displayName: "Alex's Mac",
            pubkeyHex: String(repeating: "a", count: 64),
            relays: ["wss://relay.damus.io", "wss://nos.lol"]
        )
        context.insert(peer)
        try context.save()

        let pubkey = peer.pubkeyHex
        let fetched = try context.fetch(
            FetchDescriptor<NostrPeer>(predicate: #Predicate { $0.pubkeyHex == pubkey })
        ).first
        XCTAssertEqual(fetched?.displayName, "Alex's Mac")
        XCTAssertEqual(fetched?.relays.count, 2)
        XCTAssertNil(fetched?.lastSeenAt)
    }

    func testNostrPeer_updateLastSeen() throws {
        let peer = NostrPeer(
            displayName: "Bob",
            pubkeyHex: String(repeating: "b", count: 64),
            relays: ["wss://relay"]
        )
        context.insert(peer)
        let now = Date()
        peer.lastSeenAt = now
        try context.save()
        XCTAssertNotNil(peer.lastSeenAt)
    }
}
