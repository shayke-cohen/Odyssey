import XCTest
@testable import Odyssey

final class ChatSessionWatchdogTests: XCTestCase {
    func testShouldNotTrackCompletedSessionWithPendingEventOnly() {
        XCTAssertFalse(
            ChatSessionWatchdog.shouldTrackSession(
                activity: .done,
                hasStreamingText: false,
                hasThinkingText: false
            )
        )
    }

    func testShouldTrackWaitingSessionWithoutVisibleText() {
        XCTAssertTrue(
            ChatSessionWatchdog.shouldTrackSession(
                activity: .waitingForResult,
                hasStreamingText: false,
                hasThinkingText: false
            )
        )
    }

    func testTimeoutRequiresNoVisibleOutputForActiveSession() {
        XCTAssertTrue(
            ChatSessionWatchdog.shouldTriggerNoResponseTimeout(
                elapsed: 301,
                hasVisibleOutput: false,
                activity: .waitingForResult
            )
        )

        XCTAssertFalse(
            ChatSessionWatchdog.shouldTriggerNoResponseTimeout(
                elapsed: 301,
                hasVisibleOutput: true,
                activity: .waitingForResult
            )
        )
    }

    func testTimeoutDoesNotFireForCompletedSession() {
        XCTAssertFalse(
            ChatSessionWatchdog.shouldTriggerNoResponseTimeout(
                elapsed: 301,
                hasVisibleOutput: false,
                activity: .done
            )
        )
    }
}
