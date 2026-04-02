import Foundation

enum ExecutionModePromptBuilder {
    static func wrapDirectPrompt(
        _ text: String,
        mode: ConversationExecutionMode,
        mission: String? = nil,
        isFirstInteractiveTurn: Bool = false
    ) -> String {
        switch mode {
        case .interactive:
            return wrapInteractiveKickoffPrompt(
                text,
                mission: mission,
                isFirstTurn: isFirstInteractiveTurn,
                scopeLabel: "thread"
            )
        case .autonomous:
            return """
            [Execution Mode]
            This thread is running in autonomous mode.
            - Complete the current job end to end in this run.
            - Do not ask the user follow-up questions or wait for approval unless a hard blocker makes progress impossible.
            - If you are blocked, explain the blocker clearly and stop.
            - Return a concrete final result, not a status check-in.
            ---

            \(text)
            """
        case .worker:
            return """
            [Execution Mode]
            This thread is running in worker mode.
            - Treat this message as the current job to execute.
            - Do not ask the user follow-up questions or wait for approval unless a hard blocker makes progress impossible.
            - Complete the current job fully, report the result clearly, and assume this same thread will be reused for future jobs.
            - Keep your response action-oriented and concise.
            ---

            \(text)
            """
        }
    }

    static func wrapCoordinatorPrompt(
        _ prompt: String,
        mode: ConversationExecutionMode,
        coordinatorName: String?,
        mission: String? = nil,
        isFirstInteractiveTurn: Bool = false
    ) -> String {
        switch mode {
        case .interactive:
            return wrapInteractiveKickoffPrompt(
                prompt,
                mission: mission,
                isFirstTurn: isFirstInteractiveTurn,
                scopeLabel: "group thread"
            )
        case .autonomous:
            let coordinatorLabel = coordinatorName.map { "@\($0)" } ?? "the coordinator"
            return """
            [Execution Mode]
            This group thread is running in autonomous mode.
            You are receiving the user turn first as \(coordinatorLabel).
            - Lead the mission through the shared thread.
            - Coordinate teammates in the open with @mentions, blackboard updates, and task-board actions when useful.
            - Do not ask the user follow-up questions unless a hard blocker makes progress impossible.
            - Drive the mission to a concrete outcome in this run, then stop.
            ---

            \(prompt)
            """
        case .worker:
            let coordinatorLabel = coordinatorName.map { "@\($0)" } ?? "the coordinator"
            return """
            [Execution Mode]
            This group thread is running in worker mode.
            You are receiving the user turn first as \(coordinatorLabel).
            - Lead the current job through the shared thread.
            - Coordinate teammates in the open with @mentions, blackboard updates, and task-board actions when useful.
            - Do not ask the user follow-up questions unless a hard blocker makes progress impossible.
            - Complete the current job, report the result, and assume this same thread will be reused for future jobs.
            ---

            \(prompt)
            """
        }
    }

    private static func wrapInteractiveKickoffPrompt(
        _ text: String,
        mission: String?,
        isFirstTurn: Bool,
        scopeLabel: String
    ) -> String {
        guard isFirstTurn,
              let trimmedMission = mission?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedMission.isEmpty else {
            return text
        }

        return """
        [Saved Goal]
        This \(scopeLabel) already has a saved goal.
        Treat it as the current objective for the conversation unless the user explicitly changes direction.
        If the user asks what the goal or mission is, answer using this saved goal directly.

        Saved goal:
        \(trimmedMission)

        User message to respond to:
        \(text)
        """
    }
}
