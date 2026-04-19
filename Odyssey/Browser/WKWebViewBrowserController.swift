import Foundation
import WebKit
import AppKit

@MainActor
final class WKWebViewBrowserController: NSObject, BrowserController {

    // MARK: - Properties

    let webView: WKWebView
    private var networkLog: [NetworkEntry] = []
    private var pendingNavigationContinuation: CheckedContinuation<NavigateResult, Error>?
    private var pendingYieldContinuation: CheckedContinuation<Void, Error>?
    private var pendingSubmitContinuation: CheckedContinuation<String, Error>?
    private(set) var currentURL: URL?
    private(set) var currentTitle: String?

    // MARK: - Init

    init(dataStore: WKWebsiteDataStore = .default()) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore

        // Inject browser-inspector.js at document start on all frames
        if let scriptURL = Bundle.main.url(forResource: "browser-inspector", withExtension: "js"),
           let scriptSource = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let script = WKUserScript(source: scriptSource,
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: false)
            config.userContentController.addUserScript(script)
        }

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        // Register script message handlers
        config.userContentController.add(ScriptMessageProxy(target: self), name: "consoleLog")
        config.userContentController.add(ScriptMessageProxy(target: self), name: "agentSubmit")
        config.userContentController.add(ScriptMessageProxy(target: self), name: "pageReady")

        webView.navigationDelegate = self
    }

    // MARK: - BrowserController methods

    func navigate(to url: URL) async throws -> NavigateResult {
        // Cancel any in-flight navigation continuation
        pendingNavigationContinuation?.resume(throwing: CancellationError())
        pendingNavigationContinuation = nil

        // Cancel any in-flight submit continuation
        pendingSubmitContinuation?.resume(throwing: CancellationError())
        pendingSubmitContinuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingNavigationContinuation = continuation
            self.webView.load(URLRequest(url: url))
        }
    }

    func screenshot() async throws -> Data {
        let config = WKSnapshotConfiguration()
        let image = try await webView.takeSnapshot(configuration: config)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw BrowserError.screenshotFailed
        }
        return pngData
    }

    func readDOM() async throws -> String {
        let result = try await webView.evaluateJavaScript("JSON.stringify(window.__odyssey.exportAccessibilityTree())")
        return result as? String ?? "null"
    }

    func click(selector: String) async throws {
        // Resolve the selector
        let resolveJS = "JSON.stringify(window.__odyssey.resolveSelector(\(jsonString(selector))))"
        guard let resultStr = try await webView.evaluateJavaScript(resolveJS) as? String,
              let data = resultStr.data(using: .utf8),
              let info = try? JSONDecoder().decode(SelectorResult.self, from: data),
              info.found else {
            throw BrowserError.selectorNotFound(selector)
        }

        // Highlight the element so user sees intent
        let highlightJS = """
        window.__odyssey.highlightElement(
          {top:\(info.top),left:\(info.left),width:\(info.width),height:\(info.height)},
          "clicking"
        )
        """
        try await webView.evaluateJavaScript(highlightJS)

        // Short pause so user can see the highlight
        try await Task.sleep(nanoseconds: 400_000_000) // 400ms

        // Click and clear
        let clickJS = """
        (function(){
          var el = document.querySelector(\(jsonString(selector)));
          if(el){ el.click(); window.__odyssey.clearHighlight(); return true; }
          return false;
        })()
        """
        let clicked = try await webView.evaluateJavaScript(clickJS) as? Bool ?? false
        if !clicked { throw BrowserError.selectorNotFound(selector) }
    }

    func type(selector: String, text: String) async throws {
        let highlightJS = """
        (function(){
          var el = document.querySelector(\(jsonString(selector)));
          if(!el) return false;
          var r = el.getBoundingClientRect();
          window.__odyssey.highlightElement(
            {top:r.top,left:r.left,width:r.width,height:r.height}, "typing"
          );
          return true;
        })()
        """
        let found = try await webView.evaluateJavaScript(highlightJS) as? Bool ?? false
        guard found else { throw BrowserError.selectorNotFound(selector) }

        try await Task.sleep(nanoseconds: 200_000_000)

        let typeJS = """
        (function(){
          var el = document.querySelector(\(jsonString(selector)));
          if(!el) return;
          el.focus();
          el.value = '';
          el.value = \(jsonString(text));
          el.dispatchEvent(new Event('input', {bubbles:true}));
          el.dispatchEvent(new Event('change', {bubbles:true}));
          window.__odyssey.clearHighlight();
        })()
        """
        try await webView.evaluateJavaScript(typeJS)
    }

    func scroll(direction: ScrollDirection, px: Int) async throws {
        let dy = direction == .down ? px : -px
        try await webView.evaluateJavaScript("window.scrollBy(0, \(dy))")
    }

    func waitFor(selector: String, timeoutMs: Int) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            let js = "document.querySelector(\(jsonString(selector))) !== null"
            if let found = try await webView.evaluateJavaScript(js) as? Bool, found {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw BrowserError.waitTimeout(selector)
    }

    func getConsoleLogs() async throws -> [ConsoleEntry] {
        let js = "JSON.stringify(window.__odyssey.getLogs())"
        guard let str = try await webView.evaluateJavaScript(js) as? String,
              let data = str.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ConsoleEntry].self, from: data)) ?? []
    }

    func getNetworkLogs() async throws -> [NetworkEntry] {
        return networkLog
    }

    func yieldToUser(message: String) async throws {
        pendingYieldContinuation?.resume(throwing: CancellationError())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.pendingYieldContinuation = continuation
        }
    }

    func resumeFromYield() {
        pendingYieldContinuation?.resume()
        pendingYieldContinuation = nil
    }

    func renderHTML(_ html: String, title: String?) async throws -> String {
        pendingSubmitContinuation?.resume(throwing: CancellationError())
        pendingSubmitContinuation = nil
        pendingNavigationContinuation?.resume(throwing: CancellationError())
        pendingNavigationContinuation = nil
        webView.loadHTMLString(html, baseURL: nil)
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingSubmitContinuation = continuation
        }
    }

    func resolveAgentSubmit(_ jsonString: String) {
        pendingSubmitContinuation?.resume(returning: jsonString)
        pendingSubmitContinuation = nil
    }

    // MARK: - Helpers

    private func jsonString(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: s),
           let result = String(data: data, encoding: .utf8) {
            return result // already includes surrounding quotes
        }
        return "null"
    }
}

