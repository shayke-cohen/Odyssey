// OdysseyiOSTests/iOSAppStateExpandedTests.swift
import XCTest
@testable import OdysseyiOS
import OdysseyCore

/// Additional coverage for iOSAppState event handling paths
/// and streaming buffer edge cases not covered by iOSAppStateTests.
@MainActor
final class iOSAppStateExpandedTests: XCTestCase {

    func testStreamingBuffer_multipleSessions_independent() {
        let state = iOSAppState()
        state.handleEvent(.streamToken(sessionId: "a", text: "hello-a"))
        state.handleEvent(.streamToken(sessionId: "b", text: "hello-b"))
        XCTAssertEqual(state.streamingBuffers["a"], "hello-a")
        XCTAssertEqual(state.streamingBuffers["b"], "hello-b")
    }

    func testStreamingBuffer_emptyTokenAppendsNothingNew() {
        let state = iOSAppState()
        state.handleEvent(.streamToken(sessionId: "x", text: "Hi"))
        state.handleEvent(.streamToken(sessionId: "x", text: ""))
        XCTAssertEqual(state.streamingBuffers["x"], "Hi")
    }

    func testStreamingBuffer_clearOnResult_doesNotAffectOtherSession() {
        let state = iOSAppState()
        state.handleEvent(.streamToken(sessionId: "a", text: "A"))
        state.handleEvent(.streamToken(sessionId: "b", text: "B"))
        state.handleEvent(.sessionResult(sessionId: "a", result: "done",
                                         cost: 0, tokenCount: 0, toolCallCount: 0))
        XCTAssertNil(state.streamingBuffers["a"])
        XCTAssertEqual(state.streamingBuffers["b"], "B")
    }

    func testInitialCollectionsEmpty() {
        let state = iOSAppState()
        XCTAssertTrue(state.conversations.isEmpty)
        XCTAssertTrue(state.projects.isEmpty)
        XCTAssertTrue(state.streamingBuffers.isEmpty)
    }

    func testDisconnectedEvent_setsStatus() {
        let state = iOSAppState()
        state.handleEvent(.disconnected)
        XCTAssertEqual(state.connectionStatus, .disconnected)
    }

    func testUnhandledEvent_doesNotCrash() {
        // sessionError + sessionForked hit the `default: break` arm — must not crash.
        let state = iOSAppState()
        state.handleEvent(.sessionError(sessionId: "x", error: "boom"))
        state.handleEvent(.sessionForked(parentSessionId: "p", childSessionId: "c"))
        XCTAssertEqual(state.connectionStatus, .disconnected)
    }
}
