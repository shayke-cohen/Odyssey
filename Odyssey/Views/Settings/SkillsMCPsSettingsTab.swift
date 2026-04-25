import SwiftUI

struct SkillsMCPsSettingsTab: View {
    let initialSlug: String?

    init(initialSection: ConfigSection? = nil, initialSlug: String? = nil) {
        self.initialSlug = initialSlug
        _initialSection = State(initialValue: initialSection)
    }

    @State private var initialSection: ConfigSection?

    var body: some View {
        ConfigurationSettingsTab(
            initialSection: initialSection,
            initialSlug: initialSlug,
            visibleSections: [.skills, .mcps]
        )
    }
}
