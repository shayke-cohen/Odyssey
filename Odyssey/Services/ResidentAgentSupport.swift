import Foundation

/// Utilities for Resident Agent filesystem support.
/// A "Resident Agent" is any Agent whose `defaultWorkingDirectory` is non-nil.
enum ResidentAgentSupport {

    /// Creates the home folder and seeds `MEMORY.md` inside it if neither exists yet.
    /// - Parameters:
    ///   - directoryPath: Absolute path (tilde already expanded) to the agent's home folder.
    ///   - agentName: Display name used as the MEMORY.md heading.
    /// - Returns: `true` if the file was newly created, `false` if it already existed.
    @discardableResult
    static func seedMemoryFileIfNeeded(in directoryPath: String, agentName: String) -> Bool {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let memoryURL = dirURL.appendingPathComponent("MEMORY.md")

        guard !fm.fileExists(atPath: memoryURL.path) else { return false }

        do {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            try memoryTemplate(agentName: agentName)
                .write(to: memoryURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            // Non-fatal: agent can still work without MEMORY.md
            return false
        }
    }

    static func memoryTemplate(agentName: String) -> String {
        """
        # \(agentName) — Memory

        ## Goals
        <!-- What this agent is here to do -->

        ## Active Context
        <!-- Current project state, key decisions -->

        ## Notes
        <!-- Accumulated knowledge -->

        ## Decisions Log
        <!-- Dated decisions made across chats -->
        """
    }
}
