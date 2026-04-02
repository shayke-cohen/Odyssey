import Foundation

enum ProviderSelection: String, CaseIterable, Identifiable {
    case system
    case claude
    case codex
    case foundation
    case mlx

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .claude: "Claude"
        case .codex: "Codex"
        case .foundation: "Foundation"
        case .mlx: "MLX"
        }
    }

    var concreteProvider: String? {
        switch self {
        case .system: nil
        case .claude, .codex, .foundation, .mlx: rawValue
        }
    }
}

enum CodexModel: String, CaseIterable, Identifiable {
    case gpt5Codex = "gpt-5-codex"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gpt5Codex: "GPT-5 Codex"
        }
    }
}

struct ModelChoice: Identifiable, Equatable {
    let id: String
    let label: String
}

enum AgentDefaults {
    static let inheritMarker = ProviderSelection.system.rawValue
    static let defaultFreeformSystemPrompt = "You are a helpful assistant. Be concise and clear."

    static func normalizedProviderSelection(_ value: String?) -> ProviderSelection {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case ProviderSelection.claude.rawValue:
            .claude
        case ProviderSelection.codex.rawValue:
            .codex
        case ProviderSelection.foundation.rawValue:
            .foundation
        case ProviderSelection.mlx.rawValue:
            .mlx
        default:
            .system
        }
    }

    static func defaultProvider() -> String {
        normalizedProviderSelection(
            AppSettings.store.string(forKey: AppSettings.defaultProviderKey) ?? AppSettings.defaultProvider
        ).concreteProvider ?? AppSettings.defaultProvider
    }

    static func concreteProvider(from value: String?) -> String {
        normalizedProviderSelection(value).concreteProvider ?? defaultProvider()
    }

    static func defaultModel(for provider: String) -> String {
        switch provider {
        case ProviderSelection.codex.rawValue:
            let stored = AppSettings.store.string(forKey: AppSettings.defaultCodexModelKey)
            let normalized = normalizedModelSelection(stored ?? AppSettings.defaultCodexModel)
            return isModel(normalized, compatibleWith: provider) ? normalized : AppSettings.defaultCodexModel
        case ProviderSelection.foundation.rawValue:
            let stored = AppSettings.store.string(forKey: AppSettings.defaultFoundationModelKey)
            let normalized = normalizedModelSelection(stored ?? AppSettings.defaultFoundationModel)
            return isModel(normalized, compatibleWith: provider) ? normalized : AppSettings.defaultFoundationModel
        case ProviderSelection.mlx.rawValue:
            let stored = AppSettings.store.string(forKey: AppSettings.defaultMLXModelKey)
            let normalized = normalizedModelSelection(stored ?? AppSettings.defaultMLXModel)
            return isModel(normalized, compatibleWith: provider) ? normalized : AppSettings.defaultMLXModel
        default:
            let stored = AppSettings.store.string(forKey: AppSettings.defaultClaudeModelKey)
            let normalized = normalizedModelSelection(stored ?? AppSettings.defaultClaudeModel)
            return isModel(normalized, compatibleWith: ProviderSelection.claude.rawValue)
                ? normalized
                : AppSettings.defaultClaudeModel
        }
    }

    static func normalizedModelSelection(_ value: String?) -> String {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "", "default", "inherit", "system", "provider_default":
            inheritMarker
        case "sonnet":
            ClaudeModel.sonnet.rawValue
        case "opus":
            ClaudeModel.opus.rawValue
        case "haiku":
            ClaudeModel.haiku.rawValue
        default:
            value ?? inheritMarker
        }
    }

    static func resolveEffectiveProvider(
        sessionOverride: String? = nil,
        agentSelection: String? = nil
    ) -> String {
        normalizedProviderSelection(sessionOverride).concreteProvider
            ?? normalizedProviderSelection(agentSelection).concreteProvider
            ?? defaultProvider()
    }

    static func resolveEffectiveModel(
        sessionOverride: String? = nil,
        agentSelection: String? = nil,
        provider: String
    ) -> String {
        let sessionCandidate = explicitModelSelection(from: sessionOverride)
        if let sessionCandidate, isModel(sessionCandidate, compatibleWith: provider) {
            return sessionCandidate
        }

        let agentCandidate = explicitModelSelection(from: agentSelection)
        if let agentCandidate, isModel(agentCandidate, compatibleWith: provider) {
            return agentCandidate
        }

        return defaultModel(for: provider)
    }

    static func isModel(_ model: String, compatibleWith provider: String) -> Bool {
        let normalized = normalizedModelSelection(model)
        if normalized == inheritMarker {
            return true
        }

        switch provider {
        case ProviderSelection.codex.rawValue:
            return CodexModel.allCases.contains { $0.rawValue == normalized }
        case ProviderSelection.foundation.rawValue:
            return FoundationModel.allCases.contains { $0.rawValue == normalized }
        case ProviderSelection.mlx.rawValue:
            return !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return ClaudeModel.allCases.contains { $0.rawValue == normalized }
        }
    }

    static func availableAgentModelChoices(for providerSelection: String) -> [ModelChoice] {
        let selection = normalizedProviderSelection(providerSelection)
        var choices = [ModelChoice(id: inheritMarker, label: selection == .system ? "System Default" : "Default for \(selection.label)")]

        switch selection {
        case .claude:
            choices.append(contentsOf: ClaudeModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        case .codex:
            choices.append(contentsOf: CodexModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        case .foundation:
            choices.append(contentsOf: FoundationModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        case .mlx:
            choices.append(contentsOf: mlxConfiguredModelChoices())
        case .system:
            choices.append(contentsOf: ClaudeModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
            choices.append(contentsOf: CodexModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
            choices.append(contentsOf: FoundationModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
            choices.append(contentsOf: mlxConfiguredModelChoices())
        }

        return choices
    }

    static func availableThreadModelChoices(
        for provider: String,
        inheritLabel: String = "Inherit from Agent"
    ) -> [ModelChoice] {
        var choices = [ModelChoice(id: inheritMarker, label: inheritLabel)]
        switch provider {
        case ProviderSelection.codex.rawValue:
            choices.append(contentsOf: CodexModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        case ProviderSelection.foundation.rawValue:
            choices.append(contentsOf: FoundationModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        case ProviderSelection.mlx.rawValue:
            choices.append(contentsOf: mlxConfiguredModelChoices())
        default:
            choices.append(contentsOf: ClaudeModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        }
        return choices
    }

    static func preferredModelSelection(_ current: String?, providerSelection: String) -> String {
        let normalized = normalizedModelSelection(current)
        let selection = normalizedProviderSelection(providerSelection)
        let choices = availableAgentModelChoices(for: selection.rawValue)
        return choices.contains(where: { $0.id == normalized }) ? normalized : inheritMarker
    }

    static func label(for model: String?) -> String {
        let normalized = normalizedModelSelection(model)
        if normalized == inheritMarker {
            return "System Default"
        }
        if let match = ClaudeModel.allCases.first(where: { $0.rawValue == normalized }) {
            return match.label
        }
        if let match = CodexModel.allCases.first(where: { $0.rawValue == normalized }) {
            return match.label
        }
        if let match = FoundationModel.allCases.first(where: { $0.rawValue == normalized }) {
            return match.label
        }
        if let match = MLXModel.allCases.first(where: { $0.rawValue == normalized }) {
            return match.label
        }
        return model ?? inheritMarker
    }

    static func displayName(forProvider provider: String?) -> String {
        switch concreteProvider(from: provider) {
        case ProviderSelection.codex.rawValue:
            return ProviderSelection.codex.label
        case ProviderSelection.foundation.rawValue:
            return ProviderSelection.foundation.label
        case ProviderSelection.mlx.rawValue:
            return ProviderSelection.mlx.label
        default:
            return ProviderSelection.claude.label
        }
    }

    static func makeFreeformAgentConfig(
        provider: String?,
        model: String?,
        workingDirectory: String,
        systemPrompt: String = defaultFreeformSystemPrompt,
        maxTurns: Int? = 5,
        maxBudget: Double? = nil,
        maxThinkingTokens: Int? = 10000,
        interactive: Bool? = true,
        instancePolicy: String? = nil,
        instancePolicyPoolMax: Int? = nil
    ) -> AgentConfig {
        let resolvedProvider = concreteProvider(from: provider)
        let resolvedModel = {
            let normalized = normalizedModelSelection(model)
            if normalized != inheritMarker, isModel(normalized, compatibleWith: resolvedProvider) {
                return normalized
            }
            return defaultModel(for: resolvedProvider)
        }()

        return AgentConfig(
            name: displayName(forProvider: resolvedProvider),
            systemPrompt: systemPrompt,
            allowedTools: [],
            mcpServers: [],
            provider: resolvedProvider,
            model: resolvedModel,
            maxTurns: maxTurns,
            maxBudget: maxBudget,
            maxThinkingTokens: maxThinkingTokens,
            workingDirectory: workingDirectory,
            skills: [],
            interactive: interactive,
            instancePolicy: instancePolicy,
            instancePolicyPoolMax: instancePolicyPoolMax
        )
    }

    private static func explicitModelSelection(from value: String?) -> String? {
        let normalized = normalizedModelSelection(value)
        return normalized == inheritMarker ? nil : normalized
    }

    private static func mlxConfiguredModelChoices() -> [ModelChoice] {
        let configured = normalizedModelSelection(
            AppSettings.store.string(forKey: AppSettings.defaultMLXModelKey) ?? AppSettings.defaultMLXModel
        )

        guard configured != inheritMarker else {
            return [ModelChoice(id: MLXModel.defaultModel.rawValue, label: MLXModel.defaultModel.label)]
        }

        return [ModelChoice(id: configured, label: "Configured MLX Model (\(configured))")]
    }
}
