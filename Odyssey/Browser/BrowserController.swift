import Foundation
import WebKit

// Supporting types

struct NavigateResult {
    let title: String
    let finalURL: URL
}

struct ConsoleEntry: Codable {
    let level: String
    let message: String
    let timestamp: Double
}

struct NetworkEntry {
    let url: String
    let statusCode: Int?
    let method: String
}

enum ScrollDirection {
    case up, down
}

// The protocol — WKWebView backend today, CDP tomorrow

@MainActor
protocol BrowserController: AnyObject {
    func navigate(to url: URL) async throws -> NavigateResult
    func screenshot() async throws -> Data
    func readDOM() async throws -> String
    func click(selector: String) async throws
    func type(selector: String, text: String) async throws
    func scroll(direction: ScrollDirection, px: Int) async throws
    func waitFor(selector: String, timeoutMs: Int) async throws
    func getConsoleLogs() async throws -> [ConsoleEntry]
    func getNetworkLogs() async throws -> [NetworkEntry]
    func yieldToUser(message: String) async throws   // suspends until coordinator calls resumeFromYield()
    func renderHTML(_ html: String, title: String?) async throws -> String  // suspends until window.agent.submit fires; returns JSON string
    func resumeFromYield()    // called by BrowserOverlayCoordinator when user clicks Resume
    func resolveAgentSubmit(_ jsonString: String)  // called when agentSubmit message handler fires
    var currentURL: URL? { get }
    var currentTitle: String? { get }
}
