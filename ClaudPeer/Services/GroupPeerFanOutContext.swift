import Foundation

/// Budget and deduplication for automatic peer `session.message` fan-out in group chats.
final class GroupPeerFanOutContext: @unchecked Sendable {
    private var additionalTurnsRemaining: Int
    private var deliveredNotifyKeys: Set<String> = []

    init(maxAdditionalSidecarTurns: Int = 12) {
        self.additionalTurnsRemaining = maxAdditionalSidecarTurns
    }

    /// Reserves budget and records this (target, trigger) pair, or returns false if duplicate or budget exhausted.
    func trySchedulePeerDelivery(targetSessionId: UUID, triggerMessageId: UUID) -> Bool {
        let key = "\(targetSessionId.uuidString)|\(triggerMessageId.uuidString)"
        guard !deliveredNotifyKeys.contains(key) else { return false }
        guard additionalTurnsRemaining > 0 else { return false }
        additionalTurnsRemaining -= 1
        deliveredNotifyKeys.insert(key)
        return true
    }
}
