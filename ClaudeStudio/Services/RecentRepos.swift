import Foundation

/// Manages a global list of recently-used GitHub repositories, persisted to
/// `~/.claudpeer/recent-repos.json` so all instances share the same history.
enum RecentRepos {
    private static let maxCount = 10

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudpeer/recent-repos.json")
    }

    static func load() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let repos = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return repos.filter { isValidRepoInput($0) }
    }

    /// Adds `repo` to the front of the list, deduplicating and capping at `maxCount`.
    static func add(_ repo: String) {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidRepoInput(trimmed) else { return }
        var repos = load()
        repos.removeAll { $0 == trimmed }
        repos.insert(trimmed, at: 0)
        if repos.count > maxCount {
            repos = Array(repos.prefix(maxCount))
        }
        save(repos)
    }

    private static func isValidRepoInput(_ input: String) -> Bool {
        !input.isEmpty && (input.contains("/") || input.hasPrefix("https://") || input.hasPrefix("git@"))
    }

    private static func save(_ repos: [String]) {
        let parentDir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(repos) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
