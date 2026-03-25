import SwiftUI
import SwiftData

struct AttachRepoSheet: View {
    let conversationId: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var repoInput = ""
    @State private var branch = "main"
    @State private var attachMode: AttachMode = .cloneAndSwitch
    @State private var applyToAllSessions = true
    @State private var isCloning = false
    @State private var errorMessage: String?
    @State private var recentRepos: [String] = []

    private enum AttachMode: Int, Hashable {
        case cloneAndSwitch = 0
        case referenceOnly = 1
    }

    private var conversation: Conversation? {
        try? modelContext.fetch(
            FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == conversationId })
        ).first
    }

    private var hasSessions: Bool {
        guard let convo = conversation else { return false }
        return !convo.sessions.isEmpty
    }

    private var isRepoInputValid: Bool {
        let trimmed = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && (trimmed.contains("/") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("git@"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Attach GitHub Repository")
                .font(.title3)
                .fontWeight(.semibold)
                .xrayId("attachRepo.title")

            if !recentRepos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(recentRepos.prefix(6).enumerated()), id: \.offset) { index, repo in
                            Button {
                                repoInput = repo
                                branch = "main"
                            } label: {
                                Text(repo)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(repoInput == repo ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                                    .clipShape(Capsule())
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(repoInput == repo ? Color.accentColor : .clear, lineWidth: 1.5)
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(repo)
                            .xrayId("attachRepo.recentChip.\(index)")
                            .accessibilityLabel("Select recent repository: \(repo)")
                        }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Repo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                TextField("org/repo or URL", text: $repoInput)
                    .textFieldStyle(.roundedBorder)
                    .xrayId("attachRepo.repoField")
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                TextField("main", text: $branch)
                    .textFieldStyle(.roundedBorder)
                    .xrayId("attachRepo.branchField")
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $attachMode) {
                    Text("Clone & work in repo").tag(AttachMode.cloneAndSwitch)
                    Text("Clone as reference").tag(AttachMode.referenceOnly)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .disabled(!hasSessions && attachMode == .cloneAndSwitch)
                .xrayId("attachRepo.modePicker")

                Group {
                    switch attachMode {
                    case .cloneAndSwitch:
                        Text("Changes working directory to the cloned repo path.")
                    case .referenceOnly:
                        Text("Keeps current directory. Agent gets repo context as a message.")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if !hasSessions {
                Text("No active sessions — only 'Clone as reference' is available.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let convo = conversation, convo.sessions.count > 1 {
                Toggle("Apply to all sessions in this conversation", isOn: $applyToAllSessions)
                    .font(.caption)
                    .xrayId("attachRepo.applyAllToggle")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .xrayId("attachRepo.error")
            }

            HStack {
                if isCloning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Cloning…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .xrayId("attachRepo.cancelButton")

                Button("Attach") {
                    Task { await attachRepo() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(!isRepoInputValid || isCloning || (!hasSessions && attachMode == .cloneAndSwitch))
                .xrayId("attachRepo.attachButton")
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            recentRepos = RecentRepos.load()
            if !hasSessions {
                attachMode = .referenceOnly
            }
        }
    }

    private func attachRepo() async {
        let repo = repoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let branchName = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBranch = branchName.isEmpty ? "main" : branchName
        let clonePath = WorkspaceResolver.cloneDestinationPath(repoInput: repo)

        isCloning = true
        errorMessage = nil
        defer { isCloning = false }

        // 1. Clone
        do {
            try await GitHubIntegration.ensureClone(repoInput: repo, branch: resolvedBranch, destinationPath: clonePath)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        guard let convo = conversation else {
            errorMessage = "Conversation not found."
            return
        }

        // 2. Determine sessions to update
        let sessionsToUpdate: [Session]
        if applyToAllSessions {
            sessionsToUpdate = convo.sessions
        } else {
            sessionsToUpdate = Array(convo.sessions.prefix(1))
        }

        // 3. Update sessions if clone & switch
        if attachMode == .cloneAndSwitch {
            for session in sessionsToUpdate {
                session.workingDirectory = clonePath
                session.workspaceType = .githubClone(repoUrl: repo)
            }
        }

        // 4. Add system message
        let messageText: String
        if attachMode == .cloneAndSwitch {
            messageText = "[System] Repository \(repo) cloned to \(clonePath). Working directory updated."
        } else {
            messageText = "[System] Repository \(repo) cloned to \(clonePath) as reference. Working directory unchanged."
        }

        let sysMsg = ConversationMessage(
            senderParticipantId: nil,
            text: messageText,
            type: .system,
            conversation: convo
        )
        convo.messages.append(sysMsg)

        // 5. Save + refresh
        try? modelContext.save()
        RecentRepos.add(repo)

        await MainActor.run {
            appState.fileTreeRefreshTrigger += 1
        }

        // 6. Notify sidecar
        for session in sessionsToUpdate {
            if attachMode == .cloneAndSwitch {
                try? await appState.sidecarManager?.send(
                    .sessionUpdateCwd(sessionId: session.id.uuidString, workingDirectory: clonePath)
                )
            }
            try? await appState.sidecarManager?.send(
                .sessionMessage(sessionId: session.id.uuidString, text: messageText)
            )
        }

        dismiss()
    }
}
