import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PasteableTextField: NSViewRepresentable {
    @Binding var text: String
    var onImagePaste: (Data, String) -> Void
    var onSubmit: () -> Void
    /// When plain Return should submit (Shift+Return always inserts a newline).
    var canSubmitOnReturn: () -> Bool = { true }

    func makeNSView(context: Context) -> NSTextField {
        let field = ImagePasteTextField()
        field.delegate = context.coordinator
        field.onImagePaste = onImagePaste
        field.placeholderString = "Message… (↩ send, ⇧↩ newline)"
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityIdentifier("pasteableTextField.input")
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PasteableTextField

        init(_ parent: PasteableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if textView.hasMarkedText() {
                    return false
                }
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    return false
                }
                if flags.contains(.command) {
                    parent.onSubmit()
                    return true
                }
                if parent.canSubmitOnReturn() {
                    parent.onSubmit()
                    return true
                }
                return false
            }
            return false
        }
    }
}

private class ImagePasteTextField: NSTextField {
    var onImagePaste: ((Data, String) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "v" {
            if pasteImageFromPasteboard() {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func pasteImageFromPasteboard() -> Bool {
        let pb = NSPasteboard.general
        let imageTypes: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "image/png"),
            (.tiff, "image/png"),
            (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "image/jpeg"),
            (NSPasteboard.PasteboardType(UTType.gif.identifier), "image/gif"),
        ]

        for (pbType, mediaType) in imageTypes {
            if let data = pb.data(forType: pbType) {
                let finalData: Data
                let finalMediaType: String
                if pbType == .tiff, let rep = NSBitmapImageRep(data: data),
                   let pngData = rep.representation(using: .png, properties: [:]) {
                    finalData = pngData
                    finalMediaType = "image/png"
                } else {
                    finalData = data
                    finalMediaType = mediaType
                }
                onImagePaste?(finalData, finalMediaType)
                return true
            }
        }
        return false
    }
}
