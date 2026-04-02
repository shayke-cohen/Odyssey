import XCTest
@testable import ClaudeStudio

@MainActor
final class WindowStateInspectorTests: XCTestCase {
    func testOpenInspectorSetsVisibilityAndSelectedTab() {
        let project = Project(
            name: "Repo",
            rootPath: "/tmp/repo",
            canonicalRootPath: "/tmp/repo"
        )
        let windowState = WindowState(project: project)
        windowState.inspectorVisible = false
        windowState.selectedInspectorTab = .info

        windowState.openInspector(tab: .blackboard)

        XCTAssertTrue(windowState.inspectorVisible)
        XCTAssertEqual(windowState.selectedInspectorTab, .blackboard)
    }

    func testOpenInspectorFileSelectsFilesTabAndStoresCanonicalRequest() {
        let project = Project(
            name: "Repo",
            rootPath: "/tmp/repo",
            canonicalRootPath: "/tmp/repo"
        )
        let windowState = WindowState(project: project)
        windowState.inspectorVisible = false
        windowState.selectedInspectorTab = .info

        let rawURL = URL(fileURLWithPath: "/tmp/repo/../repo/Sources/App.swift")
        windowState.openInspectorFile(at: rawURL)

        XCTAssertTrue(windowState.inspectorVisible)
        XCTAssertEqual(windowState.selectedInspectorTab, .files)
        XCTAssertEqual(
            windowState.inspectorFileSelectionRequest?.url.path,
            "/tmp/repo/Sources/App.swift"
        )
    }

    func testConsumeInspectorFileSelectionRequestClearsMatchingRequestOnly() throws {
        let project = Project(
            name: "Repo",
            rootPath: "/tmp/repo",
            canonicalRootPath: "/tmp/repo"
        )
        let windowState = WindowState(project: project)
        windowState.openInspectorFile(at: URL(fileURLWithPath: "/tmp/repo/README.md"))
        let request = try XCTUnwrap(windowState.inspectorFileSelectionRequest)

        windowState.consumeInspectorFileSelectionRequest(id: UUID())
        XCTAssertEqual(windowState.inspectorFileSelectionRequest?.id, request.id)

        windowState.consumeInspectorFileSelectionRequest(id: request.id)
        XCTAssertNil(windowState.inspectorFileSelectionRequest)
    }
}