// MARK: - WKNavigationDelegate

extension WKWebViewBrowserController: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            let url = webView.url ?? URL(string: "about:blank")!
            let title = webView.title ?? ""
            self.currentURL = url
            self.currentTitle = title
            self.pendingNavigationContinuation?.resume(returning: NavigateResult(title: title, finalURL: url))
            self.pendingNavigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.pendingNavigationContinuation?.resume(throwing: error)
            self.pendingNavigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.pendingNavigationContinuation?.resume(throwing: error)
            self.pendingNavigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            let entry = NetworkEntry(url: httpResponse.url?.absoluteString ?? "", statusCode: httpResponse.statusCode)
            Task { @MainActor in
                self.networkLog.append(entry)
                if self.networkLog.count > 200 { self.networkLog.removeFirst() }
            }
        }
        decisionHandler(.allow)
    }
}

// MARK: - WKScriptMessageHandler (via proxy to avoid retain cycle)

extension WKWebViewBrowserController: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            switch message.name {
            case "agentSubmit":
                let body = message.body as? String ?? "{}"
                self.resolveAgentSubmit(body)
            case "pageReady":
                break // navigation delegate already handles this
            case "consoleLog":
                break // logs stored in JS ring buffer, retrieved on demand
            default:
                break
            }
        }
    }
}

// MARK: - Supporting types

private struct SelectorResult: Codable {
    let found: Bool
    let top: Double
    let left: Double
    let width: Double
    let height: Double
}

enum BrowserError: LocalizedError {
    case screenshotFailed
    case selectorNotFound(String)
    case waitTimeout(String)

    var errorDescription: String? {
        switch self {
        case .screenshotFailed: return "Failed to capture screenshot"
        case .selectorNotFound(let s): return "Element not found: \(s)"
        case .waitTimeout(let s): return "Timed out waiting for: \(s)"
        }
    }
}

// Weak proxy to avoid WKUserContentController retain cycle
private class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKWebViewBrowserController?
    init(target: WKWebViewBrowserController) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
