import AppKit
import UniformTypeIdentifiers

@MainActor
enum ChatExportPresenters {

    static let markdownType = UTType(filenameExtension: "md") ?? .plainText

    static func runSavePanel(suggestedFileName: String, allowedTypes: [UTType]) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSSavePanel()
            panel.allowedContentTypes = allowedTypes
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.nameFieldStringValue = suggestedFileName
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Presents the system share sheet for a file URL. Retains `coordinator` until cleanup runs.
    ///
    /// Uses the next run loop so the SwiftUI menu can finish dismissing first; uses a non-zero
    /// anchor rect because `.zero` often yields no visible picker on macOS.
    static func presentSharePicker(for url: URL, coordinator: ShareTempFileCoordinator) {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
                  let view = window.contentView else {
                coordinator.cleanupNow()
                let alert = NSAlert()
                alert.messageText = "Couldn’t share"
                alert.informativeText = "No active window was found to attach the share sheet."
                alert.alertStyle = .informational
                alert.runModal()
                return
            }

            let items: [Any] = [url]
            if NSSharingService.sharingServices(forItems: items).isEmpty {
                coordinator.cleanupNow()
                let alert = NSAlert()
                alert.messageText = "Nothing to share"
                alert.informativeText = "Your Mac has no sharing actions available for this file type."
                alert.alertStyle = .informational
                alert.runModal()
                return
            }

            let b = view.bounds
            let side: CGFloat = max(64, min(120, min(b.width, b.height) * 0.15))
            let rect = NSRect(
                x: (b.width - side) / 2,
                y: (b.height - side) / 2,
                width: side,
                height: side
            )

            let picker = NSSharingServicePicker(items: items)
            picker.delegate = coordinator
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        }
    }
}

/// Retains the temp file until after the user dismisses the share picker, then removes it after a delay.
/// `onReleased` is always invoked on the main queue after cleanup.
final class ShareTempFileCoordinator: NSObject, NSSharingServicePickerDelegate, @unchecked Sendable {
    let url: URL
    private let onReleased: () -> Void

    init(url: URL, onReleased: @escaping () -> Void) {
        self.url = url
        self.onReleased = onReleased
        super.init()
    }

    /// Removes the temp file and clears SwiftUI retention when the picker is never shown or services are missing.
    func cleanupNow() {
        try? FileManager.default.removeItem(at: url)
        onReleased()
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        let fileURL = url
        let finish = onReleased
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            try? FileManager.default.removeItem(at: fileURL)
            finish()
        }
    }
}
