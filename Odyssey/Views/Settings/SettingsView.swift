import SwiftUI
import SwiftData

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case models
    case connection
    case connectors
    case chatDisplay
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        case .connection: "Connection"
        case .connectors: "Connectors"
        case .chatDisplay: "Chat Display"
        case .developer: "Developer"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Appearance, reading comfort, and quick actions"
        case .models: "Cloud defaults and local MLX library management"
        case .connection: "Sidecar lifecycle and local ports"
        case .connectors: "OAuth setup, broker config, and tokens"
        case .chatDisplay: "Rendering and conversation chrome"
        case .developer: "Paths, diagnostics, and experimental controls"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .models: "cpu"
        case .connection: "network"
        case .connectors: "link.badge.plus"
        case .chatDisplay: "bubble.left.and.text.bubble.right"
        case .developer: "wrench.and.screwdriver"
        }
    }

    var xrayId: String {
        switch self {
        case .general: "settings.tab.general"
        case .models: "settings.tab.models"
        case .connection: "settings.tab.connection"
        case .connectors: "settings.tab.connectors"
        case .chatDisplay: "settings.tab.chatDisplay"
        case .developer: "settings.tab.developer"
        }
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsSection

    private let onBackToApp: (() -> Void)?

    init(
        initialSection: SettingsSection = .general,
        onBackToApp: (() -> Void)? = nil
    ) {
        _selectedSection = State(initialValue: initialSection)
        self.onBackToApp = onBackToApp
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                sidebar
                    .frame(width: min(max(proxy.size.width * 0.24, 250), 320))
                Divider()
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(settingsBackground.ignoresSafeArea())
        }
        .xrayId("settings.tabView")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let onBackToApp {
                Button(action: onBackToApp) {
                    Label("Back to app", systemImage: "arrow.left")
                        .font(.headline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .xrayId("settings.backButton")
                .accessibilityIdentifier("settings.backButton")
                .accessibilityLabel("Back to app")
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.systemImage)
                                .font(.body.weight(.semibold))
                                .frame(width: 20)
                            Text(section.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedSection == section ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedSection == section ? Color.primary.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .buttonStyle(.plain)
                    .xrayId(section.xrayId)
                    .accessibilityIdentifier("settings.section.\(section.rawValue)")
                    .accessibilityLabel(section.title)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .xrayId("settings.sidebar")
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedSection.title)
                    .font(.system(size: 34, weight: .bold))
                    .accessibilityIdentifier("settings.headerTitle")
                Text(selectedSection.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.headerSubtitle")
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 12)
            .xrayId("settings.header")

            selectedSectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .xrayId("settings.detailPane")
    }

    private var selectedSectionContent: some View {
        Group {
            switch selectedSection {
            case .general:
                GeneralSettingsTab()
            case .models:
                ModelsSettingsTab()
            case .connection:
                ConnectionSettingsTab()
            case .connectors:
                ConnectorsSettingsTab()
            case .chatDisplay:
                ChatDisplaySettingsTab()
            case .developer:
                DeveloperSettingsTab()
            }
        }
    }

    private var settingsBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.93, blue: 0.88),
                Color(red: 0.96, green: 0.91, blue: 0.94),
                Color(red: 0.90, green: 0.95, blue: 0.99),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage(AppSettings.appearanceKey, store: AppSettings.store) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettings.textSizeKey, store: AppSettings.store) private var textSize = AppSettings.defaultTextSize
    @AppStorage(AppSettings.quickActionUsageOrderKey, store: AppSettings.store) private var quickActionUsageOrder = true
    @AppStorage(AppSettings.defaultMaxTurnsKey, store: AppSettings.store) private var defaultMaxTurns = AppSettings.defaultMaxTurns
    @AppStorage(AppSettings.defaultMaxBudgetKey, store: AppSettings.store) private var defaultMaxBudget = AppSettings.defaultMaxBudget

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

            Section("Quick Actions") {
                Toggle("Order quick actions by usage", isOn: $quickActionUsageOrder)
                    .xrayId("settings.general.quickActionUsageOrderToggle")
                    .help("When enabled, quick action buttons reorder based on how often you use them (after 10 uses). When disabled, uses the default popularity order.")
            }

            Section("Runtime Defaults") {
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
        }
        .formStyle(.grouped)
        .settingsDetailLayout()
    }
}

// MARK: - Models

private struct ModelsSettingsTab: View {
    private struct MLXModelDescriptor: Identifiable {
        let id: String
        let title: String
        let modelIdentifier: String
        let defaultSelectionValue: String
        let summary: String
        let parameterSize: String
        let downloadSize: String
        let bestFor: String
        let agentSuitability: String
        let recommended: Bool
        let isInstalled: Bool
        let managedPath: String?
        let sourceURL: String?
    }

    private let customMLXSelectionTag = "__custom__"

    @AppStorage(AppSettings.defaultProviderKey, store: AppSettings.store) private var defaultProvider = AppSettings.defaultProvider
    @AppStorage(AppSettings.defaultClaudeModelKey, store: AppSettings.store) private var defaultClaudeModel = AppSettings.defaultClaudeModel
    @AppStorage(AppSettings.defaultCodexModelKey, store: AppSettings.store) private var defaultCodexModel = AppSettings.defaultCodexModel
    @AppStorage(AppSettings.defaultFoundationModelKey, store: AppSettings.store) private var defaultFoundationModel = AppSettings.defaultFoundationModel
    @AppStorage(AppSettings.defaultMLXModelKey, store: AppSettings.store) private var defaultMLXModel = AppSettings.defaultMLXModel
    @AppStorage(AppSettings.sidecarPathKey, store: AppSettings.store) private var sidecarPath = ""
    @AppStorage(AppSettings.localAgentHostPathOverrideKey, store: AppSettings.store) private var localAgentHostPathOverride = ""
    @AppStorage(AppSettings.mlxRunnerPathOverrideKey, store: AppSettings.store) private var mlxRunnerPathOverride = ""
    @AppStorage(AppSettings.dataDirectoryKey, store: AppSettings.store) private var dataDirectory = AppSettings.defaultDataDirectory

