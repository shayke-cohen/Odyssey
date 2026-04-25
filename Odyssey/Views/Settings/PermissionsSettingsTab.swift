import SwiftUI

struct PermissionsSettingsTab: View {
    var body: some View {
        ConfigurationSettingsTab(
            initialSection: .permissions,
            visibleSections: [.permissions]
        )
    }
}
