import Foundation

// MARK: - Tooltip placement preference

enum WalkthroughTooltipSide {
    case right, left, above, below
}

// MARK: - Step model

struct WalkthroughStep: Identifiable {
    let id: WalkthroughAnchorID
    let title: String
    let body: String
    let whenToUse: String
    let preferredSide: WalkthroughTooltipSide

    // MARK: All 14 steps

    static let allSteps: [WalkthroughStep] = [
        // ── Sidebar ──────────────────────────────────────────────────────────
        WalkthroughStep(
            id: .sidebarSearch,
            title: "Search",
            body: "Full-text search across all your conversations and threads.",
            whenToUse: "Use when you need to find a past discussion, decision, or piece of code you talked through with an agent.",
            preferredSide: .right
        ),
        WalkthroughStep(
            id: .sidebarSchedules,
            title: "Schedules",
            body: "Agents that run automatically on a cron — daily standups, nightly builds, weekly reviews.",
            whenToUse: "Use when you want agents working while you're away from the keyboard.",
            preferredSide: .right
        ),
        WalkthroughStep(
            id: .sidebarPinned,
            title: "Pinned",
            body: "Your resident agents, favourite groups, and pinned projects — always at the top of the sidebar.",
            whenToUse: "Use when you have go-to agents you open every day. Pin them so you skip the picker.",
            preferredSide: .right
        ),
        WalkthroughStep(
            id: .sidebarAgents,
            title: "Agents",
            body: "AI specialists with their own model, skills, MCP tools, and permissions — Coder, Reviewer, Designer, and any custom agents you build.",
            whenToUse: "Use when you need focused expertise on a single task.",
            preferredSide: .right
        ),
        WalkthroughStep(
            id: .sidebarGroups,
            title: "Groups",
            body: "Named teams of agents that coordinate automatically on one prompt — Dev Squad, Security Audit, Full-Stack Team.",
            whenToUse: "Use when a task benefits from multiple perspectives at once.",
            preferredSide: .right
        ),
        WalkthroughStep(
            id: .sidebarProjects,
            title: "Projects",
            body: "Workspace folders that group related threads, tasks, and schedules. Link a GitHub repo so agents automatically know the working directory.",
            whenToUse: "Use when working on a codebase you want agents to be aware of.",
            preferredSide: .right
        ),
        WalkthroughStep(
            id: .sidebarToolbar,
            title: "Toolbar",
            body: "Quick launchers: browse the schedule list, open the agent or group library, or tap + to start a new conversation.",
            whenToUse: "Use to set up new agents or groups, review all schedules, or start a fresh session from anywhere.",
            preferredSide: .above
        ),

        // ── Chat header ───────────────────────────────────────────────────────
        WalkthroughStep(
            id: .chatHeader,
            title: "Agent Identity",
            body: "Shows who you're talking to, their model, and cost so far. Click the avatar to open the agent editor.",
            whenToUse: "Use when you want to check which model is active or tweak the agent's skills mid-conversation.",
            preferredSide: .below
        ),
        WalkthroughStep(
            id: .chatPlanMode,
            title: "Plan Mode",
            body: "The agent outlines a full plan before executing any actions. Great for catching misaligned assumptions early.",
            whenToUse: "Use for complex, multi-step tasks where you want to review the approach before the agent starts making changes.",
            preferredSide: .below
        ),
        WalkthroughStep(
            id: .chatMoreOptions,
            title: "More Options",
            body: "Fork a branch from the current message to explore a different direction, rename, duplicate, schedule, or export the conversation.",
            whenToUse: "Fork when you want to try a different approach without losing the original. Export to share a transcript.",
            preferredSide: .below
        ),

        // ── Chat body ─────────────────────────────────────────────────────────
        WalkthroughStep(
            id: .chatChips,
            title: "Skills & MCPs",
            body: "Active capabilities for this conversation — code execution, file system, GitHub, browser, and any custom MCP servers.",
            whenToUse: "Tap a chip to configure or disable a tool. Add new skills from the agent editor.",
            preferredSide: .below
        ),
        WalkthroughStep(
            id: .chatQuickActions,
            title: "Quick Actions",
            body: "One-click prompt shortcuts that fire pre-written prompts instantly — Write Tests, Code Review, Summarise, and your own custom actions.",
            whenToUse: "Use when you repeat the same kind of request often. Customise them in Settings → Quick Actions.",
            preferredSide: .above
        ),
        WalkthroughStep(
            id: .chatComposer,
            title: "Compose & Attach",
            body: "Type your message here. Shift+Enter for a new line. Drag in screenshots, log files, designs, or any document — the agent can read and act on them.",
            whenToUse: "Attach files when you want the agent to analyse, reference, or transform a specific document or image.",
            preferredSide: .above
        ),

        // ── Inspector ────────────────────────────────────────────────────────
        WalkthroughStep(
            id: .inspectorPanel,
            title: "Inspector  ⌘⌥0",
            body: "A collapsible right panel with three tabs — Files: live git-diff tree showing what the agent read or wrote. Board: project task tracker. Context: shared blackboard data across agents.",
            whenToUse: "Open it to review changes before committing, check agent-created tasks, or see shared state across a group conversation.",
            preferredSide: .left
        ),
    ]
}
