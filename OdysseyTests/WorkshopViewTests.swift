import XCTest
@testable import Odyssey

/// Tests for ConfigSection — the successor to the removed WorkshopTab.
/// ConfigSection drives the 3-pane navigator inside AgentsGroupsSettingsTab,
/// SkillsMCPsSettingsTab, and PermissionsSettingsTab.
final class WorkshopViewTests: XCTestCase {

    func testConfigSectionCases() {
        let sections = ConfigSection.allCases
        XCTAssertEqual(sections.count, 6)
        XCTAssertEqual(sections.map(\.rawValue),
                       ["agents", "groups", "skills", "mcps", "templates", "permissions"])
    }

    func testConfigSectionIcons() {
        XCTAssertEqual(ConfigSection.agents.icon, "person.crop.circle")
        XCTAssertEqual(ConfigSection.groups.icon, "person.2")
        XCTAssertEqual(ConfigSection.skills.icon, "bolt")
        XCTAssertEqual(ConfigSection.mcps.icon, "hammer")
        XCTAssertEqual(ConfigSection.templates.icon, "text.document")
        XCTAssertEqual(ConfigSection.permissions.icon, "lock.shield")
    }

    func testConfigSectionIdentifiable() {
        for section in ConfigSection.allCases {
            XCTAssertEqual(section.id, section.rawValue)
        }
    }

    func testConfigSectionTitles() {
        XCTAssertEqual(ConfigSection.agents.title, "Agents")
        XCTAssertEqual(ConfigSection.groups.title, "Groups")
        XCTAssertEqual(ConfigSection.skills.title, "Skills")
        XCTAssertEqual(ConfigSection.mcps.title, "MCPs")
        XCTAssertEqual(ConfigSection.templates.title, "Templates")
        XCTAssertEqual(ConfigSection.permissions.title, "Permissions")
    }

    func testConfigSection_noVoiceCase() {
        let allIds = ConfigSection.allCases.map(\.id)
        XCTAssertFalse(allIds.contains("voice"),
                       "ConfigSection.voice must not exist — Voice is a top-level SettingsSection")
    }
}
