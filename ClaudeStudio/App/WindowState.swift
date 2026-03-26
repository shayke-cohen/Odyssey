import SwiftUI
import SwiftData

/// Per-window state for the multi-window project model.
/// Each ClaudeStudio window is bound to a project directory
/// and has independent selection and sheet state.
@MainActor @Observable
final class WindowState {
    let projectDirectory: String

    /// Reference to the shared AppState for cross-window coordination.
    weak var appState: AppState?

    var selectedConversationId: UUID? {
        didSet {
            if selectedConversationId != nil { selectedGroupId = nil }
            // Update AppState's visible set for notification gating
            if let old = oldValue { appState?.visibleConversationIds.remove(old) }
            if let new = selectedConversationId {
                appState?.visibleConversationIds.insert(new)
                markConversationRead(id: new)
            }
        }
    }
    var selectedGroupId: UUID? {
        didSet { if selectedGroupId != nil { selectedConversationId = nil } }
    }

    var showNewSessionSheet = false
    var showAgentLibrary = false
    var showGroupLibrary = false
    var showPeerNetwork = false
    var showAgentComms = false
    var showWorkshop = false

    var launchError: String?
    var autoSendText: String?

    init(projectDirectory: String) {
        self.projectDirectory = projectDirectory
    }

    /// Short folder name for window title display.
    var projectName: String {
        (projectDirectory as NSString).lastPathComponent
    }

    private func markConversationRead(id: UUID) {
        guard let ctx = appState?.modelContext else { return }
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { c in c.id == id })
        guard let convo = try? ctx.fetch(descriptor).first, convo.isUnread else { return }
        convo.isUnread = false
        try? ctx.save()
    }
}
