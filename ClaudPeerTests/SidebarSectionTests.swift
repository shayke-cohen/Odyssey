import XCTest
import SwiftData
@testable import ClaudPeer

/// Tests for sidebar section partitioning logic:
/// - Active: first 10 non-pinned, non-archived root conversations
/// - History: overflow beyond those 10
/// - Archived: all archived conversations
@MainActor
final class SidebarSectionTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Agent.self, Session.self, Conversation.self, ConversationMessage.self,
            MessageAttachment.self, Participant.self, Skill.self, MCPServer.self,
            PermissionSet.self, SharedWorkspace.self, BlackboardEntry.self, Peer.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Create a root conversation with a given startedAt offset (seconds ago).
    private func makeConversation(
        ctx: ModelContext,
        topic: String,
        isPinned: Bool = false,
        isArchived: Bool = false,
        status: ConversationStatus = .active,
        secondsAgo: TimeInterval = 0,
        parentId: UUID? = nil
    ) -> Conversation {
        let convo = Conversation(topic: topic)
        convo.isPinned = isPinned
        convo.isArchived = isArchived
        convo.status = status
        convo.startedAt = Date().addingTimeInterval(-secondsAgo)
        convo.parentConversationId = parentId
        ctx.insert(convo)
        return convo
    }

    // MARK: - Section filtering helpers (mirrors SidebarView logic)

    /// Root conversations sorted newest-first (same as @Query sort order).
    private func rootConversations(_ all: [Conversation]) -> [Conversation] {
        all.filter { $0.parentConversationId == nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func activeItems(_ roots: [Conversation]) -> [Conversation] {
        Array(roots.filter { !$0.isPinned && !$0.isArchived }.prefix(10))
    }

    private func historyItems(_ roots: [Conversation]) -> [Conversation] {
        Array(roots.filter { !$0.isPinned && !$0.isArchived }.dropFirst(10))
    }

    private func archivedItems(_ roots: [Conversation]) -> [Conversation] {
        roots.filter { $0.isArchived }
    }

    private func pinnedItems(_ roots: [Conversation]) -> [Conversation] {
        roots.filter { $0.isPinned && !$0.isArchived }
    }

    // MARK: - Tests

    func testFewConversations_allInActive_noneInHistory() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        for i in 0..<5 {
            convos.append(makeConversation(ctx: ctx, topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        XCTAssertEqual(activeItems(roots).count, 5)
        XCTAssertEqual(historyItems(roots).count, 0)
    }

    func testExactly10_allInActive_noneInHistory() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        for i in 0..<10 {
            convos.append(makeConversation(ctx: ctx, topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        XCTAssertEqual(activeItems(roots).count, 10)
        XCTAssertEqual(historyItems(roots).count, 0)
    }

    func testMoreThan10_overflowGoesToHistory() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        for i in 0..<15 {
            convos.append(makeConversation(ctx: ctx, topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        XCTAssertEqual(activeItems(roots).count, 10)
        XCTAssertEqual(historyItems(roots).count, 5)
    }

    func testPinnedConversations_excludedFromActiveAndHistory() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        for i in 0..<12 {
            let pinned = i < 2  // First 2 are pinned
            convos.append(makeConversation(ctx: ctx, topic: "Chat \(i)", isPinned: pinned, secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        XCTAssertEqual(pinnedItems(roots).count, 2)
        XCTAssertEqual(activeItems(roots).count, 10)  // 12 - 2 pinned = 10
        XCTAssertEqual(historyItems(roots).count, 0)
    }

    func testArchivedConversations_excludedFromActiveAndHistory() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        for i in 0..<14 {
            let archived = i >= 12  // Last 2 are archived
            convos.append(makeConversation(ctx: ctx, topic: "Chat \(i)", isArchived: archived, secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        XCTAssertEqual(archivedItems(roots).count, 2)
        XCTAssertEqual(activeItems(roots).count, 10)  // 14 - 2 archived = 12, first 10
        XCTAssertEqual(historyItems(roots).count, 2)   // remaining 2
    }

    func testChildConversations_notCountedAsRoot() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let parent = makeConversation(ctx: ctx, topic: "Parent", secondsAgo: 100)
        let child1 = makeConversation(ctx: ctx, topic: "Child 1", secondsAgo: 50, parentId: parent.id)
        let child2 = makeConversation(ctx: ctx, topic: "Child 2", secondsAgo: 30, parentId: parent.id)
        try ctx.save()

        let allConvos = [parent, child1, child2]
        let roots = rootConversations(allConvos)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(activeItems(roots).count, 1)
        XCTAssertEqual(historyItems(roots).count, 0)
    }

    func testMixedStatuses_activeAndClosed_bothInSections() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        for i in 0..<15 {
            let status: ConversationStatus = i % 2 == 0 ? .active : .closed
            convos.append(makeConversation(ctx: ctx, topic: "Chat \(i)", status: status, secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        let active = activeItems(roots)
        let history = historyItems(roots)

        // Both active and closed appear in the sections (no status filtering)
        XCTAssertEqual(active.count, 10)
        XCTAssertEqual(history.count, 5)

        // Verify both statuses are present in active
        let hasActive = active.contains { $0.status == .active }
        let hasClosed = active.contains { $0.status == .closed }
        XCTAssertTrue(hasActive)
        XCTAssertTrue(hasClosed)
    }

    func testActiveOrdering_newestFirst() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let old = makeConversation(ctx: ctx, topic: "Old", secondsAgo: 3600)
        let mid = makeConversation(ctx: ctx, topic: "Mid", secondsAgo: 1800)
        let recent = makeConversation(ctx: ctx, topic: "Recent", secondsAgo: 60)
        try ctx.save()

        let roots = rootConversations([old, mid, recent])
        let active = activeItems(roots)

        XCTAssertEqual(active[0].topic, "Recent")
        XCTAssertEqual(active[1].topic, "Mid")
        XCTAssertEqual(active[2].topic, "Old")
    }

    func testHistoryItems_areOldestConversations() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        for i in 0..<12 {
            convos.append(makeConversation(ctx: ctx, topic: "Chat \(i)", secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        let history = historyItems(roots)

        // History should contain the 2 oldest conversations
        XCTAssertEqual(history.count, 2)
        // Newest-first sorting: Chat 0 is most recent, Chat 11 is oldest
        // Active gets 0..9, History gets 10..11
        XCTAssertEqual(history[0].topic, "Chat 10")
        XCTAssertEqual(history[1].topic, "Chat 11")
    }

    func testAllArchived_noActiveOrHistory() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        for i in 0..<5 {
            convos.append(makeConversation(ctx: ctx, topic: "Chat \(i)", isArchived: true, secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        XCTAssertEqual(activeItems(roots).count, 0)
        XCTAssertEqual(historyItems(roots).count, 0)
        XCTAssertEqual(archivedItems(roots).count, 5)
    }

    func testAllPinned_noActiveOrHistory() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        for i in 0..<5 {
            convos.append(makeConversation(ctx: ctx, topic: "Chat \(i)", isPinned: true, secondsAgo: Double(i) * 60))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        XCTAssertEqual(pinnedItems(roots).count, 5)
        XCTAssertEqual(activeItems(roots).count, 0)
        XCTAssertEqual(historyItems(roots).count, 0)
    }

    func testPinnedArchivedConversation_appearsOnlyInArchived() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        // A conversation that is both pinned and archived should show in archived only
        let convo = makeConversation(ctx: ctx, topic: "Pinned+Archived", isPinned: true, isArchived: true)
        try ctx.save()

        let roots = rootConversations([convo])
        XCTAssertEqual(pinnedItems(roots).count, 0)  // pinned excludes archived
        XCTAssertEqual(activeItems(roots).count, 0)
        XCTAssertEqual(historyItems(roots).count, 0)
        XCTAssertEqual(archivedItems(roots).count, 1)
    }

    func testLargeDataset_correctPartitioning() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        var convos: [Conversation] = []
        // 3 pinned, 5 archived, 42 regular
        for i in 0..<3 {
            convos.append(makeConversation(ctx: ctx, topic: "Pinned \(i)", isPinned: true, secondsAgo: Double(i)))
        }
        for i in 0..<5 {
            convos.append(makeConversation(ctx: ctx, topic: "Archived \(i)", isArchived: true, secondsAgo: Double(i)))
        }
        for i in 0..<42 {
            convos.append(makeConversation(ctx: ctx, topic: "Regular \(i)", secondsAgo: Double(i)))
        }
        try ctx.save()

        let roots = rootConversations(convos)
        XCTAssertEqual(pinnedItems(roots).count, 3)
        XCTAssertEqual(activeItems(roots).count, 10)
        XCTAssertEqual(historyItems(roots).count, 32)  // 42 - 10
        XCTAssertEqual(archivedItems(roots).count, 5)

        // Total should account for everything
        let total = pinnedItems(roots).count + activeItems(roots).count + historyItems(roots).count + archivedItems(roots).count
        XCTAssertEqual(total, 50)
    }
}