    @State private var modelsCatalog: ManagedMLXModelsCatalog?
    @State private var isLoadingCatalog = false
    @State private var catalogMessage: String?
    @State private var customModelInput = ""
    @State private var showCustomDefaultMLXInput = false
    @State private var isInstallingMLXRunner = false
    @State private var installingModelId: String?
    @State private var deletingModelId: String?
    @State private var deleteConfirmationModel: ManagedInstalledMLXModel?
    @State private var smokeTestingModelId: String?
    @State private var smokeTestResults: [String: ManagedMLXSmokeTestResult] = [:]

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

    private var selectedFoundationModel: Binding<FoundationModel> {
        Binding(
            get: { FoundationModel(rawValue: AgentDefaults.normalizedModelSelection(defaultFoundationModel)) ?? .system },
            set: { defaultFoundationModel = $0.rawValue }
        )
    }

    private var localProviderReport: LocalProviderStatusReport {
        LocalProviderSupport.statusReport(
            projectRootOverride: sidecarPath.isEmpty ? nil : sidecarPath,
            hostOverride: localAgentHostPathOverride.isEmpty ? nil : localAgentHostPathOverride,
            mlxRunnerOverride: mlxRunnerPathOverride.isEmpty ? nil : mlxRunnerPathOverride,
            dataDirectoryPath: dataDirectory,
            defaultMLXModel: defaultMLXModel
        )
    }

    private var catalogPresets: [ManagedMLXModelPreset] {
        modelsCatalog?.presets ?? LocalProviderInstaller.recommendedMLXPresets()
    }

    private var installedModels: [ManagedInstalledMLXModel] {
        modelsCatalog?.installed ?? localProviderReport.installedMLXModels
    }

    private var installedModelLookup: [String: ManagedInstalledMLXModel] {
        Dictionary(uniqueKeysWithValues: installedModels.map { ($0.modelIdentifier, $0) })
    }

    private var presetLookup: [String: ManagedMLXModelPreset] {
        Dictionary(uniqueKeysWithValues: catalogPresets.map { ($0.modelIdentifier, $0) })
    }

