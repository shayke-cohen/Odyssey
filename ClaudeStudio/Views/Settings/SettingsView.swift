import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .xrayId("settings.tab.general")

            ConnectionSettingsTab()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
                .xrayId("settings.tab.connection")

            ChatDisplaySettingsTab()
                .tabItem {
                    Label("Chat Display", systemImage: "bubble.left.and.text.bubble.right")
                }
                .xrayId("settings.tab.chatDisplay")

            DeveloperSettingsTab()
                .tabItem {
                    Label("Developer", systemImage: "wrench.and.screwdriver")
                }
                .xrayId("settings.tab.developer")
        }
        .frame(width: 480)
        .xrayId("settings.tabView")
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettings.textSizeKey, store: AppSettings.store) private var textSize = AppSettings.defaultTextSize
    @AppStorage(AppSettings.defaultProviderKey, store: AppSettings.store) private var defaultProvider = AppSettings.defaultProvider
    @AppStorage(AppSettings.defaultClaudeModelKey, store: AppSettings.store) private var defaultClaudeModel = AppSettings.defaultClaudeModel
    @AppStorage(AppSettings.defaultCodexModelKey, store: AppSettings.store) private var defaultCodexModel = AppSettings.defaultCodexModel
    @AppStorage(AppSettings.defaultMaxTurnsKey, store: AppSettings.store) private var defaultMaxTurns = AppSettings.defaultMaxTurns
    @AppStorage(AppSettings.defaultMaxBudgetKey, store: AppSettings.store) private var defaultMaxBudget = AppSettings.defaultMaxBudget
    @AppStorage(AppSettings.quickActionUsageOrderKey, store: AppSettings.store) private var quickActionUsageOrder = true

    private var selectedAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearance) ?? .system },
            set: { appearance = $0.rawValue }
        )
    }

    private var selectedProvider: Binding<ProviderSelection> {
        Binding(
            get: { ProviderSelection(rawValue: defaultProvider) ?? .claude },
            set: { defaultProvider = $0.rawValue }
        )
    }

    private var selectedClaudeModel: Binding<ClaudeModel> {
        Binding(
            get: { ClaudeModel(rawValue: AgentDefaults.normalizedModelSelection(defaultClaudeModel)) ?? .sonnet },
            set: { defaultClaudeModel = $0.rawValue }
        )
    }

    private var selectedCodexModel: Binding<CodexModel> {
        Binding(
            get: { CodexModel(rawValue: AgentDefaults.normalizedModelSelection(defaultCodexModel)) ?? .gpt5Codex },
            set: { defaultCodexModel = $0.rawValue }
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
                .xrayId("settings.general.appearancePicker")

                Picker("Text Size", selection: selectedTextSize) {
                    ForEach(AppTextSize.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .xrayId("settings.general.textSizePicker")

                Text("Use View > Increase Text Size or the shortcuts ⌘+ / ⌘- to adjust it anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Defaults") {
                Picker("Default Provider", selection: selectedProvider) {
                    ForEach([ProviderSelection.claude, ProviderSelection.codex]) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .xrayId("settings.general.defaultProviderPicker")

                Picker("Default Claude Model", selection: selectedClaudeModel) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .xrayId("settings.general.defaultClaudeModelPicker")

                Picker("Default Codex Model", selection: selectedCodexModel) {
                    ForEach(CodexModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .xrayId("settings.general.defaultCodexModelPicker")

                Stepper("Default Max Turns: \(defaultMaxTurns)", value: $defaultMaxTurns, in: 1...200)
                    .xrayId("settings.general.defaultMaxTurnsStepper")

                HStack {
                    Text("Default Max Budget")
                    Spacer()
                    TextField("$", value: $defaultMaxBudget, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .xrayId("settings.general.defaultMaxBudgetField")
                    Text(defaultMaxBudget == 0 ? "(unlimited)" : "")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("Quick Actions") {
                Toggle("Order quick actions by usage", isOn: $quickActionUsageOrder)
                    .xrayId("settings.general.quickActionUsageOrderToggle")
                    .help("When enabled, quick action buttons reorder based on how often you use them (after 10 uses). When disabled, uses the default popularity order.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Connection

private struct ConnectionSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettings.autoConnectSidecarKey, store: AppSettings.store) private var autoConnectSidecar = true
    @AppStorage(AppSettings.wsPortKey, store: AppSettings.store) private var wsPort = AppSettings.defaultWsPort
    @AppStorage(AppSettings.httpPortKey, store: AppSettings.store) private var httpPort = AppSettings.defaultHttpPort

    var body: some View {
        Form {
            Section("Sidecar Status") {
                HStack(spacing: 8) {
                    statusDot
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusLabel)
                            .font(.body)
                        if appState.sidecarStatus == .connected {
                            Text("ws://localhost:\(appState.allocatedWsPort)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .xrayId("settings.connection.statusURL")
                        }
                    }
                    Spacer()
                    statusActions
                }
                .xrayId("settings.connection.statusRow")
            }

            Section("Preferences") {
                Toggle("Auto-connect on Launch", isOn: $autoConnectSidecar)
                    .xrayId("settings.connection.autoConnectToggle")
            }

            Section("Ports") {
                HStack {
                    Text("WebSocket Port")
                    Spacer()
                    TextField("9849", value: $wsPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .xrayId("settings.connection.wsPortField")
                }

                HStack {
                    Text("HTTP API Port")
                    Spacer()
                    TextField("9850", value: $httpPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .xrayId("settings.connection.httpPortField")
                }

                Text("Changes take effect after restarting the sidecar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var statusDot: some View {
        switch appState.sidecarStatus {
        case .connected:
            Circle().fill(.green).frame(width: 10, height: 10)
        case .connecting:
            ProgressView().controlSize(.small)
        case .disconnected:
            Circle().fill(.gray).frame(width: 10, height: 10)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private var statusLabel: String {
        switch appState.sidecarStatus {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnected: "Disconnected"
        case .error(let msg): "Error: \(msg)"
        }
    }

    @ViewBuilder
    private var statusActions: some View {
        switch appState.sidecarStatus {
        case .connected:
            Button("Reconnect") {
                appState.disconnectSidecar()
                appState.connectSidecar()
            }
            .controlSize(.small)
            .xrayId("settings.connection.reconnectButton")

            Button("Stop") {
                appState.disconnectSidecar()
            }
            .controlSize(.small)
            .foregroundStyle(.red)
            .xrayId("settings.connection.stopButton")

        case .disconnected, .error:
            Button("Connect") {
                appState.connectSidecar()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .xrayId("settings.connection.connectButton")

        case .connecting:
            EmptyView()
        }
    }
}

// MARK: - Chat Display

private struct ChatDisplaySettingsTab: View {
    @AppStorage(AppSettings.renderAdmonitionsKey, store: AppSettings.store) private var renderAdmonitions = true
    @AppStorage(AppSettings.renderDiffsKey, store: AppSettings.store) private var renderDiffs = true
    @AppStorage(AppSettings.renderTerminalKey, store: AppSettings.store) private var renderTerminal = true
    @AppStorage(AppSettings.renderMermaidKey, store: AppSettings.store) private var renderMermaid = true
    @AppStorage(AppSettings.renderHTMLKey, store: AppSettings.store) private var renderHTML = true
    @AppStorage(AppSettings.renderPDFKey, store: AppSettings.store) private var renderPDF = true
    @AppStorage(AppSettings.showSessionSummaryKey, store: AppSettings.store) private var showSessionSummary = true
    @AppStorage(AppSettings.showSuggestionChipsKey, store: AppSettings.store) private var showSuggestionChips = true

    var body: some View {
        Form {
            Section("Rich Content") {
                Toggle("Callout Cards", isOn: $renderAdmonitions)
                    .xrayId("settings.chatDisplay.renderAdmonitions")
                Text("Render > [!info], > [!warning], etc. as styled cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Inline HTML", isOn: $renderHTML)
                    .xrayId("settings.chatDisplay.renderHTML")
                Text("Render HTML file cards inline via WebView")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Mermaid Diagrams", isOn: $renderMermaid)
                    .xrayId("settings.chatDisplay.renderMermaid")
                Text("Render ```mermaid``` blocks as visual diagrams")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Inline PDF", isOn: $renderPDF)
                    .xrayId("settings.chatDisplay.renderPDF")
                Text("Show PDF pages inline instead of file card icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tool Output") {
                Toggle("Inline Diffs", isOn: $renderDiffs)
                    .xrayId("settings.chatDisplay.renderDiffs")
                Text("Show file edits as colored diffs instead of raw JSON")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Terminal Output", isOn: $renderTerminal)
                    .xrayId("settings.chatDisplay.renderTerminal")
                Text("Style bash/shell output with terminal appearance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Session") {
                Toggle("Session Summary Card", isOn: $showSessionSummary)
                    .xrayId("settings.chatDisplay.showSessionSummary")
                Text("Show cost, tokens, and files touched when a session completes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Suggestion Chips", isOn: $showSuggestionChips)
                    .xrayId("settings.chatDisplay.showSuggestionChips")
                Text("Show follow-up action chips after agent responses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Developer

private struct DeveloperSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettings.bunPathOverrideKey, store: AppSettings.store) private var bunPathOverride = ""
    @AppStorage(AppSettings.sidecarPathKey, store: AppSettings.store) private var sidecarPath = ""
    @AppStorage(AppSettings.dataDirectoryKey, store: AppSettings.store) private var dataDirectory = AppSettings.defaultDataDirectory
    @AppStorage(AppSettings.logLevelKey, store: AppSettings.store) private var logLevel = AppSettings.defaultLogLevel
    @State private var showResetConfirmation = false

    private var selectedLogLevel: Binding<LogLevel> {
        Binding(
            get: { LogLevel(rawValue: logLevel) ?? .info },
            set: { logLevel = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Paths") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bun Path Override")
                    HStack {
                        TextField("Auto-detect", text: $bunPathOverride)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("settings.developer.bunPathField")
                        Button("Browse...") {
                            browseBunPath()
                        }
                        .xrayId("settings.developer.bunPathBrowseButton")
                    }
                    if bunPathOverride.isEmpty {
                        Text("Will search: /opt/homebrew/bin/bun, /usr/local/bin/bun, ~/.bun/bin/bun")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Path")
                    HStack {
                        TextField("Auto-detect", text: $sidecarPath)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("settings.developer.sidecarPathField")
                        Button("Browse...") {
                            browseProjectPath()
                        }
                        .xrayId("settings.developer.sidecarPathBrowseButton")
                    }
                    Text("Root directory containing the sidecar/ folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data Directory")
                    HStack {
                        TextField("~/.claudestudio", text: $dataDirectory)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("settings.developer.dataDirectoryField")
                        Button("Browse...") {
                            browseDataDirectory()
                        }
                        .xrayId("settings.developer.dataDirectoryBrowseButton")
                    }
                    Text("Stores logs, blackboard data, repos, and sandboxes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Logging") {
                Picker("Log Level", selection: selectedLogLevel) {
                    ForEach(LogLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .xrayId("settings.developer.logLevelPicker")
                .onChange(of: logLevel) { _, newValue in
                    guard appState.sidecarStatus == .connected,
                          let manager = appState.sidecarManager else { return }
                    Task {
                        try? await manager.send(.configSetLogLevel(level: newValue))
                    }
                }
            }

            Section {
                HStack {
                    Button("Open Data Directory in Finder") {
                        openDataDirectory()
                    }
                    .xrayId("settings.developer.openDataDirectoryButton")

                    Spacer()

                    Button("Reset All Settings", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .xrayId("settings.developer.resetSettingsButton")
                    .confirmationDialog(
                        "Reset all settings to defaults?",
                        isPresented: $showResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Reset", role: .destructive) {
                            AppSettings.resetAll()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will revert all preferences to their default values. The sidecar will need to be restarted.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func browseBunPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the Bun executable"
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            bunPathOverride = url.path
        }
    }

    private func browseProjectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the ClaudeStudio project directory"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if panel.runModal() == .OK, let url = panel.url {
            sidecarPath = url.path
        }
    }

    private func browseDataDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the data directory"
        let expandedPath = NSString(string: dataDirectory).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expandedPath)
        if panel.runModal() == .OK, let url = panel.url {
            dataDirectory = url.path
        }
    }

    private func openDataDirectory() {
        let expandedPath = NSString(string: dataDirectory).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath))
    }
}

#Preview {
    SettingsView()
}
