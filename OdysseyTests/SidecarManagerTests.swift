import XCTest
@testable import Odyssey

@MainActor
final class SidecarManagerTests: XCTestCase {
    func testStartPrefersFreshManagedLaunchBeforeConnecting() async throws {
        var events: [String] = []
        let manager = SidecarManager(
            hooks: .init(
                connectWebSocket: {
                    events.append("connect")
                },
                launchSidecar: {
                    events.append("launch")
                },
                terminateConflictingSidecars: {
                    events.append("terminate")
                },
                sleep: { _ in
                    events.append("sleep")
                }
            )
        )

        try await manager.start()

        XCTAssertEqual(events, ["terminate", "launch", "sleep", "connect"])
    }

    func testStartFallsBackToExistingListenerWhenFreshLaunchFails() async throws {
        enum ExpectedError: Error { case launchFailed }

        var events: [String] = []
        let manager = SidecarManager(
            hooks: .init(
                connectWebSocket: {
                    events.append("connect")
                },
                launchSidecar: {
                    events.append("launch")
                    throw ExpectedError.launchFailed
                },
                terminateConflictingSidecars: {
                    events.append("terminate")
                },
                sleep: { _ in
                    events.append("sleep")
                }
            )
        )

        try await manager.start()

        XCTAssertEqual(events, ["terminate", "launch", "connect"])
    }
}
