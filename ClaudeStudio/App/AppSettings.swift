import SwiftUI
import AppKit

enum AppSettings {
    // MARK: - General
    static let appearanceKey = "claudestudio.appearance"
    static let textSizeKey = "claudestudio.textSize"
    static let defaultModelKey = "claudestudio.defaultModel"
    static let defaultProviderKey = "claudestudio.defaultProvider"
    static let defaultClaudeModelKey = defaultModelKey
    static let defaultCodexModelKey = "claudestudio.defaultCodexModel"
    static let defaultMaxTurnsKey = "claudestudio.defaultMaxTurns"
    static let defaultMaxBudgetKey = "claudestudio.defaultMaxBudget"
    static let autoConnectSidecarKey = "claudestudio.autoConnectSidecar"

    // MARK: - Connection
    static let wsPortKey = "claudestudio.wsPort"
    static let httpPortKey = "claudestudio.httpPort"
    static let bunPathOverrideKey = "claudestudio.bunPathOverride"
    static let sidecarPathKey = "claudestudio.projectPath"

    // MARK: - Instance
    static let instanceWorkingDirectoryKey = "claudestudio.instanceWorkingDirectory"

    // MARK: - Layout
    static let inspectorWidthKey = "claudestudio.inspectorWidth"

    // MARK: - Notifications
    static let notificationsEnabledKey = "claudestudio.notifications.enabled"
    static let notificationSoundEnabledKey = "claudestudio.notifications.sound"

    // MARK: - Chat Display
    static let renderMermaidKey = "claudestudio.chat.renderMermaid"
    static let renderHTMLKey = "claudestudio.chat.renderHTML"
    static let renderDiffsKey = "claudestudio.chat.renderDiffs"
    static let renderTerminalKey = "claudestudio.chat.renderTerminal"
    static let renderAdmonitionsKey = "claudestudio.chat.renderAdmonitions"
    static let renderPDFKey = "claudestudio.chat.renderPDF"
    static let showSessionSummaryKey = "claudestudio.chat.showSessionSummary"
    static let showSuggestionChipsKey = "claudestudio.chat.showSuggestionChips"

    // MARK: - Quick Actions
    static let quickActionUsageOrderKey = "claudestudio.chat.quickActionUsageOrder"
    static let quickActionUsageCountsKey = "claudestudio.chat.quickActionUsageCounts"

    // MARK: - Advanced
    static let dataDirectoryKey = "claudestudio.dataDirectory"
    static let logLevelKey = "claudestudio.logLevel"

    // MARK: - Defaults
    static let defaultWsPort = 9849
    static let defaultHttpPort = 9850
    static let defaultMaxTurns = 30
    static let defaultMaxBudget = 0.0
    static let defaultProvider = ProviderSelection.claude.rawValue
    static let defaultClaudeModel = ClaudeModel.sonnet.rawValue
    static let defaultCodexModel = CodexModel.gpt5Codex.rawValue
    static let defaultTextSize = AppTextSize.standard.rawValue
    static let defaultDataDirectory = "~/.claudestudio"
    static let defaultLogLevel = "info"

    /// Per-instance UserDefaults store for use with `@AppStorage(_:store:)`.
    nonisolated(unsafe) static let store: UserDefaults = InstanceConfig.userDefaults

    static var allKeys: [String] {
        [
            appearanceKey, textSizeKey, defaultProviderKey, defaultClaudeModelKey,
            defaultCodexModelKey, defaultMaxTurnsKey,
            defaultMaxBudgetKey, autoConnectSidecarKey,
            instanceWorkingDirectoryKey,
            wsPortKey, httpPortKey, bunPathOverrideKey, sidecarPathKey,
            notificationsEnabledKey, notificationSoundEnabledKey,
            renderMermaidKey, renderHTMLKey, renderDiffsKey, renderTerminalKey,
            renderAdmonitionsKey, renderPDFKey, showSessionSummaryKey, showSuggestionChipsKey,
            quickActionUsageOrderKey, quickActionUsageCountsKey,
            dataDirectoryKey, logLevelKey,
        ]
    }

    static func resetAll() {
        let defaults = InstanceConfig.userDefaults
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppTextSize: Int, CaseIterable, Identifiable {
    case smaller = -2
    case small = -1
    case standard = 0
    case large = 1
    case larger = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .smaller: "Smaller"
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .smaller: .xSmall
        case .small: .small
        case .standard: .large
        case .large: .xLarge
        case .larger: .xxLarge
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .smaller: 0.85
        case .small: 0.93
        case .standard: 1.0
        case .large: 1.12
        case .larger: 1.24
        }
    }

    var canIncrease: Bool { self != Self.maximum }
    var canDecrease: Bool { self != Self.minimum }

    func increased() -> AppTextSize {
        AppTextSize(rawValue: rawValue + 1) ?? self
    }

    func decreased() -> AppTextSize {
        AppTextSize(rawValue: rawValue - 1) ?? self
    }

    static var minimum: AppTextSize { .smaller }
    static var maximum: AppTextSize { .larger }
}

private struct AppTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var appTextScale: CGFloat {
        get { self[AppTextScaleKey.self] }
        set { self[AppTextScaleKey.self] = newValue }
    }
}

@MainActor
final class AppTextSizeShortcutMonitor {
    static let shared = AppTextSizeShortcutMonitor()

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.command] || flags == [.command, .shift] else {
                return event
            }

            let keys = Set([event.charactersIgnoringModifiers, event.characters].compactMap { $0 })

            if keys.contains("-") {
                Self.update { $0.decreased() }
                return nil
            }

            if keys.contains("0") {
                AppSettings.store.set(AppTextSize.standard.rawValue, forKey: AppSettings.textSizeKey)
                return nil
            }

            if keys.contains("=") || keys.contains("+") {
                Self.update { $0.increased() }
                return nil
            }

            return event
        }
    }

    private static func update(_ transform: (AppTextSize) -> AppTextSize) {
        let rawValue = AppSettings.store.object(forKey: AppSettings.textSizeKey) as? Int ?? AppSettings.defaultTextSize
        let current = AppTextSize(rawValue: rawValue) ?? .standard
        AppSettings.store.set(transform(current).rawValue, forKey: AppSettings.textSizeKey)
    }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-4-6"
    case opus = "claude-opus-4-6"
    case haiku = "claude-haiku-4-5-20251001"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sonnet: "Claude Sonnet 4.6"
        case .opus: "Claude Opus 4.6"
        case .haiku: "Claude Haiku 4.5"
        }
    }
}

enum LogLevel: String, CaseIterable, Identifiable {
    case debug, info, warn, error

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}
