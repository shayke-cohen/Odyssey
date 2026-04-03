import Foundation

enum ChatSessionWatchdog {
    static let noVisibleOutputTimeout: TimeInterval = 300

    static func shouldTrackSession(
        activity: AppState.SessionActivityState,
        hasStreamingText: Bool,
        hasThinkingText: Bool
    ) -> Bool {
        switch activity {
        case .thinking, .streaming, .callingTool, .waitingForResult:
            return true
        case .idle, .done, .error, .askingUser:
            return hasStreamingText || hasThinkingText
        }
    }

    static func shouldTriggerNoResponseTimeout(
        elapsed: TimeInterval,
        hasVisibleOutput: Bool,
        activity: AppState.SessionActivityState
    ) -> Bool {
        guard elapsed > noVisibleOutputTimeout else { return false }

        switch activity {
        case .thinking, .streaming, .callingTool, .waitingForResult:
            return !hasVisibleOutput
        case .idle, .done, .error, .askingUser:
            return false
        }
    }
}
