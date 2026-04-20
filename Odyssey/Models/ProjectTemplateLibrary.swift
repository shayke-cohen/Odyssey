struct ProjectTemplateLibrary {
    struct Entry: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let prompt: String
    }

    static let all: [Entry] = [
        Entry(
            name: "Check open issues",
            prompt: "List all open GitHub issues in this repo, grouped by label. Summarize the most critical ones and suggest triage actions."
        ),
        Entry(
            name: "Review open PRs",
            prompt: "List all open pull requests. For each one, summarize the changes, status, and any blocking concerns."
        ),
        Entry(
            name: "Recent activity",
            prompt: "Summarize the last 7 days of commits. Highlight significant changes, regressions, or areas needing attention."
        ),
        Entry(
            name: "Find TODOs",
            prompt: "Search the codebase for all TODO, FIXME, and HACK comments. Organize them by file and estimated effort."
        ),
        Entry(
            name: "Dependency audit",
            prompt: "Check all dependencies for available updates and known security vulnerabilities. Recommend actions."
        ),
        Entry(
            name: "Test coverage gaps",
            prompt: "Identify areas of the codebase with low or missing test coverage. Suggest what to add first."
        ),
        Entry(
            name: "Onboarding summary",
            prompt: "Produce a concise onboarding guide for this repo: architecture overview, key entry points, and dev setup steps."
        )
    ]
}
