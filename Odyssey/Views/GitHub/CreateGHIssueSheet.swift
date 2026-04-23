import SwiftUI
import SwiftData

// MARK: - Create GitHub Issue Sheet

struct CreateGHIssueSheet: View {
    let conversation: Conversation
    let project: Project?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var issueBody: String = ""
    @State private var selectedRepo: String = ""
    @State private var isSubmitting = false
    @State private var submitError: String? = nil

    private var settings: GHPollerSettings { GHPollerSettings.shared }

    private var availableRepos: [String] {
        var repos: [String] = []
        if !settings.inboxRepo.isEmpty { repos.append(settings.inboxRepo) }
        if let projectRepo = project?.githubRepo, !projectRepo.isEmpty {
            repos.append(projectRepo)
        }
        return repos
    }

    private var inboxRoutingLabels: [String] {
        guard let agent = conversation.sessions?.first?.agent else { return [] }
        return ["odyssey:agent:\(agent.name)"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleSection
                    repoSection
                    bodySection
                    if let err = submitError {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .stableXrayId("createGHIssue.errorLabel")
                    }
                }
                .padding(24)
            }
            Divider()
            footerBar
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            title = conversation.topic ?? ""
            selectedRepo = availableRepos.first ?? ""
        }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
            Text("Create GitHub Issue")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .stableXrayId("createGHIssue.closeButton")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.subheadline.weight(.medium))
            TextField("Issue title", text: $title)
                .textFieldStyle(.roundedBorder)
                .stableXrayId("createGHIssue.titleField")
        }
    }

    private var repoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repository")
                .font(.subheadline.weight(.medium))
            if availableRepos.isEmpty {
                Text("No repos configured. Connect a GitHub inbox repo in Settings → GitHub.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Repository", selection: $selectedRepo) {
                    ForEach(availableRepos, id: \.self) { repo in
                        Text(repo).tag(repo)
                    }
                }
                .labelsHidden()
                .stableXrayId("createGHIssue.repoPicker")

                if selectedRepo == settings.inboxRepo && !inboxRoutingLabels.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Will add label: \(inboxRoutingLabels.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description (optional)")
                .font(.subheadline.weight(.medium))
            TextEditor(text: $issueBody)
                .font(.callout)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                .stableXrayId("createGHIssue.bodyField")
        }
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .stableXrayId("createGHIssue.cancelButton")
            Button {
                submit()
            } label: {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Create Issue")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedRepo.isEmpty || isSubmitting)
            .stableXrayId("createGHIssue.submitButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func submit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, !selectedRepo.isEmpty else { return }

        var labels: [String] = []
        if selectedRepo == settings.inboxRepo {
            labels = inboxRoutingLabels
        }

        isSubmitting = true
        submitError = nil

        appState.sendToSidecar(.ghIssueCreate(
            repo: selectedRepo,
            title: trimmedTitle,
            body: issueBody.trimmingCharacters(in: .whitespacesAndNewlines),
            labels: labels,
            conversationId: conversation.id.uuidString
        ))

        dismiss()
    }
}
