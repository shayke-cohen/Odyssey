import XCTest
@testable import ClaudeStudio

final class LocalFileReferenceSupportTests: XCTestCase {
    private var tempDirectory: URL!
    private var workspaceDirectory: URL!
    private var externalDirectory: URL!

    override func setUp() {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeStudioLocalFileTests-\(UUID().uuidString)", isDirectory: true)
        workspaceDirectory = tempDirectory.appendingPathComponent("workspace", isDirectory: true)
        externalDirectory = tempDirectory.appendingPathComponent("external", isDirectory: true)

        try? FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        workspaceDirectory = nil
        externalDirectory = nil
    }

    func testNormalizeFileURLCanonicalizesPath() throws {
        let fileURL = workspaceDirectory.appendingPathComponent("notes.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let normalized = LocalFileReferenceSupport.normalize(rawReference: fileURL.absoluteString)

        XCTAssertEqual(normalized?.path, fileURL.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testResolveAbsolutePathInsideWorkspaceReturnsWorkspaceFile() throws {
        let fileURL = workspaceDirectory.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "print(\"ok\")".write(to: fileURL, atomically: true, encoding: .utf8)

        let resolution = LocalFileReferenceSupport.resolve(
            rawReference: fileURL.path,
            workspaceRoot: workspaceDirectory.path
        )

        XCTAssertEqual(resolution, .workspaceFile(fileURL.standardizedFileURL.resolvingSymlinksInPath()))
    }

    func testResolveFileURLOutsideWorkspaceReturnsExternalFile() throws {
        let fileURL = externalDirectory.appendingPathComponent("guide.md")
        try "guide".write(to: fileURL, atomically: true, encoding: .utf8)

        let resolution = LocalFileReferenceSupport.resolve(
            rawReference: fileURL.absoluteString,
            workspaceRoot: workspaceDirectory.path
        )

        XCTAssertEqual(resolution, .externalFile(fileURL.standardizedFileURL.resolvingSymlinksInPath()))
    }

    func testResolveSymlinkUsesCanonicalTarget() throws {
        let targetURL = workspaceDirectory.appendingPathComponent("README.md")
        try "readme".write(to: targetURL, atomically: true, encoding: .utf8)
        let symlinkURL = externalDirectory.appendingPathComponent("workspace-readme.md")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        let resolution = LocalFileReferenceSupport.resolve(
            rawReference: symlinkURL.path,
            workspaceRoot: workspaceDirectory.path
        )

        XCTAssertEqual(resolution, .workspaceFile(targetURL.standardizedFileURL.resolvingSymlinksInPath()))
    }

    func testResolveDirectoryReturnsDirectory() throws {
        let resolution = LocalFileReferenceSupport.resolve(
            rawReference: workspaceDirectory.path,
            workspaceRoot: workspaceDirectory.path
        )

        XCTAssertEqual(resolution, .directory(workspaceDirectory.standardizedFileURL.resolvingSymlinksInPath()))
    }

    func testResolveMissingPathReturnsInvalid() {
        let missingPath = workspaceDirectory.appendingPathComponent("missing.txt").path

        XCTAssertEqual(
            LocalFileReferenceSupport.resolve(rawReference: missingPath, workspaceRoot: workspaceDirectory.path),
            .invalid
        )
    }

    func testDisplayPathUsesWorkspaceRelativePath() throws {
        let fileURL = workspaceDirectory.appendingPathComponent("src/Feature/View.swift")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "view".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            LocalFileReferenceSupport.displayPath(for: fileURL.path, workspaceRoot: workspaceDirectory.path),
            "src/Feature/View.swift"
        )
    }

    func testLinkifierLinkifiesBareFileURL() {
        let text = "Open file://\(workspaceDirectory.path)/notes.md please"

        let linked = LocalFileReferenceLinkifier.linkify(text)

        XCTAssertTrue(linked.contains("[file://"))
        XCTAssertTrue(linked.contains("](file://"))
    }

    func testLinkifierLinkifiesAbsolutePath() {
        let filePath = "/tmp/project/README.md"

        let linked = LocalFileReferenceLinkifier.linkify("See \(filePath) next")

        XCTAssertTrue(linked.contains("[\(filePath)](file://\(filePath))"))
    }

    func testLinkifierSkipsFencedCodeBlocksInlineCodeAndExistingLinks() {
        let text = """
        Here is `/tmp/inline.txt`

        ```swift
        let file = "/tmp/fenced.txt"
        let localhost = "http://localhost:3000"
        ```

        Existing [link](file:///tmp/already.md)
        Existing [site](https://example.com)
        """

        let linked = LocalFileReferenceLinkifier.linkify(text)

        XCTAssertTrue(linked.contains("`/tmp/inline.txt`"))
        XCTAssertTrue(linked.contains("let file = \"/tmp/fenced.txt\""))
        XCTAssertTrue(linked.contains("let localhost = \"http://localhost:3000\""))
        XCTAssertTrue(linked.contains("Existing [link](file:///tmp/already.md)"))
        XCTAssertTrue(linked.contains("Existing [site](https://example.com)"))
        XCTAssertFalse(linked.contains("[/tmp/inline.txt]"))
        XCTAssertFalse(linked.contains("[/tmp/fenced.txt]"))
    }

    func testLinkifierLinkifiesBareHTTPSURL() {
        let text = "See https://example.com/docs/getting-started for details"

        let linked = LocalFileReferenceLinkifier.linkify(text)

        XCTAssertEqual(
            linked,
            "See [https://example.com/docs/getting-started](https://example.com/docs/getting-started) for details"
        )
    }

    func testLinkifierLinkifiesBareLocalhostHTTPURL() {
        let text = "Open http://localhost:3000 to preview"

        let linked = LocalFileReferenceLinkifier.linkify(text)

        XCTAssertEqual(
            linked,
            "Open [http://localhost:3000](http://localhost:3000) to preview"
        )
    }

    func testSessionSummaryTouchedFilesKeepsFullPaths() {
        let toolCalls: [String: [AppState.ToolCallInfo]] = [
            "session-1": [
                AppState.ToolCallInfo(
                    tool: "edit",
                    input: #"{"file_path":"/tmp/project/Sources/App.swift"}"#,
                    output: nil,
                    timestamp: Date()
                ),
                AppState.ToolCallInfo(
                    tool: "edit",
                    input: #"{"file_path":"/tmp/project/Sources/App.swift"}"#,
                    output: nil,
                    timestamp: Date()
                ),
                AppState.ToolCallInfo(
                    tool: "write",
                    input: #"{"file_path":"/tmp/project/README.md"}"#,
                    output: nil,
                    timestamp: Date()
                ),
            ]
        ]

        let touchedFiles = SessionSummaryCard.touchedFiles(from: toolCalls)

        XCTAssertEqual(
            touchedFiles,
            [
                .init(path: "/tmp/project/README.md"),
                .init(path: "/tmp/project/Sources/App.swift"),
            ]
        )
    }
}
