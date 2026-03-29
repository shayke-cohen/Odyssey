import SwiftUI

#if DEBUG
#if os(macOS)
import AppKit

private struct StableXrayMarker: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> MarkerView {
        MarkerView(id: id)
    }

    func updateNSView(_ nsView: MarkerView, context: Context) {
        nsView.update(id: id)
    }

    final class MarkerView: NSView {
        private var markerId: String

        init(id: String) {
            self.markerId = id
            super.init(frame: .zero)
            configure()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var isOpaque: Bool { false }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func update(id: String) {
            markerId = id
            configure()
        }

        private func configure() {
            setAccessibilityIdentifier(markerId)
            setAccessibilityLabel(markerId)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

private struct AppXrayTapProxy: NSViewRepresentable {
    let id: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> ProxyButton {
        let button = ProxyButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.invoke)
        button.isBordered = false
        button.title = ""
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        button.alphaValue = 0.01
        button.focusRingType = .none
        button.configure(id: id)
        return button
    }

    func updateNSView(_ nsView: ProxyButton, context: Context) {
        context.coordinator.action = action
        nsView.configure(id: id)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func invoke() {
            action()
        }
    }

    final class ProxyButton: NSButton {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            dirtyRect.fill()
        }

        func configure(id: String) {
            setAccessibilityIdentifier(id)
            setAccessibilityLabel(id)
            toolTip = id
        }
    }
}
#endif

extension View {
    /// Adds a concrete NSView marker so AppXray can resolve SwiftUI content
    /// inside scroll/detail regions where the SDK's default xrayId registry
    /// does not always surface a usable target.
    func stableXrayId(_ id: String) -> some View {
        #if os(macOS)
        return self
            .accessibilityIdentifier(id)
            .background {
                StableXrayMarker(id: id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        #else
        return self.accessibilityIdentifier(id)
        #endif
    }

    func appXrayTapProxy(id: String, action: @escaping () -> Void) -> some View {
        #if os(macOS)
        return self.background {
            AppXrayTapProxy(id: id, action: action)
        }
        #else
        return self
        #endif
    }
}
#else
extension View {
    func stableXrayId(_ id: String) -> some View {
        self.accessibilityIdentifier(id)
    }

    func appXrayTapProxy(id: String, action: @escaping () -> Void) -> some View {
        self
    }
}
#endif
