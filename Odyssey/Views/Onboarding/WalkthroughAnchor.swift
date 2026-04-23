import SwiftUI

// MARK: - Anchor ID

enum WalkthroughAnchorID: String, CaseIterable {
    // Sidebar
    case sidebarSearch
    case sidebarSchedules
    case sidebarPinned
    case sidebarAgents
    case sidebarGroups
    case sidebarProjects
    case sidebarToolbar
    // Chat header
    case chatHeader
    case chatPlanMode
    case chatMoreOptions
    // Chat body
    case chatChips
    case chatQuickActions
    case chatComposer
    // Inspector
    case inspectorPanel
}

// MARK: - PreferenceKey

struct WalkthroughAnchorsKey: PreferenceKey {
    typealias Value = [WalkthroughAnchorID: CGRect]
    static let defaultValue: Value = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - View modifier

extension View {
    func walkthroughAnchor(_ id: WalkthroughAnchorID) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: WalkthroughAnchorsKey.self,
                    value: [id: geo.frame(in: .named("walkthroughCoordSpace"))]
                )
            }
        )
    }
}
