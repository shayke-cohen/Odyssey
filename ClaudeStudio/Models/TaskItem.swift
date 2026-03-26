import Foundation
import SwiftData

enum TaskStatus: String, Codable, Sendable {
    case backlog
    case ready
    case inProgress
    case done
    case failed
    case blocked
}

enum TaskPriority: String, Codable, Sendable {
    case low
    case medium
    case high
    case critical
}

@Model
final class TaskItem {
    var id: UUID
    var title: String
    var taskDescription: String
    var status: TaskStatus
    var priority: TaskPriority
    var labels: [String]
    var result: String?
    var parentTaskId: UUID?
    var assignedAgentId: UUID?
    var assignedGroupId: UUID?
    var conversationId: UUID?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?

    init(
        title: String,
        taskDescription: String = "",
        priority: TaskPriority = .medium,
        labels: [String] = [],
        status: TaskStatus = .backlog
    ) {
        self.id = UUID()
        self.title = title
        self.taskDescription = taskDescription
        self.status = status
        self.priority = priority
        self.labels = labels
        self.createdAt = Date()
    }
}
