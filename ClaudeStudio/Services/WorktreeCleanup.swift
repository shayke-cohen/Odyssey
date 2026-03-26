import Foundation
import SwiftData

/// Removes git worktrees when sessions end and prunes orphans on startup.
/// Note: Session-level worktrees have been removed. Per-conversation worktrees
/// are managed by WorktreeManager and cleaned up via Conversation.worktreePath.
@MainActor
enum WorktreeCleanup {
    /// Scan for worktree directories that don't belong to any active conversation and remove them.
    static func pruneOrphaned(activeSessions: [Session]) async {
        let worktreeBase = "\(NSHomeDirectory())/.claudestudio/worktrees"
        let fm = FileManager.default
        guard fm.fileExists(atPath: worktreeBase) else { return }

        guard let repoDirs = try? fm.contentsOfDirectory(atPath: worktreeBase) else { return }
        for repoDir in repoDirs {
            let repoPath = (worktreeBase as NSString).appendingPathComponent(repoDir)
            guard let branchDirs = try? fm.contentsOfDirectory(atPath: repoPath) else { continue }
            for branchDir in branchDirs {
                let worktreePath = (repoPath as NSString).appendingPathComponent(branchDir)
                // Remove orphaned worktree directories
                try? fm.removeItem(atPath: worktreePath)
            }
            // Remove repo dir if empty
            if let remaining = try? fm.contentsOfDirectory(atPath: repoPath), remaining.isEmpty {
                try? fm.removeItem(atPath: repoPath)
            }
        }
    }
}
