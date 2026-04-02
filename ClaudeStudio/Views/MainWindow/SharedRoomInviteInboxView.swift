import SwiftUI
import SwiftData

struct SharedRoomInviteInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WindowState.self) private var windowState: WindowState
    @EnvironmentObject private var sharedRoomService: SharedRoomService
    @Query(sort: \SharedRoomInvite.updatedAt, order: .reverse) private var invites: [SharedRoomInvite]

    @State private var errorMessage: String?
    @State private var joiningInviteId: String?

    private var pendingInvites: [SharedRoomInvite] {
        invites.filter {
            $0.status == .pending && !$0.isRevoked && $0.expiresAt > Date()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Invites Inbox")
                    .font(.headline)
                    .xrayId("sharedRoomInbox.title")
                Spacer()
                Button("Done") { dismiss() }
                    .xrayId("sharedRoomInbox.doneButton")
            }

            if pendingInvites.isEmpty {
                ContentUnavailableView(
                    "No Pending Invites",
                    systemImage: "tray",
                    description: Text("Shared room invites that match this device will appear here.")
                )
                .xrayId("sharedRoomInbox.emptyState")
            } else {
                List(pendingInvites) { invite in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(invite.inviterDisplayName) invited you to \"\(invite.roomTopic)\"")
                            .font(.body)
                        Text("Full history • expires \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(joiningInviteId == invite.inviteId ? "Joining…" : "Join") {
                                Task { await join(invite) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(joiningInviteId != nil)
                            .xrayId("sharedRoomInbox.joinButton.\(invite.id.uuidString)")

                            Button("Decline") {
                                Task { await sharedRoomService.declineInvite(invite) }
                            }
                            .buttonStyle(.bordered)
                            .xrayId("sharedRoomInbox.declineButton.\(invite.id.uuidString)")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
                .xrayId("sharedRoomInbox.list")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .xrayId("sharedRoomInbox.error")
            }
        }
        .padding(20)
    }

    private func join(_ invite: SharedRoomInvite) async {
        joiningInviteId = invite.inviteId
        defer { joiningInviteId = nil }
        do {
            let conversation = try await sharedRoomService.acceptInvite(
                roomId: invite.roomId,
                inviteId: invite.inviteId,
                inviteToken: invite.inviteToken,
                projectId: windowState.selectedProjectId
            )
            windowState.selectedConversationId = conversation.id
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
