import SwiftUI
import SwiftData
import AppKit

struct SharedRoomInviteSheet: View {
    let conversationId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sharedRoomService: SharedRoomService
    @Query private var conversations: [Conversation]

    @State private var recipientLabel = ""
    @State private var expiryPreset: ExpiryPreset = .day
    @State private var singleUse = true
    @State private var generatedLink: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var conversation: Conversation? {
        conversations.first { $0.id == conversationId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Invite To Room")
                .font(.headline)
                .xrayId("sharedRoomInvite.title")

            if let conversation {
                Text("Room: \(conversation.topic ?? "Shared Room")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .xrayId("sharedRoomInvite.roomLabel")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Share with")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("iCloud contact or label", text: $recipientLabel)
                    .textFieldStyle(.roundedBorder)
                    .xrayId("sharedRoomInvite.recipientField")
            }

            Picker("Expires", selection: $expiryPreset) {
                ForEach(ExpiryPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .xrayId("sharedRoomInvite.expiryPicker")

            Toggle("Single use invite", isOn: $singleUse)
                .xrayId("sharedRoomInvite.singleUseToggle")

            Text("Transport: direct when possible, CloudKit sync always")
                .font(.caption)
                .foregroundStyle(.secondary)
                .xrayId("sharedRoomInvite.transportNote")

            if let generatedLink {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(generatedLink)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        .xrayId("sharedRoomInvite.generatedLink")
                    Button("Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(generatedLink, forType: .string)
                    }
                    .xrayId("sharedRoomInvite.copyButton")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .xrayId("sharedRoomInvite.error")
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .xrayId("sharedRoomInvite.cancelButton")
                Spacer()
                Button(isWorking ? "Creating…" : "Create Invite") {
                    Task { await createInvite() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || conversation == nil)
                .keyboardShortcut(.defaultAction)
                .xrayId("sharedRoomInvite.createButton")
            }
        }
        .padding(20)
    }

    private func createInvite() async {
        guard let conversation else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let invite = try await sharedRoomService.createInvite(
                for: conversation,
                recipientLabel: recipientLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                expiresIn: expiryPreset.interval,
                singleUse: singleUse
            )
            generatedLink = invite.deepLink
            errorMessage = nil
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ExpiryPreset: CaseIterable, Identifiable {
    case hour
    case day
    case week

    var id: String { label }

    var label: String {
        switch self {
        case .hour: return "1 hour"
        case .day: return "24 hours"
        case .week: return "7 days"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .hour: return 60 * 60
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
