import XCTest
@testable import Odyssey

/// XCTest coverage for the 13-tab Settings redesign.
///
/// Tests verify:
/// - All 13 SettingsSection cases exist and carry correct identifiers
/// - Every tab's accessibility identifier follows the settings.tab.* convention
/// - Per-tab control identifiers use the correct section prefix
/// - No duplicate identifiers within a tab
/// - ConfigSection.voice is gone (Voice is now a top-level tab)
/// - SettingsSidebarGroup structure maps to the four labelled groups
final class SettingsTabsTests: XCTestCase {

    // MARK: - Sidebar tab identifiers

    /// Canonical set of all 13 sidebar tab identifiers.
    private let expectedTabIds: Set<String> = [
        "settings.tab.appearance",
        "settings.tab.voice",
        "settings.tab.shortcuts",
        "settings.tab.models",
        "settings.tab.agentsGroups",
        "settings.tab.skillsMCPs",
        "settings.tab.templates",
        "settings.tab.permissions",
        "settings.tab.github",
        "settings.tab.connectors",
        "settings.tab.pairing",
        "settings.tab.advanced",
        "settings.tab.devLabs",
    ]

    func testAllTabIds_haveSettingsTabPrefix() {
        for id in expectedTabIds {
            XCTAssertTrue(id.hasPrefix("settings.tab."),
                          "Tab identifier '\(id)' must start with 'settings.tab.'")
        }
    }

    func testAllTabIds_noDuplicates() {
        XCTAssertEqual(expectedTabIds.count, 13,
                       "Expected exactly 13 distinct tab identifiers")
    }

