import Foundation
import SwiftData

enum ScheduledMissionRunStatus: String, Codable, CaseIterable, Sendable {
    case running
    case succeeded
    case failed
    case skipped

    var displayName: String {
        rawValue.capitalized
    }
}

enum ScheduledMissionRunTriggerSource: String, Codable, Sendable {
    case timer
    case launchd
    case manual
}

@Model
final class ScheduledMissionRun {
    var id: UUID = UUID()
    var scheduleId: UUID = UUID()
    var occurrenceKey: String = ""
    var status: ScheduledMissionRunStatus = ScheduledMissionRunStatus.running
    var triggerSource: ScheduledMissionRunTriggerSource = ScheduledMissionRunTriggerSource.manual
    var scheduledFor: Date = Date()
    var startedAt: Date = Date()
    var completedAt: Date?
    var conversationId: UUID?
    var summary: String?
    var errorMessage: String?
    var skipReason: String?

    init(
        scheduleId: UUID,
        occurrenceKey: String,
        status: ScheduledMissionRunStatus,
        triggerSource: ScheduledMissionRunTriggerSource,
        scheduledFor: Date,
        startedAt: Date = Date()
    ) {
        self.id = UUID()
        self.scheduleId = scheduleId
        self.occurrenceKey = occurrenceKey
        self.status = status
        self.triggerSource = triggerSource
        self.scheduledFor = scheduledFor
        self.startedAt = startedAt
    }

    static func occurrenceKey(scheduleId: UUID, scheduledFor: Date) -> String {
        "\(scheduleId.uuidString)|\(ISO8601DateFormatter().string(from: scheduledFor))"
    }
}
