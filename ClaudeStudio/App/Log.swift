import OSLog

/// Centralized structured logging for ClaudeStudio.
///
/// Usage:  `Log.appState.info("Session created")`
///
/// Each category maps to a `[Prefix]` that was previously used in `print()` calls.
/// All loggers share the subsystem `com.claudestudio.app` so they can be queried
/// together via `OSLogStore`.
enum Log {
    static let subsystem = "com.claudestudio.app"

    static let appState    = Logger(subsystem: subsystem, category: "appState")
    static let sidecar     = Logger(subsystem: subsystem, category: "sidecar")
    static let configSync  = Logger(subsystem: subsystem, category: "configSync")
    static let configFile  = Logger(subsystem: subsystem, category: "configFile")
    static let seeder      = Logger(subsystem: subsystem, category: "seeder")
    static let peerCatalog = Logger(subsystem: subsystem, category: "peerCatalog")
    static let chat        = Logger(subsystem: subsystem, category: "chat")
    static let p2p         = Logger(subsystem: subsystem, category: "p2p")
    static let general     = Logger(subsystem: subsystem, category: "general")
}
