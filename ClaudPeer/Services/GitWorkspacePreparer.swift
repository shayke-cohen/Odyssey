import Foundation
import SwiftData

/// Ensures a GitHub-linked clone exists before the sidecar runs tools in that directory.
@MainActor
enum GitWorkspacePreparer {
    static func prepareIfNeeded(session: Session, modelContext: ModelContext) async throws {
        guard let agent = session.agent else { return }
        guard WorkspaceResolver.shouldManageGitHubClone(agent: agent, sessionWorkingDirectory: session.workingDirectory) else {
            return
        }
        guard let repo = agent.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty else { return }

        let path = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
        let branchRaw = agent.githubDefaultBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branch = branchRaw.isEmpty ? "main" : branchRaw

        try await GitHubIntegration.ensureClone(repoInput: repo, branch: branch, destinationPath: path)

        if session.workingDirectory != path {
            session.workingDirectory = path
        }
        session.workspaceType = .githubClone(repoUrl: repo)
        try? modelContext.save()
    }
}
