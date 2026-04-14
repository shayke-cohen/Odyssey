import SwiftUI
import SwiftData

struct ScheduleDetailView: View {
    let scheduleId: UUID
    let onEdit: (ScheduledMission) -> Void
    let onDuplicate: (ScheduledMission) -> Void
    let onDelete: (ScheduledMission) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(WindowState.self) private var windowState: WindowState
    @Query private var schedules: [ScheduledMission]
    @Query(sort: \ScheduledMissionRun.startedAt, order: .reverse) private var runs: [ScheduledMissionRun]
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \AgentGroup.sortOrder) private var groups: [AgentGroup]
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]

    private var schedule: ScheduledMission? {
        schedules.first { $0.id == scheduleId }
    }

    private var scheduleRuns: [ScheduledMissionRun] {
        runs.filter { $0.scheduleId == scheduleId }
    }

    private var lastConversation: Conversation? {
        guard let conversationId = scheduleRuns.first(where: { $0.conversationId != nil })?.conversationId else {
            return nil
        }
        return conversations.first { $0.id == conversationId }
    }

    var body: some View {
        if let schedule {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(schedule)
                    missionCard(schedule)
                    settingsCard(schedule)
                    historyCard(schedule)
                }
                .padding(24)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .stableXrayId("scheduleDetail.scrollView")
        } else {
            ContentUnavailableView("Select a schedule", systemImage: "clock.badge")
                .stableXrayId("scheduleDetail.emptyState")
        }
    }

    @ViewBuilder
    private func header(_ schedule: ScheduledMission) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(schedule.name)
                        .font(.title2.bold())
                    HStack(spacing: 6) {
                        statusBadge(schedule.isEnabled ? "Enabled" : "Disabled", color: schedule.isEnabled ? .green : .gray)
                        statusBadge(targetName(for: schedule), color: .blue)
                        statusBadge(ScheduledMissionCadence.cadenceSummary(for: schedule), color: .purple)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Run Now") {
                    appState.runScheduledMissionNow(schedule.id, windowState: windowState)
                }
                .buttonStyle(.borderedProminent)
                .stableXrayId("scheduleDetail.runNowButton")

                Button(schedule.isEnabled ? "Pause" : "Enable") {
                    schedule.isEnabled.toggle()
                    appState.syncScheduledMission(schedule)
                }
                .buttonStyle(.bordered)
                .stableXrayId("scheduleDetail.enableToggleButton")

                Button("Edit") {
                    onEdit(schedule)
                }
                .buttonStyle(.bordered)
                .stableXrayId("scheduleDetail.editButton")

                if let lastConversation {
                    Button("Open Last Conversation") {
                        windowState.selectedConversationId = lastConversation.id
                    }
                    .buttonStyle(.bordered)
                    .stableXrayId("scheduleDetail.openConversationButton")
                }

                Menu {
                    Button("Duplicate") { onDuplicate(schedule) }
                    Button("Delete", role: .destructive) { onDelete(schedule) }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .stableXrayId("scheduleDetail.moreMenu")
            }

            HStack(spacing: 20) {
                infoLine("Next run", value: schedule.nextRunAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not scheduled")
                infoLine("Last success", value: schedule.lastSucceededAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                infoLine("Last failure", value: schedule.lastFailedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .stableXrayId("scheduleDetail.header")
    }

    @ViewBuilder
    private func missionCard(_ schedule: ScheduledMission) -> some View {
        card("Mission") {
            Text(schedule.promptTemplate)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .stableXrayId("scheduleDetail.missionCard")
    }

    @ViewBuilder
    private func settingsCard(_ schedule: ScheduledMission) -> some View {
        card("Execution Settings") {
            VStack(alignment: .leading, spacing: 8) {
                infoLine("Mode", value: schedule.runMode.displayName)
                infoLine("Project", value: schedule.projectDirectory)
                infoLine("Closed-app execution", value: schedule.runWhenAppClosed ? "Enabled" : "Disabled")
                if schedule.runWhenAppClosed {
                    infoLine("launchd", value: schedule.launchdJobLabel ?? "Pending sync")
                }
                if let lastConversation {
                    Button(lastConversation.topic ?? "Open linked conversation") {
                        windowState.selectedConversationId = lastConversation.id
                    }
                    .buttonStyle(.link)
                    .stableXrayId("scheduleDetail.linkedConversationButton")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .stableXrayId("scheduleDetail.settingsCard")
    }

    @ViewBuilder
    private func historyCard(_ schedule: ScheduledMission) -> some View {
        card("Run History") {
            if scheduleRuns.isEmpty {
                Text("No runs yet")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(scheduleRuns.prefix(12)) { run in
                        HStack {
                            statusBadge(run.status.displayName, color: color(for: run.status))
                            Text(run.scheduledFor.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let summary = run.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.caption)
                                    .lineLimit(1)
                            } else if let error = run.errorMessage, !error.isEmpty {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            } else if let reason = run.skipReason {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .stableXrayId("scheduleDetail.historyCard")
    }

    private func targetName(for schedule: ScheduledMission) -> String {
        switch schedule.targetKind {
        case .agent:
            return agents.first(where: { $0.id == schedule.targetAgentId })?.name ?? "Agent"
        case .group:
            return groups.first(where: { $0.id == schedule.targetGroupId })?.name ?? "Group"
        case .conversation:
            return conversations.first(where: { $0.id == schedule.targetConversationId })?.topic ?? "Conversation"
        }
    }

    private func color(for status: ScheduledMissionRunStatus) -> Color {
        switch status {
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoLine(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .fontWeight(.medium)
            Text(value)
        }
    }
}
