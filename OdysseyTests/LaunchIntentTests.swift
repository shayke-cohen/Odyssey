import XCTest
@testable import Odyssey

final class LaunchIntentTests: XCTestCase {
    func testParsesScheduleCLIArguments() {
        let intent = LaunchIntent.fromArguments([
            "Odyssey",
            "--schedule", "2F0D95B8-1D90-49B4-9C7B-6DAB4F9386A8",
            "--occurrence", "2026-03-27T06:00:00Z"
        ])

        guard let intent else {
            return XCTFail("Expected launch intent")
        }

        switch intent.mode {
        case .schedule(let id):
            XCTAssertEqual(id.uuidString.uppercased(), "2F0D95B8-1D90-49B4-9C7B-6DAB4F9386A8")
        default:
            XCTFail("Expected schedule launch mode")
        }
        XCTAssertNotNil(intent.occurrence)
    }

    func testParsesScheduleURL() {
        let url = URL(string: "odyssey://schedule/2F0D95B8-1D90-49B4-9C7B-6DAB4F9386A8?occurrence=2026-03-27T06:00:00Z")!
        let intent = LaunchIntent.fromURL(url)

        guard let intent else {
            return XCTFail("Expected launch intent")
        }

        switch intent.mode {
        case .schedule(let id):
            XCTAssertEqual(id.uuidString.uppercased(), "2F0D95B8-1D90-49B4-9C7B-6DAB4F9386A8")
        default:
            XCTFail("Expected schedule launch mode")
        }
        XCTAssertNotNil(intent.occurrence)
    }

    func testParsesRoomJoinURL() {
        let url = URL(string: "odyssey://room/join?roomId=room-123&inviteId=invite-456&token=secret-789")!
        let intent = LaunchIntent.fromURL(url)

        guard let intent else {
            return XCTFail("Expected launch intent")
        }

        switch intent.mode {
        case .roomJoin(let payload):
            XCTAssertEqual(payload.roomId, "room-123")
            XCTAssertEqual(payload.inviteId, "invite-456")
            XCTAssertEqual(payload.inviteToken, "secret-789")
        default:
            XCTFail("Expected room join launch mode")
        }
    }

    func testParsesRoomJoinCLIArgumentsWithToken() {
        let intent = LaunchIntent.fromArguments([
            "Odyssey",
            "--room-join", "room-123:invite-456:secret-789"
        ])

        guard let intent else {
            return XCTFail("Expected launch intent")
        }

        switch intent.mode {
        case .roomJoin(let payload):
            XCTAssertEqual(payload.roomId, "room-123")
            XCTAssertEqual(payload.inviteId, "invite-456")
            XCTAssertEqual(payload.inviteToken, "secret-789")
        default:
            XCTFail("Expected room join launch mode")
        }
    }

    // MARK: - existingConversation / existingSession (testing affordance)

    func testParsesExistingConversationURL() {
        let convoId = "B07C0411-E1F1-4B6E-9276-2A1F4D3E5C6A"
        let url = URL(string: "odyssey://chat?conversation=\(convoId)&prompt=hello")!
        guard let intent = LaunchIntent.fromURL(url) else {
            return XCTFail("Expected launch intent")
        }
        switch intent.mode {
        case .existingConversation(let id):
            XCTAssertEqual(id.uuidString, convoId)
        default:
            XCTFail("Expected existingConversation launch mode, got \(intent.mode)")
        }
        XCTAssertEqual(intent.prompt, "hello")
    }

    func testParsesExistingSessionURL() {
        let sessionId = "1A2B3C4D-5E6F-7890-ABCD-EF1234567890"
        let url = URL(string: "odyssey://chat?session=\(sessionId)")!
        guard let intent = LaunchIntent.fromURL(url) else {
            return XCTFail("Expected launch intent")
        }
        switch intent.mode {
        case .existingSession(let id):
            XCTAssertEqual(id.uuidString, sessionId)
        default:
            XCTFail("Expected existingSession launch mode, got \(intent.mode)")
        }
    }

    func testExistingConversationCLIFlag() {
        let convoId = "B07C0411-E1F1-4B6E-9276-2A1F4D3E5C6A"
        let intent = LaunchIntent.fromArguments([
            "Odyssey", "--conversation", convoId, "--prompt", "STREAM:1000:12"
        ])
        guard let intent else {
            return XCTFail("Expected launch intent")
        }
        switch intent.mode {
        case .existingConversation(let id):
            XCTAssertEqual(id.uuidString, convoId)
        default:
            XCTFail("Expected existingConversation launch mode")
        }
        XCTAssertEqual(intent.prompt, "STREAM:1000:12")
    }

    func testExistingSessionCLIFlag() {
        let sessionId = "1A2B3C4D-5E6F-7890-ABCD-EF1234567890"
        let intent = LaunchIntent.fromArguments([
            "Odyssey", "--session", sessionId
        ])
        guard let intent else {
            return XCTFail("Expected launch intent")
        }
        switch intent.mode {
        case .existingSession(let id):
            XCTAssertEqual(id.uuidString, sessionId)
        default:
            XCTFail("Expected existingSession launch mode")
        }
    }

    func testInvalidConversationUUIDFallsThroughToChat() {
        // A malformed UUID in the query should not crash; `chat://` without
        // a valid conversation/session ID just opens a fresh chat.
        let url = URL(string: "odyssey://chat?conversation=not-a-uuid&prompt=hi")!
        guard let intent = LaunchIntent.fromURL(url) else {
            return XCTFail("Expected launch intent")
        }
        if case .chat = intent.mode {
            // expected
        } else {
            XCTFail("Expected fallback to .chat, got \(intent.mode)")
        }
    }
}
