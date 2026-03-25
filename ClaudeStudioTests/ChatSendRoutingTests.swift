import XCTest
@testable import ClaudPeer

final class ChatSendRoutingTests: XCTestCase {

    func testParseSlashHelp() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/help"), .help)
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/?"), .help)
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("  /help  "), .help)
    }

    func testParseSlashTopic() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/topic My Title"), .topic("My Title"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/rename  Two  Words"), .topic("Two  Words"))
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/topic"), .topic(""))
    }

    func testParseSlashAgents() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/agents"), .agents)
    }

    func testDoubleSlashNotCommand() {
        XCTAssertNil(ChatSendRouting.parseSlashCommand("//not a command"))
    }

    func testMentionedAgentNames() {
        let names = ChatSendRouting.mentionedAgentNames(in: "Hi @Coder and @Reviewer please")
        XCTAssertEqual(names, ["Coder", "Reviewer"])
    }

    func testResolveMentionedAgents() {
        let a = Agent(name: "Coder")
        let b = Agent(name: "Reviewer")
        let (resolved, unknown) = ChatSendRouting.resolveMentionedAgents(
            names: ["coder", "Nobody"],
            agents: [a, b]
        )
        XCTAssertEqual(resolved.map(\.id), [a.id])
        XCTAssertEqual(unknown, ["Nobody"])
    }

    func testBareSlashIsNotACommand() {
        XCTAssertNil(ChatSendRouting.parseSlashCommand("/"))
        XCTAssertNil(ChatSendRouting.parseSlashCommand("   /   "))
    }

    func testSlashUsesFirstLineOnly() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/help\nignored"), .help)
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/topic Line1\nLine2"), .topic("Line1"))
    }

    func testUnknownSlashCommand() {
        XCTAssertEqual(ChatSendRouting.parseSlashCommand("/frobnicate"), .unknown("frobnicate"))
    }

    func testResolveMentionedAgentsDeduplicates() {
        let a = Agent(name: "Coder")
        let (resolved, unknown) = ChatSendRouting.resolveMentionedAgents(
            names: ["Coder", "coder", "CODER"],
            agents: [a]
        )
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.id, a.id)
        XCTAssertTrue(unknown.isEmpty)
    }

    func testResolveMentionedAgentsSkipsEmptyTokens() {
        let a = Agent(name: "A")
        let (resolved, unknown) = ChatSendRouting.resolveMentionedAgents(names: ["", "  ", "A"], agents: [a])
        XCTAssertEqual(resolved.map(\.id), [a.id])
        XCTAssertTrue(unknown.isEmpty)
    }

    func testMentionedAgentNamesPreservesOrder() {
        let names = ChatSendRouting.mentionedAgentNames(in: "@Z @A @M")
        XCTAssertEqual(names, ["Z", "A", "M"])
    }
}