    private var installedModelDescriptors: [MLXModelDescriptor] {
        installedModels
            .compactMap { descriptor(for: $0.modelIdentifier, installedModel: $0) }
            .sorted { lhs, rhs in
                if lhs.defaultSelectionValue == defaultMLXModel { return true }
                if rhs.defaultSelectionValue == defaultMLXModel { return false }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var selectedDefaultMLXDescriptor: MLXModelDescriptor? {
        installedModelDescriptors.first(where: { $0.defaultSelectionValue == defaultMLXModel })
            ?? descriptor(for: defaultMLXModel)
    }

    private var isUsingDownloadedDefaultMLXModel: Bool {
        installedModelDescriptors.contains(where: { $0.defaultSelectionValue == defaultMLXModel })
    }

    private var defaultMLXPickerSelection: Binding<String> {
        Binding(
            get: { isUsingDownloadedDefaultMLXModel ? defaultMLXModel : customMLXSelectionTag },
            set: { newValue in
                guard newValue != customMLXSelectionTag else { return }
                defaultMLXModel = newValue
            }
        )
    }

    private var customDefaultDisclosure: Binding<Bool> {
        Binding(
            get: { showCustomDefaultMLXInput || !isUsingDownloadedDefaultMLXModel || installedModels.isEmpty },
            set: { showCustomDefaultMLXInput = $0 }
        )
    }

    private var recommendedModelDescriptors: [MLXModelDescriptor] {
        catalogPresets.compactMap { descriptor(for: $0.modelIdentifier) }
    }

    private var customModelSource: ManagedMLXInstallSource? {
        LocalProviderInstaller.installSource(from: customModelInput)
    }

    private var customModelValidation: (text: String, isError: Bool) {
        let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("Accepts Hugging Face repo ids, Hugging Face URLs, and direct archive URLs.", false)
        }

        guard let customModelSource else {
            return ("Enter a Hugging Face repo id, a Hugging Face URL, or an archive URL ending in .zip, .tar, .tar.gz, or .tgz.", true)
        }

        switch customModelSource.kind {
        case .modelIdentifier:
            return ("Ready to download from a Hugging Face repo id.", false)
        case .huggingFaceURL:
            return ("Ready to download from a Hugging Face URL.", false)
        case .archiveURL:
            return ("Ready to import this archive into Odyssey’s managed MLX library.", false)
        }
    }

    private var reloadToken: String {
        [sidecarPath, localAgentHostPathOverride, mlxRunnerPathOverride, dataDirectory, defaultMLXModel].joined(separator: "|")
    }

    var body: some View {
        Form {
            cloudAndDefaultModelsSection
            localMLXSetupSection
            recommendedMLXLibrarySection
            installedMLXModelsSection
        }
        .formStyle(.grouped)
        .settingsDetailLayout()
        .task(id: reloadToken) {
            await refreshCatalog()
        }
        .alert("Delete downloaded model?", isPresented: deleteConfirmationPresented, presenting: deleteConfirmationModel) { model in
            Button("Cancel", role: .cancel) {
                deleteConfirmationModel = nil
            }
            Button("Delete", role: .destructive) {
                deleteManagedModel(model)
            }
        } message: { model in
            Text(deleteConfirmationMessage(for: model))
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { deleteConfirmationModel != nil },
            set: { if !$0 { deleteConfirmationModel = nil } }
        )
    }

    private var cloudAndDefaultModelsSection: some View {
        Section("Cloud & Default Models") {
            modelSurface {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose defaults and local-model fallbacks.")
                        .font(.headline)
                    Text("This keeps cloud providers and your default local MLX model in one place without changing the rest of session behavior.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Default Provider", selection: selectedProvider) {
                ForEach([ProviderSelection.claude, ProviderSelection.codex, ProviderSelection.foundation, ProviderSelection.mlx]) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .xrayId("settings.models.defaultProviderPicker")

            Picker("Default Claude Model", selection: selectedClaudeModel) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            .xrayId("settings.models.defaultClaudeModelPicker")

            Picker("Default Codex Model", selection: selectedCodexModel) {
                ForEach(CodexModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            .xrayId("settings.models.defaultCodexModelPicker")

            Picker("Default Foundation Model", selection: selectedFoundationModel) {
                ForEach(FoundationModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            .xrayId("settings.models.defaultFoundationModelPicker")

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Choose your default local model")
                        .font(.headline)
                    Spacer()
                    if !installedModels.isEmpty {
                        Text("\(installedModels.count) downloaded")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if installedModels.isEmpty {
                    modelSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Download a model below to make it selectable here.")
                                .font(.subheadline.weight(.semibold))
                            Text("Once a managed MLX model is installed, it appears here as a simple default choice.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Picker("MLX Default", selection: defaultMLXPickerSelection) {
                        ForEach(installedModelDescriptors) { descriptor in
                            Text(pickerLabel(for: descriptor)).tag(descriptor.defaultSelectionValue)
                        }
                        Text("Custom repo id or local path").tag(customMLXSelectionTag)
                    }
                    .xrayId("settings.models.defaultMLXModelPicker")

                    Text("This dropdown only lists MLX models already downloaded on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let descriptor = selectedDefaultMLXDescriptor {
                    modelDetailCard(
                        descriptor,
                        badgeText: defaultMLXPickerSelection.wrappedValue == customMLXSelectionTag ? "Custom Default" : "Current Default",
                        badgeColor: .accentColor,
                        identifier: "settings.models.currentDefaultMLXModel"
                    )
                }

                DisclosureGroup("Use a custom MLX model id or local path", isExpanded: customDefaultDisclosure) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("mlx-community/Qwen3-4B-Instruct-2507-4bit or /path/to/model", text: $defaultMLXModel)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("settings.models.defaultMLXModelField")

                        Text("Downloaded models are easier to manage from Odyssey. Use a custom repo id or local path only when you need something outside the managed library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var localMLXSetupSection: some View {
        Section("Local MLX Setup") {
            VStack(alignment: .leading, spacing: 12) {
                modelSurface {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Local providers run fully on this Mac.")
                            .font(.headline)
                        Text("MLX uses the managed runner plus the models you download below. Developer overrides still live in the Developer tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsStatusRow(
                    title: "Local Host",
                    summary: localProviderReport.hostSummary,
                    available: localProviderReport.hostBinaryPath != nil || localProviderReport.packagePath != nil,
                    identifier: "settings.models.localProviders.hostStatus"
                )
                settingsStatusRow(
                    title: "Foundation Models",
                    summary: localProviderReport.foundationSummary,
                    available: localProviderReport.foundationAvailable,
                    identifier: "settings.models.localProviders.foundationStatus"
                )
                settingsStatusRow(
                    title: "MLX",
                    summary: localProviderReport.mlxSummary,
                    available: localProviderReport.mlxAvailable,
                    identifier: "settings.models.localProviders.mlxStatus"
                )

                if localProviderReport.mlxRunnerPath == nil {
                    modelSurface {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Finish MLX Setup")
                                .font(.headline)

                            Text("Odyssey can install the local MLX runtime and keep downloaded models in its managed cache automatically.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(localProviderReport.mlxDownloadDirectory)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .xrayId("settings.models.mlxDownloadDirectory")

                            HStack {
                                Button(isInstallingMLXRunner ? "Installing MLX Support…" : "Install MLX Support") {
                                    installMLXRunner()
                                }
                                .disabled(isInstallingMLXRunner)
                                .xrayId("settings.models.installMLXRunnerButton")

                                Button("Open Cache in Finder") {
                                    openPathInFinder(localProviderReport.mlxDownloadDirectory)
                                }
                                .xrayId("settings.models.openMLXCacheButton")
                            }
                        }
                    }
                }
            }
        }
    }

    private var recommendedMLXLibrarySection: some View {
        Section("Recommended MLX Library") {
            VStack(alignment: .leading, spacing: 16) {
                modelSurface {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended Downloads")
                            .font(.headline)
                        Text("Pick one model that matches how you want to work.")
                            .font(.subheadline.weight(.medium))
                        Text("Each card calls out size, download cost, best use, and whether it’s a good fit for autonomous agent work.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(recommendedModelDescriptors) { descriptor in
                    recommendedModelCard(descriptor)
                }

                modelSurface {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add from URL")
                            .font(.headline)
                        HStack {
                            TextField("https://huggingface.co/owner/model or https://host/model.tar.gz or owner/model", text: $customModelInput)
                                .textFieldStyle(.roundedBorder)
                                .xrayId("settings.models.customMLXModelField")
                            Button(installingModelId == "__custom__" ? "Adding…" : "Add") {
                                installCustomModel()
                            }
                            .disabled(customModelSource == nil || installingModelId != nil)
                            .xrayId("settings.models.installCustomMLXModelButton")
                        }
                        Text(customModelValidation.text)
                            .font(.caption)
                            .foregroundStyle(customModelValidation.isError ? .red : .secondary)
                    }
                }
            }

            if isLoadingCatalog {
                ProgressView("Refreshing MLX model library…")
                    .xrayId("settings.models.loadingCatalog")
            }

            if let catalogMessage {
                Text(catalogMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .xrayId("settings.models.catalogMessage")
            }
        }
    }

    private var installedMLXModelsSection: some View {
        Section("Installed MLX Models") {
            VStack(alignment: .leading, spacing: 10) {
                if installedModels.isEmpty {
                    modelSurface {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No managed MLX models are installed yet.")
                                .font(.subheadline.weight(.semibold))
                            Text("Download or import a model above and it will appear here with smoke test, reveal, and delete actions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .xrayId("settings.models.noInstalledModels")
                    }
                } else {
                    ForEach(installedModelDescriptors) { descriptor in
                        installedModelCard(descriptor)
                    }
                }
            }
        }
    }

    private func descriptor(for modelIdentifier: String, installedModel: ManagedInstalledMLXModel? = nil) -> MLXModelDescriptor? {
        let trimmedIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else { return nil }

        let resolvedInstalledModel = installedModel ?? installedModelLookup[trimmedIdentifier]
        let selectionValue = defaultSelectionValue(for: resolvedInstalledModel, modelIdentifier: trimmedIdentifier)
        if let preset = presetLookup[trimmedIdentifier] {
            return MLXModelDescriptor(
                id: trimmedIdentifier,
                title: preset.label,
                modelIdentifier: trimmedIdentifier,
                defaultSelectionValue: selectionValue,
                summary: preset.summary,
                parameterSize: preset.parameterSize,
                downloadSize: preset.downloadSize,
                bestFor: preset.bestFor,
                agentSuitability: preset.agentSuitability,
                recommended: preset.recommended,
                isInstalled: resolvedInstalledModel != nil,
                managedPath: resolvedInstalledModel?.managedPath ?? resolvedInstalledModel?.downloadDirectory,
                sourceURL: resolvedInstalledModel?.sourceURL
            )
        }

        return MLXModelDescriptor(
            id: trimmedIdentifier,
            title: inferredMLXModelTitle(from: trimmedIdentifier),
            modelIdentifier: trimmedIdentifier,
            defaultSelectionValue: selectionValue,
            summary: summary(for: resolvedInstalledModel),
            parameterSize: inferredParameterSize(from: trimmedIdentifier),
            downloadSize: "Varies",
            bestFor: "Use when you need a repo id or archive outside Odyssey’s curated list.",
            agentSuitability: "Unknown agent fit",
            recommended: false,
            isInstalled: resolvedInstalledModel != nil,
            managedPath: resolvedInstalledModel?.managedPath ?? resolvedInstalledModel?.downloadDirectory,
            sourceURL: resolvedInstalledModel?.sourceURL
        )
    }

    private func pickerLabel(for descriptor: MLXModelDescriptor) -> String {
        if descriptor.parameterSize.isEmpty {
            return descriptor.title
        }
        return "\(descriptor.title) • \(descriptor.parameterSize)"
    }

    private func inferredMLXModelTitle(from modelIdentifier: String) -> String {
        let tail = modelIdentifier.split(separator: "/").last.map(String.init) ?? modelIdentifier
        return tail
            .replacingOccurrences(of: "-4bit", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func inferredParameterSize(from modelIdentifier: String) -> String {
        let components = modelIdentifier.split(separator: "/").last.map(String.init) ?? modelIdentifier
        guard let match = components.range(of: #"\d+(\.\d+)?B"#, options: .regularExpression) else {
            return "Custom size"
        }
        return "\(components[match]) params"
    }

    @ViewBuilder
    private func modelSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func metadataPills(for descriptor: MLXModelDescriptor) -> some View {
        HStack(spacing: 8) {
            metadataPill(descriptor.parameterSize)
            metadataPill(descriptor.downloadSize)
            metadataPill(descriptor.agentSuitability)
        }
    }

    @ViewBuilder
    private func metadataPill(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.10), in: Capsule())
        }
    }

    @ViewBuilder
    private func modelDetailCard(
        _ descriptor: MLXModelDescriptor,
        badgeText: String,
        badgeColor: Color,
        identifier: String
    ) -> some View {
        modelSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(descriptor.title)
                        .font(.headline)
                    Text(badgeText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor.opacity(0.12), in: Capsule())
                }
                Text(descriptor.modelIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                metadataPills(for: descriptor)
                Text(descriptor.summary)
                    .font(.subheadline)
                Text("Best for: \(descriptor.bestFor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .xrayId(identifier)
    }

    @ViewBuilder
    private func recommendedModelCard(_ descriptor: MLXModelDescriptor) -> some View {
        modelSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(descriptor.title)
                        .font(.headline)
                    if descriptor.recommended {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    if descriptor.isInstalled {
                        Text("Downloaded")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                    if descriptor.modelIdentifier == defaultMLXModel {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }

                Text(descriptor.modelIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                metadataPills(for: descriptor)

                Text(descriptor.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Best for: \(descriptor.bestFor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(installingModelId == descriptor.modelIdentifier ? "Downloading…" : (descriptor.isInstalled ? "Downloaded" : "Download")) {
                        installManagedModel(descriptor.modelIdentifier)
                    }
                    .disabled(installingModelId != nil || descriptor.isInstalled)
                    .xrayId("settings.models.downloadPreset.\(descriptor.modelIdentifier.replacingOccurrences(of: "/", with: "-"))")

                    Button("Set as Default") {
                        defaultMLXModel = descriptor.modelIdentifier
                    }
                    .xrayId("settings.models.setDefaultPreset.\(descriptor.modelIdentifier.replacingOccurrences(of: "/", with: "-"))")
                }
            }
        }
        .xrayId("settings.models.presetCard.\(descriptor.modelIdentifier.replacingOccurrences(of: "/", with: "-"))")
    }

    @ViewBuilder
    private func installedModelCard(_ descriptor: MLXModelDescriptor) -> some View {
        modelSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(descriptor.title)
                        .font(.headline)
                    if descriptor.defaultSelectionValue == defaultMLXModel {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }

                Text(descriptor.modelIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                metadataPills(for: descriptor)

                Text(descriptor.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Best for: \(descriptor.bestFor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let managedPath = descriptor.managedPath {
                    Text(managedPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let sourceURL = descriptor.sourceURL {
                    Text(sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Set as Default") {
                        defaultMLXModel = descriptor.defaultSelectionValue
                    }
                    .xrayId("settings.models.setDefaultInstalled.\(descriptor.modelIdentifier.replacingOccurrences(of: "/", with: "-"))")

                    Button(smokeTestingModelId == descriptor.id ? "Testing…" : "Smoke Test") {
                        if let installedModel = installedModelLookup[descriptor.modelIdentifier] {
                            smokeTestManagedModel(installedModel, descriptor: descriptor)
                        }
                    }
                    .disabled(smokeTestingModelId != nil)
                    .xrayId("settings.models.smokeTestInstalled.\(descriptor.modelIdentifier.replacingOccurrences(of: "/", with: "-"))")

                    if let revealPath = descriptor.managedPath {
                        Button("Reveal") {
                            openPathInFinder(revealPath)
                        }
                        .xrayId("settings.models.revealInstalled.\(descriptor.modelIdentifier.replacingOccurrences(of: "/", with: "-"))")
                    }

                    Button(deletingModelId == descriptor.id ? "Deleting…" : "Delete") {
                        if let installedModel = installedModelLookup[descriptor.modelIdentifier] {
                            deleteConfirmationModel = installedModel
                        }
                    }
                    .disabled(deletingModelId != nil)
                    .foregroundStyle(.red)
                    .xrayId("settings.models.deleteInstalled.\(descriptor.modelIdentifier.replacingOccurrences(of: "/", with: "-"))")
                }

                if let smokeTestResult = smokeTestResults[descriptor.modelIdentifier] {
                    smokeTestResultView(smokeTestResult)
                }
            }
        }
        .xrayId("settings.models.installedCard.\(descriptor.modelIdentifier.replacingOccurrences(of: "/", with: "-"))")
    }

    private func refreshCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }

        do {
            modelsCatalog = try await LocalProviderInstaller.listMLXModels(
                dataDirectoryPath: dataDirectory,
                bundleResourcePath: Bundle.main.resourcePath,
                currentDirectoryPath: FileManager.default.currentDirectoryPath,
                projectRootOverride: sidecarPath.isEmpty ? nil : sidecarPath,
                hostOverride: localAgentHostPathOverride.isEmpty ? nil : localAgentHostPathOverride,
                runnerOverride: mlxRunnerPathOverride.isEmpty ? nil : mlxRunnerPathOverride
            )
            catalogMessage = nil
        } catch {
            modelsCatalog = ManagedMLXModelsCatalog(
                downloadDirectory: localProviderReport.mlxDownloadDirectory,
                manifestPath: LocalProviderInstaller.managedMLXManifestPath(dataDirectoryPath: dataDirectory),
                runnerPath: localProviderReport.mlxRunnerPath,
                presets: LocalProviderInstaller.recommendedMLXPresets(),
                installed: localProviderReport.installedMLXModels
            )
            catalogMessage = error.localizedDescription
        }
    }

    private func installMLXRunner() {
        isInstallingMLXRunner = true
        catalogMessage = "Downloading and building the MLX runner…"

        Task {
            do {
                let installedPath = try await LocalProviderInstaller.installMLXRunner(dataDirectoryPath: dataDirectory)
                await MainActor.run {
                    isInstallingMLXRunner = false
                    catalogMessage = "Installed MLX runner at \(installedPath)."
                    mlxRunnerPathOverride = ""
                }
                await refreshCatalog()
            } catch {
                await MainActor.run {
                    isInstallingMLXRunner = false
                    catalogMessage = error.localizedDescription
                }
            }
        }
    }

    private func installCustomModel() {
        installManagedModel(customModelInput, installToken: "__custom__")
    }

    private func installManagedModel(_ modelIdentifier: String, installToken: String? = nil) {
        let trimmed = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        installingModelId = installToken ?? trimmed
        catalogMessage = "Adding \(trimmed)…"

        Task {
            do {
                let result = try await LocalProviderInstaller.installMLXModel(
                    modelIdentifier: trimmed,
                    dataDirectoryPath: dataDirectory,
                    bundleResourcePath: Bundle.main.resourcePath,
                    currentDirectoryPath: FileManager.default.currentDirectoryPath,
                    projectRootOverride: sidecarPath.isEmpty ? nil : sidecarPath,
                    hostOverride: localAgentHostPathOverride.isEmpty ? nil : localAgentHostPathOverride,
                    runnerOverride: mlxRunnerPathOverride.isEmpty ? nil : mlxRunnerPathOverride
                )
                await MainActor.run {
                    installingModelId = nil
                    customModelInput = ""
                    let verb = result.alreadyInstalled ? "Already installed" : "Installed"
                    catalogMessage = "\(verb) \(result.modelIdentifier) in \(result.downloadDirectory)."
                }
                await refreshCatalog()
            } catch {
                await MainActor.run {
                    installingModelId = nil
                    catalogMessage = error.localizedDescription
                }
            }
        }
    }

    private func smokeTestManagedModel(_ model: ManagedInstalledMLXModel, descriptor: MLXModelDescriptor) {
        smokeTestingModelId = model.id
        catalogMessage = "Testing \(descriptor.title)…"

        Task {
            do {
                let result = try await LocalProviderInstaller.smokeTestMLXModel(
                    modelReference: descriptor.managedPath ?? descriptor.modelIdentifier,
                    dataDirectoryPath: dataDirectory,
                    bundleResourcePath: Bundle.main.resourcePath,
                    currentDirectoryPath: FileManager.default.currentDirectoryPath,
                    projectRootOverride: sidecarPath.isEmpty ? nil : sidecarPath,
                    hostOverride: localAgentHostPathOverride.isEmpty ? nil : localAgentHostPathOverride,
                    runnerOverride: mlxRunnerPathOverride.isEmpty ? nil : mlxRunnerPathOverride
                )
                await MainActor.run {
                    smokeTestingModelId = nil
                    smokeTestResults[model.modelIdentifier] = result
                    catalogMessage = result.success ? "Smoke test passed for \(descriptor.title)." : (result.errorMessage ?? "Smoke test failed.")
                }
            } catch {
                await MainActor.run {
                    smokeTestingModelId = nil
                    smokeTestResults[model.modelIdentifier] = ManagedMLXSmokeTestResult(
                        modelReference: descriptor.managedPath ?? descriptor.modelIdentifier,
                        durationSeconds: 0,
                        success: false,
                        outputPreview: nil,
                        errorMessage: error.localizedDescription
                    )
                    catalogMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteManagedModel(_ model: ManagedInstalledMLXModel) {
        deletingModelId = model.id
        catalogMessage = "Deleting \(model.modelIdentifier)…"

        Task {
            do {
                let currentSelectionValue = defaultSelectionValue(for: model, modelIdentifier: model.modelIdentifier)
                let result = try await LocalProviderInstaller.deleteMLXModel(
                    modelIdentifier: model.modelIdentifier,
                    dataDirectoryPath: dataDirectory,
                    bundleResourcePath: Bundle.main.resourcePath,
                    currentDirectoryPath: FileManager.default.currentDirectoryPath,
                    projectRootOverride: sidecarPath.isEmpty ? nil : sidecarPath,
                    hostOverride: localAgentHostPathOverride.isEmpty ? nil : localAgentHostPathOverride
                )
                await MainActor.run {
                    deletingModelId = nil
                    deleteConfirmationModel = nil
                    smokeTestResults.removeValue(forKey: model.modelIdentifier)
                    if defaultMLXModel == currentSelectionValue {
                        defaultMLXModel = AppSettings.defaultMLXModel
                    }
                    let verb = result.alreadyRemoved ? "Already removed" : "Removed"
                    catalogMessage = "\(verb) \(result.modelIdentifier)."
                }
                await refreshCatalog()
            } catch {
                await MainActor.run {
                    deletingModelId = nil
                    deleteConfirmationModel = nil
                    catalogMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func smokeTestResultView(_ result: ManagedMLXSmokeTestResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(result.success ? "Passed" : "Failed")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((result.success ? Color.green : Color.red).opacity(0.12), in: Capsule())
                Text(String(format: "%.1fs", result.durationSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let outputPreview = result.outputPreview, !outputPreview.isEmpty {
                Text("Preview: \"\(outputPreview)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = result.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteConfirmationMessage(for model: ManagedInstalledMLXModel) -> String {
        var parts = ["Delete \(model.modelIdentifier)?"]
        if let managedPath = model.managedPath {
            parts.append(managedPath)
        }
        if defaultSelectionValue(for: model, modelIdentifier: model.modelIdentifier) == defaultMLXModel {
            parts.append("This is your current MLX default. Odyssey will fall back to \(AppSettings.defaultMLXModel).")
        }
        return parts.joined(separator: "\n\n")
    }

    private func defaultSelectionValue(for installedModel: ManagedInstalledMLXModel?, modelIdentifier: String) -> String {
        guard let installedModel,
              shouldUseManagedPathAsDefault(for: installedModel),
              let managedPath = installedModel.managedPath else {
            return modelIdentifier
        }
        return managedPath
    }

    private func shouldUseManagedPathAsDefault(for installedModel: ManagedInstalledMLXModel) -> Bool {
        guard let sourceURL = installedModel.sourceURL,
              let url = URL(string: sourceURL) else {
            return false
        }
        let host = url.host?.lowercased()
        return !["huggingface.co", "www.huggingface.co", "hf.co"].contains(host ?? "")
    }

    private func summary(for installedModel: ManagedInstalledMLXModel?) -> String {
        guard let sourceURL = installedModel?.sourceURL,
              let url = URL(string: sourceURL) else {
            return "Custom MLX model selection."
        }
        let host = url.host?.lowercased()
        if ["huggingface.co", "www.huggingface.co", "hf.co"].contains(host ?? "") {
            return "Downloaded from a custom Hugging Face repo."
        }
        return "Imported from a model archive URL."
    }

    private func openPathInFinder(_ path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath))
    }

    @ViewBuilder
    private func settingsStatusRow(title: String, summary: String, available: Bool, identifier: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(available ? .green : .orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .xrayId(identifier)
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
        .settingsDetailLayout()
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

private struct ConnectorsSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Connection.displayName) private var connections: [Connection]
    @AppStorage(AppSettings.connectorBrokerBaseURLKey, store: AppSettings.store) private var connectorBrokerBaseURL = ""
    @AppStorage(AppSettings.xClientIdKey, store: AppSettings.store) private var xClientId = ""
    @AppStorage(AppSettings.linkedinClientIdKey, store: AppSettings.store) private var linkedinClientId = ""
    @State private var editingProvider: ConnectionProvider?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Setup") {
                Text("Set the provider app details here once, then use Connect on each service. Manual tokens are tucked into Advanced only for fallback cases.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .xrayId("settings.connectors.setupSummary")
            }

            Section("Brokered Connectors") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Broker Base URL")
                    TextField("https://broker.example.com/", text: $connectorBrokerBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .xrayId("settings.connectors.brokerURL")
                    Text("Used for Slack, Facebook, and WhatsApp. Once configured, those providers should connect with one click.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Native OAuth Apps") {
                providerSettingField(
                    title: "X Client ID",
                    text: $xClientId,
                    callbackURL: ConnectorCatalog.callbackURL(for: .x),
                    xrayId: "settings.connectors.xClientId"
                )

                providerSettingField(
                    title: "LinkedIn Client ID",
                    text: $linkedinClientId,
                    callbackURL: ConnectorCatalog.callbackURL(for: .linkedin),
                    xrayId: "settings.connectors.linkedinClientId"
                )
            }

            Section("Available Connectors") {
                ForEach(ConnectionProvider.allCases) { provider in
                    ConnectorRowView(
                        provider: provider,
                        connection: connection(for: provider),
                        missingConfiguration: ConnectorCatalog.missingConfiguration(for: provider),
                        onConfigure: { editingProvider = provider },
                        onConnect: { startAuth(for: provider) },
                        onTest: { test(provider: provider) },
                        onRevoke: { revoke(provider: provider) }
                    )
                }
            }

            if let errorMessage {
                Section("Connector Status") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .xrayId("settings.connectors.error")
                }
            }
        }
        .formStyle(.grouped)
        .settingsDetailLayout()
        .sheet(item: $editingProvider) { provider in
            ConnectorEditorSheet(
                provider: provider,
                existingConnection: connection(for: provider)
            )
            .environmentObject(appState)
        }
    }

    @ViewBuilder
    private func providerSettingField(
        title: String,
        text: Binding<String>,
        callbackURL: String,
        xrayId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            TextField("Paste the provider client ID", text: text)
                .textFieldStyle(.roundedBorder)
                .xrayId(xrayId)
            Text("Callback URL: \(callbackURL)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func connection(for provider: ConnectionProvider) -> Connection? {
        ConnectorService.providerConnection(for: provider, in: connections)
    }

    private func startAuth(for provider: ConnectionProvider) {
        do {
            try ConnectorService.beginAuth(provider: provider, in: modelContext, appState: appState)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func test(provider: ConnectionProvider) {
        guard let connection = connection(for: provider) else { return }
        appState.sendToSidecar(.connectorTest(connectionId: connection.id.uuidString))
    }

    private func revoke(provider: ConnectionProvider) {
        guard let connection = connection(for: provider) else { return }
        ConnectorService.revoke(connection, in: modelContext, appState: appState)
    }
}

private struct ConnectorRowView: View {
    let provider: ConnectionProvider
    let connection: Connection?
    let missingConfiguration: [String]
    let onConfigure: () -> Void
    let onConnect: () -> Void
    let onTest: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label(provider.displayName, systemImage: provider.iconName)
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .xrayId("settings.connectors.status.\(provider.rawValue)")
            }

            if let connection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.displayName)
                    Text("\(connection.authMode.displayName) · \(connection.writePolicy.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !connection.grantedScopes.isEmpty {
                        Text(connection.grantedScopes.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let accountHandle = connection.accountHandle, !accountHandle.isEmpty {
                        Text("Account: \(accountHandle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let auditSummary = connection.auditSummary, !auditSummary.isEmpty {
                        Text(auditSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let statusMessage = connection.statusMessage, !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(ConnectorCatalog.definition(for: provider).setupSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !missingConfiguration.isEmpty {
                Text("Needs setup: \(missingConfiguration.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Configure") {
                    onConfigure()
                }
                .xrayId("settings.connectors.configureButton.\(provider.rawValue)")

                Button(connection == nil ? "Connect" : "Reconnect") {
                    onConnect()
                }
                .disabled(!missingConfiguration.isEmpty)
                .xrayId("settings.connectors.connectButton.\(provider.rawValue)")

                Button("Test") {
                    onTest()
                }
                .disabled(connection == nil)
                .xrayId("settings.connectors.testButton.\(provider.rawValue)")

                Button("Revoke") {
                    onRevoke()
                }
                .disabled(connection == nil)
                .foregroundStyle(.red)
                .xrayId("settings.connectors.revokeButton.\(provider.rawValue)")

                Link("Docs", destination: ConnectorCatalog.definition(for: provider).docsURL)
                    .xrayId("settings.connectors.docsLink.\(provider.rawValue)")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .xrayId("settings.connectors.row.\(provider.rawValue)")
    }

    private var statusText: String {
        connection?.status.displayName ?? "Not Installed"
    }

    private var statusColor: Color {
        switch connection?.status {
        case .connected: return .green
        case .authorizing: return .orange
        case .needsAttention: return .yellow
        case .revoked: return .gray
        case .failed: return .red
        case .disconnected, .none: return .secondary
        }
    }
}

private struct ConnectorEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    let provider: ConnectionProvider
    let existingConnection: Connection?

    @State private var displayName: String
    @State private var scopesText: String
    @State private var authMode: ConnectionAuthMode
    @State private var writePolicy: ConnectionWritePolicy
    @State private var accountId: String
    @State private var accountHandle: String
    @State private var accountMetadataJSON: String
    @State private var brokerReference: String
    @State private var accessToken: String
    @State private var refreshToken: String
    @State private var tokenType: String
    @State private var expiresAt: Date
    @State private var hasExpiry: Bool
    @State private var showAdvanced = false
    @State private var errorMessage: String?

    init(provider: ConnectionProvider, existingConnection: Connection?) {
        self.provider = provider
        self.existingConnection = existingConnection

        let definition = ConnectorCatalog.definition(for: provider)
        let storedCredentials = existingConnection.flatMap { try? ConnectionVault.loadCredentials(connectionId: $0.id) }

        _displayName = State(initialValue: existingConnection?.displayName ?? provider.displayName)
        _scopesText = State(initialValue: (existingConnection?.grantedScopes ?? definition.defaultScopes).joined(separator: ", "))
        _authMode = State(initialValue: existingConnection?.authMode ?? definition.authMode)
        _writePolicy = State(initialValue: existingConnection?.writePolicy ?? .requireApproval)
        _accountId = State(initialValue: existingConnection?.accountId ?? "")
        _accountHandle = State(initialValue: existingConnection?.accountHandle ?? "")
        _accountMetadataJSON = State(initialValue: existingConnection?.accountMetadataJSON ?? "")
        _brokerReference = State(initialValue: storedCredentials?.brokerReference ?? existingConnection?.brokerReference ?? "")
        _accessToken = State(initialValue: storedCredentials?.accessToken ?? "")
        _refreshToken = State(initialValue: storedCredentials?.refreshToken ?? "")
        _tokenType = State(initialValue: storedCredentials?.tokenType ?? "Bearer")
        _expiresAt = State(initialValue: storedCredentials?.expiresAt ?? Date())
        _hasExpiry = State(initialValue: storedCredentials?.expiresAt != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existingConnection == nil ? "Install \(provider.displayName)" : "Edit \(provider.displayName)")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .xrayId("settings.connectors.editor.doneButton.\(provider.rawValue)")
            }
            .padding()

            Form {
                Section("Connection") {
                    Text(ConnectorCatalog.definition(for: provider).setupSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Display Name", text: $displayName)
                        .xrayId("settings.connectors.editor.displayName.\(provider.rawValue)")

                    Picker("Auth Mode", selection: $authMode) {
                        ForEach(ConnectionAuthMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .xrayId("settings.connectors.editor.authMode.\(provider.rawValue)")

                    Picker("Write Policy", selection: $writePolicy) {
                        ForEach(ConnectionWritePolicy.allCases, id: \.rawValue) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .xrayId("settings.connectors.editor.writePolicy.\(provider.rawValue)")

                    TextField("Scopes (comma-separated)", text: $scopesText, axis: .vertical)
                        .lineLimit(2...4)
                        .xrayId("settings.connectors.editor.scopes.\(provider.rawValue)")
                }

                Section("Advanced") {
                    DisclosureGroup("Manual account and credential overrides", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Use this only when automatic auth is unavailable. Most users should click Connect instead.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("Account ID", text: $accountId)
                                .xrayId("settings.connectors.editor.accountId.\(provider.rawValue)")
                            TextField("Account Handle", text: $accountHandle)
                                .xrayId("settings.connectors.editor.accountHandle.\(provider.rawValue)")
                            TextField("Account Metadata JSON", text: $accountMetadataJSON, axis: .vertical)
                                .lineLimit(2...5)
                                .xrayId("settings.connectors.editor.accountMetadata.\(provider.rawValue)")
                            TextField("Broker Reference", text: $brokerReference)
                                .xrayId("settings.connectors.editor.brokerReference.\(provider.rawValue)")

                            SecureField("Access Token", text: $accessToken)
                                .xrayId("settings.connectors.editor.accessToken.\(provider.rawValue)")
                            SecureField("Refresh Token", text: $refreshToken)
                                .xrayId("settings.connectors.editor.refreshToken.\(provider.rawValue)")
                            TextField("Token Type", text: $tokenType)
                                .xrayId("settings.connectors.editor.tokenType.\(provider.rawValue)")
                            Toggle("Has Expiry", isOn: $hasExpiry)
                                .xrayId("settings.connectors.editor.hasExpiry.\(provider.rawValue)")
                            if hasExpiry {
                                DatePicker("Expires At", selection: $expiresAt)
                                    .xrayId("settings.connectors.editor.expiresAt.\(provider.rawValue)")
                            }
                            Text("Tokens are stored in macOS Keychain and never in SwiftData.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .xrayId("settings.connectors.editor.cancelButton.\(provider.rawValue)")

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .xrayId("settings.connectors.editor.saveButton.\(provider.rawValue)")
            }
            .padding()
        }
        .frame(width: 520, height: 640)
    }

    private func save() {
        let scopes = scopesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        do {
            let connection = ConnectorService.upsertConnection(provider: provider, in: modelContext)
            let trimmedMetadata = accountMetadataJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            connection.accountMetadataJSON = trimmedMetadata.isEmpty ? nil : trimmedMetadata
            try ConnectorService.saveManualConnection(
                provider: provider,
                displayName: displayName,
                scopes: scopes,
                authMode: authMode,
                writePolicy: writePolicy,
                accountId: accountId,
                accountHandle: accountHandle,
                brokerReference: brokerReference,
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenType: tokenType,
                expiresAt: hasExpiry ? expiresAt : nil,
                in: modelContext,
                appState: appState
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
        .settingsDetailLayout()
    }
}

// MARK: - Developer

private struct DeveloperSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettings.bunPathOverrideKey, store: AppSettings.store) private var bunPathOverride = ""
    @AppStorage(AppSettings.sidecarPathKey, store: AppSettings.store) private var sidecarPath = ""
    @AppStorage(AppSettings.localAgentHostPathOverrideKey, store: AppSettings.store) private var localAgentHostPathOverride = ""
    @AppStorage(AppSettings.mlxRunnerPathOverrideKey, store: AppSettings.store) private var mlxRunnerPathOverride = ""
    @AppStorage(AppSettings.dataDirectoryKey, store: AppSettings.store) private var dataDirectory = AppSettings.defaultDataDirectory
    @AppStorage(AppSettings.logLevelKey, store: AppSettings.store) private var logLevel = AppSettings.defaultLogLevel
    @AppStorage(AppSettings.useLegacyChatChromeKey, store: AppSettings.store) private var useLegacyChatChrome = false
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Agent Host Override")
                    HStack {
                        TextField("Use bundled host when available", text: $localAgentHostPathOverride)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("settings.developer.localAgentHostField")
                        Button("Browse...") {
                            browseExecutablePath(
                                message: "Select the Odyssey local-agent host executable"
                            ) { localAgentHostPathOverride = $0 }
                        }
                        .xrayId("settings.developer.localAgentHostBrowseButton")
                    }
                    Text("Normally the app uses the bundled local-agent host automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("MLX Runner Override")
                    HStack {
                        TextField("Auto-detect llm-tool", text: $mlxRunnerPathOverride)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("settings.developer.mlxRunnerField")
                        Button("Browse...") {
                            browseExecutablePath(
                                message: "Select the MLX runner executable"
                            ) { mlxRunnerPathOverride = $0 }
                        }
                        .xrayId("settings.developer.mlxRunnerBrowseButton")
                    }
                    Text("Leave blank to auto-detect `llm-tool` in PATH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data Directory")
                    HStack {
                        TextField("~/.odyssey", text: $dataDirectory)
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

            Section("UI Experiments") {
                Toggle("Use legacy chat chrome", isOn: $useLegacyChatChrome)
                    .xrayId("settings.developer.useLegacyChatChromeToggle")
                Text("Temporary comparison toggle for the Focus First chat redesign. Turn this on to restore the previous toolbar, header, and composer layout locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .settingsDetailLayout()
    }

    private func browseBunPath() {
        browseExecutablePath(
            message: "Select the Bun executable",
            directoryURL: URL(fileURLWithPath: "/opt/homebrew/bin")
        ) { bunPathOverride = $0 }
    }

    private func browseExecutablePath(
        message: String,
        directoryURL: URL? = nil,
        assign: (String) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.directoryURL = directoryURL
        if panel.runModal() == .OK, let url = panel.url {
            assign(url.path)
        }
    }

    private func browseProjectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the Odyssey project directory"
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

private extension View {
    func settingsDetailLayout() -> some View {
        self
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 1040, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
    }
}

#Preview {
    SettingsView()
}
