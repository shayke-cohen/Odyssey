import Foundation

/// Static mapping of agent names to suggested prompts and action chips.
/// Used by ChatView (empty state + chips) and potentially WelcomeView.
enum AgentSuggestions {

    struct SuggestionSet {
        let starters: [String]   // 3-4 full prompt strings for empty state
        let chips: [String]      // 4-6 short chip labels
    }

    // MARK: - Per-Agent Suggestions

    static let byAgentName: [String: SuggestionSet] = [
        "Coder": SuggestionSet(
            starters: [
                "Implement a REST API endpoint for user authentication",
                "Refactor this function to use async/await",
                "Add error handling to the database layer",
                "Create a new SwiftUI view with data binding",
            ],
            chips: ["Write code", "Refactor", "Debug", "Add tests", "Explain code", "Fix the bug"]
        ),
        "Reviewer": SuggestionSet(
            starters: [
                "Review this PR for security vulnerabilities",
                "Check this code for performance issues",
                "Audit the error handling patterns in this module",
                "Review the API design for consistency",
            ],
            chips: ["Review code", "Security audit", "Check performance", "Style review", "Architecture review"]
        ),
        "Tester": SuggestionSet(
            starters: [
                "Write unit tests for the authentication module",
                "Create integration tests for the API endpoints",
                "Add UI tests for the main navigation flow",
                "Generate test cases for edge conditions",
            ],
            chips: ["Write tests", "Run tests", "Check coverage", "Test edge cases", "UI test"]
        ),
        "Orchestrator": SuggestionSet(
            starters: [
                "Plan and coordinate a new feature implementation",
                "Break down this project into tasks for the team",
                "Coordinate a code review and testing cycle",
                "Create a migration plan for the database schema",
            ],
            chips: ["Plan feature", "Delegate tasks", "Check status", "Coordinate team", "Summarize progress"]
        ),
        "Researcher": SuggestionSet(
            starters: [
                "Research best practices for error handling in Swift",
                "Find documentation on this API or framework",
                "Compare these two approaches and recommend one",
                "Analyze the codebase architecture and document findings",
            ],
            chips: ["Research topic", "Find docs", "Compare options", "Analyze codebase", "Summarize findings"]
        ),
        "Analyst": SuggestionSet(
            starters: [
                "Analyze the performance metrics for this module",
                "Generate a report on code complexity",
                "Track and visualize the test coverage trends",
                "Identify the most common error patterns",
            ],
            chips: ["Analyze data", "Generate report", "Track metrics", "Find patterns", "Visualize"]
        ),
        "Designer": SuggestionSet(
            starters: [
                "Review this UI for accessibility issues",
                "Suggest improvements for the onboarding flow",
                "Audit the color and typography consistency",
                "Design the layout for a new settings screen",
            ],
            chips: ["Review UI", "Accessibility", "Color audit", "Layout design", "UX feedback"]
        ),
        "DevOps": SuggestionSet(
            starters: [
                "Set up a CI/CD pipeline for this project",
                "Create a Dockerfile for the application",
                "Configure branch protection rules",
                "Set up automated deployment to staging",
            ],
            chips: ["Setup CI/CD", "Docker", "Git workflow", "Deploy", "Environment"]
        ),
        "Writer": SuggestionSet(
            starters: [
                "Write a README for this project",
                "Document the API endpoints",
                "Create a getting started guide",
                "Write release notes for the latest changes",
            ],
            chips: ["Write README", "API docs", "User guide", "Release notes", "Architecture doc"]
        ),
        "Product Manager": SuggestionSet(
            starters: [
                "Write requirements for a new feature",
                "Prioritize the backlog items",
                "Create a product roadmap for next quarter",
                "Define acceptance criteria for this user story",
            ],
            chips: ["Write spec", "Prioritize", "Roadmap", "User stories", "Acceptance criteria"]
        ),
        "Config Agent": SuggestionSet(
            starters: [
                "Generate a new agent configuration",
                "Create a specialized agent for this task",
                "Optimize the agent settings for code review",
                "Set up an agent group for full-stack development",
            ],
            chips: ["Create agent", "Configure", "Optimize settings", "Setup group"]
        ),
    ]

    // MARK: - Freeform (no agent)

    static let freeformSuggestions = SuggestionSet(
        starters: [
            "Help me write and debug some code",
            "Explain a concept or technology",
            "Review and improve this code",
            "Plan a feature implementation",
        ],
        chips: ["Write code", "Explain", "Review", "Plan", "Debug", "Research"]
    )

    // MARK: - Group Suggestions

    static let byGroupName: [String: SuggestionSet] = [
        "Dev Squad": SuggestionSet(
            starters: [
                "Implement a new feature with code review and tests",
                "Refactor this module and verify with tests",
                "Fix this bug, review the fix, and add regression tests",
            ],
            chips: ["Build feature", "Fix bug", "Refactor", "Add tests"]
        ),
        "Code Review Pair": SuggestionSet(
            starters: [
                "Write this feature and review it for quality",
                "Implement and review error handling improvements",
                "Build a new component with code review",
            ],
            chips: ["Write & review", "Improve code", "Check quality"]
        ),
        "Full Stack Team": SuggestionSet(
            starters: [
                "Build an end-to-end feature from code to deploy",
                "Implement, review, test, and deploy this change",
                "Ship a bug fix through the full pipeline",
            ],
            chips: ["Full pipeline", "Ship feature", "End-to-end fix"]
        ),
        "Plan & Build": SuggestionSet(
            starters: [
                "Plan and implement a new feature from scratch",
                "Design an architecture and build it with tests",
                "Break down this project and start building",
            ],
            chips: ["Plan & build", "Design architecture", "Break down tasks"]
        ),
        "Security Audit": SuggestionSet(
            starters: [
                "Audit this codebase for security vulnerabilities",
                "Scan for OWASP top 10 issues and write exploit tests",
                "Review authentication and authorization patterns",
            ],
            chips: ["Security scan", "Audit auth", "Exploit tests", "OWASP review"]
        ),
        "Product Crew": SuggestionSet(
            starters: [
                "Research the market and recommend a product direction",
                "Analyze user feedback and prioritize features",
                "Write a product spec based on research findings",
            ],
            chips: ["Research", "Analyze feedback", "Write spec", "Prioritize"]
        ),
        "Content Studio": SuggestionSet(
            starters: [
                "Research a topic and write a comprehensive guide",
                "Draft documentation and have it reviewed",
                "Create a technical blog post with editing",
            ],
            chips: ["Write docs", "Blog post", "Technical guide", "Edit draft"]
        ),
    ]

    static func groupSuggestions(for group: AgentGroup) -> SuggestionSet {
        byGroupName[group.name] ?? groupFallback(for: group)
    }

    private static func groupFallback(for group: AgentGroup) -> SuggestionSet {
        SuggestionSet(
            starters: [
                "Help me with a task using the \(group.name) team",
                "Coordinate the team on a new project",
                "Get started on a task together",
            ],
            chips: ["Get started", "Coordinate", "Plan together", "Assign tasks"]
        )
    }

    // MARK: - Lookup

    static func suggestions(for agent: Agent) -> SuggestionSet {
        byAgentName[agent.name] ?? fallback(for: agent)
    }

    private static func fallback(for agent: Agent) -> SuggestionSet {
        SuggestionSet(
            starters: [
                "Help me with \(agent.name.lowercased()) tasks",
                "What can you help me with?",
                "Get started on a new task",
            ],
            chips: ["Get started", "Help me with...", "Explain", "Create a plan"]
        )
    }
}
