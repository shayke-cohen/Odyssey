import XCTest
@testable import ClaudPeer

final class WorkspaceResolverTests: XCTestCase {
    func testCloneURLShorthand() {
        XCTAssertEqual(
            WorkspaceResolver.cloneURL(from: "org/repo"),
            "https://github.com/org/repo"
        )
    }

    func testCloneURLPassthroughHttps() {
        XCTAssertEqual(
            WorkspaceResolver.cloneURL(from: "https://example.com/a.git"),
            "https://example.com/a.git"
        )
    }

    func testRepositoryDirectoryName() {
        let n = WorkspaceResolver.repositoryDirectoryName(repoInput: "https://github.com/foo/bar")
        XCTAssertEqual(n, "foo-bar")
    }

    func testCloneDestinationUnderRepos() {
        let p = WorkspaceResolver.cloneDestinationPath(repoInput: "org/repo")
        XCTAssertTrue(p.hasSuffix("/.claudpeer/repos/org-repo"))
    }
}
