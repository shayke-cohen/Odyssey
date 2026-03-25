import Foundation

enum ChatSlashCommand: Equatable {
    case help
    case topic(String)
    case agents
    case unknown(String)
}

enum ChatSendRouting {
    /// First line only; returns nil if not a slash command.
    static func parseSlashCommand(_ raw: String) -> ChatSlashCommand? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "/", trimmed.count > 1 else { return nil }
        if trimmed.hasPrefix("//") { return nil }

        let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? trimmed
        let parts = firstLine.dropFirst().split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let cmd = parts.first.map(String.init)?.lowercased() ?? ""

        switch cmd {
        case "help", "?":
            return .help
        case "topic", "rename":
            let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return .topic(rest)
        case "agents":
            return .agents
        default:
            return .unknown(cmd)
        }
    }

    /// `@Name` tokens (no spaces in name segment).
    static func mentionedAgentNames(in text: String) -> [String] {
        let pattern = #"@([^\s@]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { m in
            guard m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    /// Match mention names to agents (exact name, case-insensitive).
    static func resolveMentionedAgents(names: [String], agents: [Agent]) -> (resolved: [Agent], unknown: [String]) {
        var resolved: [Agent] = []
        var unknown: [String] = []
        for raw in names {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if let a = agents.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) {
                if !resolved.contains(where: { $0.id == a.id }) {
                    resolved.append(a)
                }
            } else {
                unknown.append(key)
            }
        }
        return (resolved, unknown)
    }
}
