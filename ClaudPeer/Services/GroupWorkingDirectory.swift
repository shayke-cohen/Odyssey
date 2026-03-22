import Foundation
import SwiftData

/// Normalizes `Session.workingDirectory` for group conversations so every agent session shares one cwd when paths are unset.
enum GroupWorkingDirectory {
    @MainActor
    static func ensureShared(for conversation: Conversation, instanceDefault: String?, modelContext: ModelContext) {
        let agentSessions = conversation.sessions.filter { $0.agent != nil }
        guard !agentSessions.isEmpty else { return }

        func trimmed(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let primary = conversation.primarySession,
           !trimmed(primary.workingDirectory).isEmpty {
            let path = trimmed(primary.workingDirectory)
            var changed = false
            for s in agentSessions where trimmed(s.workingDirectory).isEmpty {
                s.workingDirectory = path
                changed = true
            }
            if changed { try? modelContext.save() }
            return
        }

        let sortedAgents = agentSessions.sorted { $0.startedAt < $1.startedAt }
        if let withPath = sortedAgents.first(where: { !trimmed($0.workingDirectory).isEmpty }) {
            let path = trimmed(withPath.workingDirectory)
            var changed = false
            for s in agentSessions where trimmed(s.workingDirectory).isEmpty {
                s.workingDirectory = path
                changed = true
            }
            if changed { try? modelContext.save() }
            return
        }

        let agents = agentSessions.compactMap(\.agent)
        let repos = Set(agents.compactMap { a -> String? in
            guard let r = a.githubRepo, !trimmed(r).isEmpty else { return nil }
            return trimmed(r)
        })
        let sharedRepo = repos.count == 1 ? repos.first : nil
        let canonical: String
        if let repo = sharedRepo,
           agents.allSatisfy({ ag in
               guard let r = ag.githubRepo, !trimmed(r).isEmpty else { return false }
               return trimmed(r) == repo
           }) {
            canonical = repoClonePath(repo: repo)
        } else if let inst = instanceDefault.map(trimmed), !inst.isEmpty {
            canonical = inst
        } else {
            canonical = "\(NSHomeDirectory())/.claudpeer/sandboxes/conversations/\(conversation.id.uuidString)"
        }

        try? FileManager.default.createDirectory(atPath: canonical, withIntermediateDirectories: true, attributes: nil)

        var changed = false
        for s in agentSessions where s.workingDirectory != canonical {
            s.workingDirectory = canonical
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    private static func repoClonePath(repo: String) -> String {
        WorkspaceResolver.cloneDestinationPath(repoInput: repo)
    }
}