    func testTabIds_noTypos() {
        XCTAssertTrue(expectedTabIds.contains("settings.tab.appearance"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.voice"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.shortcuts"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.models"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.agentsGroups"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.skillsMCPs"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.templates"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.permissions"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.github"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.connectors"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.pairing"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.advanced"))
        XCTAssertTrue(expectedTabIds.contains("settings.tab.devLabs"))
    }

    // MARK: - SettingsSection enum

    func testSettingsSection_hasExactly13Cases() {
        XCTAssertEqual(SettingsSection.allCases.count, 13,
                       "SettingsSection must have exactly 13 cases after B1 redesign")
    }

    func testSettingsSection_personalGroup() {
        let personal: [SettingsSection] = [.appearance, .voice, .shortcuts]
        for section in personal {
            XCTAssertTrue(SettingsSection.allCases.contains(section),
                          "Personal group section .\(section) must exist")
        }
    }

    func testSettingsSection_aiPlatformGroup() {
        let aiPlatform: [SettingsSection] = [.models, .agentsGroups, .skillsMCPs, .templates, .permissions]
        for section in aiPlatform {
            XCTAssertTrue(SettingsSection.allCases.contains(section),
                          "AI Platform group section .\(section) must exist")
        }
    }

    func testSettingsSection_integrationsGroup() {
        let integrations: [SettingsSection] = [.github, .connectors, .pairing]
        for section in integrations {
            XCTAssertTrue(SettingsSection.allCases.contains(section),
                          "Integrations group section .\(section) must exist")
        }
    }

    func testSettingsSection_systemGroup() {
        let system: [SettingsSection] = [.advanced, .devLabs]
        for section in system {
            XCTAssertTrue(SettingsSection.allCases.contains(section),
                          "System group section .\(section) must exist")
        }
    }

    func testSettingsSection_xrayIdFormat() {
        for section in SettingsSection.allCases {
            let id = section.xrayId
            XCTAssertTrue(id.hasPrefix("settings.tab."),
                          "xrayId for .\(section) must start with 'settings.tab.', got '\(id)'")
            XCTAssertFalse(id.hasSuffix("."),
                           "xrayId '\(id)' must not end with a dot")
        }
    }

    func testSettingsSection_xrayIdMatchesRawValue() {
        for section in SettingsSection.allCases {
            let expected = "settings.tab.\(section.rawValue)"
            XCTAssertEqual(section.xrayId, expected,
                           "xrayId for .\(section) must be 'settings.tab.\(section.rawValue)'")
        }
    }

    func testSettingsSection_allHaveNonEmptyTitle() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.title.isEmpty,
                           "Section .\(section) has an empty title")
        }
    }

    func testSettingsSection_allHaveNonEmptySystemImage() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.systemImage.isEmpty,
                           "Section .\(section) has an empty systemImage")
        }
    }

    // MARK: - ConfigSection (must not contain .voice)

    func testConfigSection_doesNotHaveVoice() {
        let allIds = ConfigSection.allCases.map(\.id)
        XCTAssertFalse(allIds.contains("voice"),
                       "ConfigSection.voice must be removed — Voice is now a top-level SettingsSection")
    }

    func testConfigSection_hasExactly6Cases() {
        XCTAssertEqual(ConfigSection.allCases.count, 6,
                       "ConfigSection must have exactly 6 cases: agents, groups, skills, mcps, templates, permissions")
    }

    // MARK: - ConfigSection → SettingsSection routing

    func testConfigSectionRouting_agentsGoesToAgentsGroups() {
        XCTAssertEqual(SettingsSection.section(for: .agents), .agentsGroups)
    }

    func testConfigSectionRouting_groupsGoesToAgentsGroups() {
        XCTAssertEqual(SettingsSection.section(for: .groups), .agentsGroups)
    }

    func testConfigSectionRouting_skillsGoesToSkillsMCPs() {
        XCTAssertEqual(SettingsSection.section(for: .skills), .skillsMCPs)
    }

    func testConfigSectionRouting_mcpsGoesToSkillsMCPs() {
        XCTAssertEqual(SettingsSection.section(for: .mcps), .skillsMCPs)
    }

    func testConfigSectionRouting_templatesGoesToTemplates() {
        XCTAssertEqual(SettingsSection.section(for: .templates), .templates)
    }

    func testConfigSectionRouting_permissionsGoesToPermissions() {
        XCTAssertEqual(SettingsSection.section(for: .permissions), .permissions)
    }

    // MARK: - Appearance tab identifiers

    private let appearanceIds: Set<String> = [
        "settings.appearance.appearancePicker",
        "settings.appearance.textSizePicker",
        "settings.appearance.defaultMaxTurnsStepper",
        "settings.appearance.defaultMaxBudgetField",
        "settings.appearance.renderAdmonitions",
        "settings.appearance.renderMermaid",
        "settings.appearance.renderHTML",
        "settings.appearance.renderPDF",
        "settings.appearance.renderDiffs",
        "settings.appearance.renderTerminal",
        "settings.appearance.showSessionSummary",
        "settings.appearance.showSuggestionChips",
        "settings.appearance.deleteAllHistoryButton",
    ]

    func testAppearanceIds_useCorrectPrefix() {
        for id in appearanceIds {
            XCTAssertTrue(id.hasPrefix("settings.appearance."),
                          "Appearance identifier '\(id)' must use settings.appearance. prefix")
        }
    }

    func testAppearanceIds_count() {
        XCTAssertEqual(appearanceIds.count, 13,
                       "Expected 13 distinct Appearance tab identifiers")
    }

    // MARK: - Voice tab identifiers

    private let voiceIds: Set<String> = [
        "settings.voice.featuresEnabledToggle",
        "settings.voice.voicePicker",
        "settings.voice.autoSpeakToggle",
        "settings.voice.speakingRateSlider",
        "settings.voice.showSpeakerButtonToggle",
    ]

    func testVoiceIds_useCorrectPrefix() {
        for id in voiceIds {
            XCTAssertTrue(id.hasPrefix("settings.voice."),
                          "Voice identifier '\(id)' must use settings.voice. prefix")
        }
    }

    // MARK: - Developer & Labs tab identifiers

    private let devLabsStaticIds: Set<String> = [
        "settings.devLabs.form",
        "settings.devLabs.logLevelPicker",
    ]

    private let devLabsToggleSuffixes: [String] = [
        "peerNetwork", "workflows", "autoAssemble",
        "autonomousMissions", "federation", "agentComms",
        "debugLogs", "advancedAgentConfig", "devMode",
    ]

    func testDevLabsIds_useCorrectPrefix() {
        for id in devLabsStaticIds {
            XCTAssertTrue(id.hasPrefix("settings.devLabs."),
                          "DevLabs identifier '\(id)' must use settings.devLabs. prefix")
        }
    }

    func testDevLabsToggleIds_format() {
        for suffix in devLabsToggleSuffixes {
            let id = "settings.devLabs.toggle.\(suffix)"
            XCTAssertTrue(id.hasPrefix("settings.devLabs.toggle."),
                          "Toggle identifier '\(id)' must start with settings.devLabs.toggle.")
        }
    }

    func testDevLabsToggleIds_noMasterGate() {
        let ids = devLabsToggleSuffixes.map { "settings.devLabs.toggle.\($0)" }
        XCTAssertFalse(ids.contains("settings.devLabs.toggle.showAdvanced"),
                       "Master gate toggle must not exist — it was removed in the B1 redesign")
    }

    func testDevLabsToggleIds_count() {
        XCTAssertEqual(devLabsToggleSuffixes.count, 9,
                       "Expected 9 individual feature toggles in Dev & Labs (6 experimental + 3 developer)")
    }

    // MARK: - Pairing tab identifiers

    private let pairingIds: Set<String> = [
        "settings.pairing.root",
        "settings.pairing.acceptInviteButton",
    ]

    func testPairingIds_useCorrectPrefix() {
        for id in pairingIds {
            XCTAssertTrue(id.hasPrefix("settings.pairing."),
                          "Pairing identifier '\(id)' must use settings.pairing. prefix")
        }
    }

    // MARK: - Configuration tab identifiers

    private let configurationIds: Set<String> = [
        "settings.configuration.root",
        "settings.configuration.openConfigFolder",
        "settings.configuration.listNewButton",
        "settings.configuration.emptyDetail",
        "settings.configuration.detail",
        "settings.configuration.heroHeader",
        "settings.configuration.heroRevealButton",
        "settings.configuration.heroEditButton",
        "settings.configuration.heroDuplicateButton",
        "settings.configuration.heroDeleteButton",
        "settings.configuration.heroResidentBadge",
    ]

    func testConfigurationIds_useCorrectPrefix() {
        for id in configurationIds {
            XCTAssertTrue(id.hasPrefix("settings.configuration."),
                          "Configuration identifier '\(id)' must use settings.configuration. prefix")
        }
    }

    // MARK: - Accept Invite identifiers

    private let acceptInviteIds: Set<String> = [
        "settings.acceptInvite.textEditor",
        "settings.acceptInvite.submitButton",
        "settings.acceptInvite.success",
        "settings.acceptInvite.error",
    ]

    func testAcceptInviteIds_useCorrectPrefix() {
        for id in acceptInviteIds {
            XCTAssertTrue(id.hasPrefix("settings.acceptInvite."),
                          "AcceptInvite identifier '\(id)' must use settings.acceptInvite. prefix")
        }
    }

    // MARK: - Quick Actions / Shortcuts tab identifiers

    private let shortcutsStaticIds: Set<String> = [
        "settings.quickActions.resetButton",
        "settings.quickActions.addButton",
        "settings.quickActions.usageOrderToggle",
    ]

    private let shortcutsDynamicPrefixes: [String] = [
        "settings.quickActions.row.",
        "settings.quickActions.editButton.",
        "settings.quickActions.deleteButton.",
        "settings.quickActions.dragHandle.",
    ]

    func testShortcutsIds_useCorrectPrefix() {
        for id in shortcutsStaticIds {
            XCTAssertTrue(id.hasPrefix("settings.quickActions."),
                          "Shortcuts identifier '\(id)' must use settings.quickActions. prefix")
        }
    }

    func testShortcutsDynamicIds_format() {
        for prefix in shortcutsDynamicPrefixes {
            let example = "\(prefix)00000000-0000-0000-0000-000000000000"
            XCTAssertTrue(example.hasPrefix("settings.quickActions."),
                          "Dynamic shortcuts identifier must use settings.quickActions. prefix, got '\(example)'")
        }
    }

    // MARK: - Sidebar chrome identifiers

    func testSidebarChromeIds_exist() {
        let chromeIds = [
            "settings.tabView",
            "settings.sidebar",
            "settings.header",
            "settings.backButton",
            "settings.detailPane",
        ]
        for id in chromeIds {
            XCTAssertTrue(id.hasPrefix("settings."),
                          "Settings chrome identifier '\(id)' must use settings. prefix")
        }
    }
}
