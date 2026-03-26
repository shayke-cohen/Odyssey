import SwiftUI

enum AppSettings {
    // MARK: - General
    static let appearanceKey = "claudestudio.appearance"
    static let defaultModelKey = "claudestudio.defaultModel"
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
    static let defaultModel = "claude-sonnet-4-6"
    static let defaultDataDirectory = "~/.claudestudio"
    static let defaultLogLevel = "info"

    /// Per-instance UserDefaults store for use with `@AppStorage(_:store:)`.
    nonisolated(unsafe) static let store: UserDefaults = InstanceConfig.userDefaults

    static var allKeys: [String] {
        [
            appearanceKey, defaultModelKey, defaultMaxTurnsKey,
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
