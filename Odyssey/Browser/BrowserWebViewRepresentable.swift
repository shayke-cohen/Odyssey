import SwiftUI
import WebKit

/// An `NSViewRepresentable` wrapper that embeds the controller's `WKWebView` in SwiftUI.
/// The controller owns the WKWebView lifetime; this representable just surfaces it.
struct BrowserWebViewRepresentable: NSViewRepresentable {
    let controller: WKWebViewBrowserController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WKWebView is owned and driven by the controller; no SwiftUI-driven update needed.
    }
}
