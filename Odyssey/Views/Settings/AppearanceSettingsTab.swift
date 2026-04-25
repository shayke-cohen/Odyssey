import SwiftUI
import SwiftData

struct AppearanceSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var conversations: [Conversation]

    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettings.textSizeKey, store: AppSettings.store) private var textSize = AppSettings.defaultTextSize
    @AppStorage(AppSettings.defaultMaxTurnsKey, store: AppSettings.store) private var defaultMaxTurns = AppSettings.defaultMaxTurns
    @AppStorage(AppSettings.defaultMaxBudgetKey, store: AppSettings.store) private var defaultMaxBudget = AppSettings.defaultMaxBudget

    @AppStorage(AppSettings.renderAdmonitionsKey, store: AppSettings.store) private var renderAdmonitions = true
    @AppStorage(AppSettings.renderDiffsKey, store: AppSettings.store) private var renderDiffs = true
    @AppStorage(AppSettings.renderTerminalKey, store: AppSettings.store) private var renderTerminal = true
    @AppStorage(AppSettings.renderMermaidKey, store: AppSettings.store) private var renderMermaid = true
    @AppStorage(AppSettings.renderHTMLKey, store: AppSettings.store) private var renderHTML = true
    @AppStorage(AppSettings.renderPDFKey, store: AppSettings.store) private var renderPDF = true
    @AppStorage(AppSettings.showSessionSummaryKey, store: AppSettings.store) private var showSessionSummary = true
    @AppStorage(AppSettings.showSuggestionChipsKey, store: AppSettings.store) private var showSuggestionChips = true

    @State private var showDeleteHistoryConfirmation = false

    private var selectedAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearance) ?? .system },
            set: { appearance = $0.rawValue }
        )
    }

    private var selectedTextSize: Binding<AppTextSize> {
        Binding(
            get: { AppTextSize(rawValue: textSize) ?? .standard },
            set: { textSize = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: selectedAppearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance.appearancePicker")

                Picker("Text Size", selection: selectedTextSize) {
                    ForEach(AppTextSize.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .accessibilityIdentifier("settings.appearance.textSizePicker")

                Text("Use View > Increase Text Size or the shortcuts ⌘+ / ⌘- to adjust it anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Runtime Defaults") {
                Stepper("Default Max Turns: \(defaultMaxTurns)", value: $defaultMaxTurns, in: 1...200)
                    .accessibilityIdentifier("settings.appearance.defaultMaxTurnsStepper")

                HStack {
                    Text("Default Max Budget")
                    Spacer()
                    TextField("$", value: $defaultMaxBudget, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("settings.appearance.defaultMaxBudgetField")
                    Text(defaultMaxBudget == 0 ? "(unlimited)" : "")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("Chat Display") {
                Toggle("Callout Cards", isOn: $renderAdmonitions)
                    .accessibilityIdentifier("settings.appearance.renderAdmonitions")
                Text("Render > [!info], > [!warning], etc. as styled cards")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Mermaid Diagrams", isOn: $renderMermaid)
                    .accessibilityIdentifier("settings.appearance.renderMermaid")
                Text("Render ```mermaid``` blocks as visual diagrams")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Inline HTML", isOn: $renderHTML)
                    .accessibilityIdentifier("settings.appearance.renderHTML")
                Text("Render HTML file cards inline via WebView")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Inline PDF", isOn: $renderPDF)
                    .accessibilityIdentifier("settings.appearance.renderPDF")
                Text("Show PDF pages inline instead of file card icon")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Tool Output") {
                Toggle("Inline Diffs", isOn: $renderDiffs)
                    .accessibilityIdentifier("settings.appearance.renderDiffs")
                Text("Show file edits as colored diffs instead of raw JSON")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Terminal Output", isOn: $renderTerminal)
                    .accessibilityIdentifier("settings.appearance.renderTerminal")
                Text("Style bash/shell output with terminal appearance")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Session") {
                Toggle("Session Summary Card", isOn: $showSessionSummary)
                    .accessibilityIdentifier("settings.appearance.showSessionSummary")
                Text("Show cost, tokens, and files touched when a session completes")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Suggestion Chips", isOn: $showSuggestionChips)
                    .accessibilityIdentifier("settings.appearance.showSuggestionChips")
                Text("Show follow-up action chips after agent responses")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Data") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chat History")
                        Text("\(conversations.count) thread\(conversations.count == 1 ? "" : "s") across all agents, groups, and projects")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Delete All…", role: .destructive) {
                        showDeleteHistoryConfirmation = true
                    }
                    .accessibilityIdentifier("settings.appearance.deleteAllHistoryButton")
                }
            }
        }
        .formStyle(.grouped)
        .settingsDetailLayout()
        .confirmationDialog(
            "Delete all chat history?",
            isPresented: $showDeleteHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Threads", role: .destructive) { deleteAllHistory() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes all \(conversations.count) thread\(conversations.count == 1 ? "" : "s") and their messages from agents, groups, and projects. This cannot be undone.")
        }
    }

    private func deleteAllHistory() {
        for conversation in conversations {
            for msg in (conversation.messages ?? []) {
                for att in (msg.attachments ?? []) { modelContext.delete(att) }
                modelContext.delete(msg)
            }
            for participant in (conversation.participants ?? []) { modelContext.delete(participant) }
            for session in (conversation.sessions ?? []) { modelContext.delete(session) }
            modelContext.delete(conversation)
        }
        try? modelContext.save()
    }
}
