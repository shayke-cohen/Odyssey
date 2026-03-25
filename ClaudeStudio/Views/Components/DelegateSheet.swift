import SwiftUI
import SwiftData

struct DelegateSheet: View {
    let agent: Agent
    let initialTask: String
    /// Sidecar `delegate.task` source session (primary agent session in this conversation).
    let sourceSessionId: UUID
    var onDelegate: (() -> Void)?

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var taskText: String = ""
    @State private var contextText: String = ""
    @State private var waitForResult = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delegate Task")
                .font(.headline)

            agentHeader

            VStack(alignment: .leading, spacing: 4) {
                Text("Task")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextEditor(text: $taskText)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    .xrayId("delegate.taskField")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Context")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Optional — file paths, blackboard keys, or other context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $contextText)
                    .font(.body)
                    .frame(minHeight: 50, maxHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    .xrayId("delegate.contextField")
            }

            Toggle(isOn: $waitForResult) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wait for result")
                    Text("Block until the delegate finishes and return the result")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .xrayId("delegate.waitToggle")

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .xrayId("delegate.cancelButton")

                Spacer()

                Button {
                    performDelegation()
                } label: {
                    Label("Delegate", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
                .xrayId("delegate.submitButton")
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            taskText = initialTask
        }
    }

    private var agentHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: agent.icon)
                .font(.title2)
                .foregroundStyle(Color.fromAgentColor(agent.color))
                .frame(width: 36, height: 36)
                .background(Color.fromAgentColor(agent.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(agent.agentDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .xrayId("delegate.agentHeader")
    }

    private func performDelegation() {
        let task = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        let context = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.delegateTask(
            sourceSessionId: sourceSessionId,
            toAgent: agent.name,
            task: task,
            context: context.isEmpty ? nil : context,
            waitForResult: waitForResult
        )

        onDelegate?()
        dismiss()
    }
}
