import Foundation

struct LocalToolAccessPolicy: Sendable {
    private let rawRules: [String]
    private let normalizedRules: [String]

    init(rules: [String]) {
        self.rawRules = rules
        self.normalizedRules = rules.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    var allowsAllBuiltInTools: Bool {
        normalizedRules.isEmpty || normalizedRules.contains("*")
    }

    func allowedBuiltInToolNames(from definitions: [LocalAgentToolDefinition]) -> Set<String> {
        let availableNames = Set(definitions.map(\.name))
        guard !allowsAllBuiltInTools else { return availableNames }

        var allowed = Set<String>()
        for rule in normalizedRules {
            let lowercasedRule = rule.lowercased()
            if availableNames.contains(rule) {
                allowed.insert(rule)
                continue
            }

            switch canonicalRuleName(from: lowercasedRule) {
            case "read":
                allowed.formUnion(["read_file", "list_directory"])
            case "grep":
                allowed.insert("search_files")
            case "glob":
                allowed.insert("list_directory")
            case "write":
                allowed.formUnion(["write_file", "replace_in_file"])
            case "bash":
                allowed.insert("run_command")
            case "webfetch":
                allowed.insert("fetch_url")
            case "websearch":
                allowed.insert("web_search")
            default:
                break
            }
        }

        return allowed.intersection(availableNames)
    }

    func allowsInvocation(
        toolName: String,
        arguments: [String: DynamicValue],
        workingDirectory: String
    ) -> Bool {
        guard !allowsAllBuiltInTools else { return true }

        if normalizedRules.contains(toolName) {
            return true
        }

        switch toolName {
        case "read_file":
            return hasRule(named: "read")
        case "list_directory":
            return hasRule(named: "read") || hasRule(named: "glob")
        case "search_files":
            return hasRule(named: "grep")
        case "write_file", "replace_in_file":
            guard let path = arguments["path"]?.stringValue else { return false }
            return matchingRules(named: "write").contains { rule in
                matchesPathRule(rule: rule, path: path, workingDirectory: workingDirectory)
            }
        case "run_command":
            guard let command = arguments["command"]?.stringValue else { return false }
            return matchingRules(named: "bash").contains { rule in
                matchesCommandRule(rule: rule, command: command)
            }
        case "fetch_url":
            return hasRule(named: "webfetch")
        case "web_search":
            return hasRule(named: "websearch")
        default:
            return false
        }
    }

    private func hasRule(named name: String) -> Bool {
        !matchingRules(named: name).isEmpty
    }

    private func matchingRules(named name: String) -> [String] {
        normalizedRules.filter { canonicalRuleName(from: $0.lowercased()) == name }
    }

    private func canonicalRuleName(from rule: String) -> String {
        if let paren = rule.firstIndex(of: "(") {
            return String(rule[..<paren])
        }
        return rule
    }

    private func matchesPathRule(rule: String, path: String, workingDirectory: String) -> Bool {
        guard let pattern = rulePayload(rule) else {
            return true
        }

        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let workingDirectoryURL = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        let pathURL = URL(fileURLWithPath: standardizedPath)
        let relativePath = pathURL.path.hasPrefix(workingDirectoryURL.path)
            ? String(pathURL.path.dropFirst(workingDirectoryURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : nil
        let basename = pathURL.lastPathComponent

        return [standardizedPath, relativePath, basename]
            .compactMap { $0 }
            .contains { globMatches(pattern: pattern, value: $0) }
    }

    private func matchesCommandRule(rule: String, command: String) -> Bool {
        guard let pattern = rulePayload(rule) else {
            return true
        }
        return globMatches(pattern: pattern, value: command)
    }

    private func rulePayload(_ rule: String) -> String? {
        guard let open = rule.firstIndex(of: "("),
              let close = rule.lastIndex(of: ")"),
              open < close else {
            return nil
        }

        let payload = rule[rule.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        return payload.isEmpty ? nil : payload
    }

    private func globMatches(pattern: String, value: String) -> Bool {
        let regex = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
        guard let expression = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(location: 0, length: value.utf16.count)
        return expression.firstMatch(in: value, options: [], range: range) != nil
    }
}
