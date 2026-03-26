import Foundation

/// A single log entry from either the Swift app or the TypeScript sidecar,
/// normalised into a common shape for the debug log window.
struct UnifiedLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let source: LogSource
    let category: String
    let message: String

    enum LogSource: String, CaseIterable, Identifiable, Sendable {
        case app = "App"
        case sidecar = "Sidecar"
        var id: String { rawValue }
    }
}

// MARK: - Sidecar JSON Line Parsing

extension UnifiedLogEntry {
    /// Attempt to parse a structured JSON log line emitted by `sidecar/src/logger.ts`.
    /// Falls back to legacy `[prefix] message` format.
    static func parseSidecarLine(_ line: String) -> UnifiedLogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try structured JSON first
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONDecoder().decode(SidecarLogLine.self, from: data)
        {
            let date = ISO8601DateFormatter().date(from: json.ts) ?? Date()
            let level = LogLevel(rawValue: json.level) ?? .info
            return UnifiedLogEntry(
                timestamp: date,
                level: level,
                source: .sidecar,
                category: json.category,
                message: json.message
            )
        }

        // Fallback: parse legacy `[category] message` format
        return parseLegacyLine(trimmed)
    }

    private static func parseLegacyLine(_ line: String) -> UnifiedLogEntry {
        var category = "sidecar"
        var message = line
        var level: LogLevel = .info

        // Extract [prefix] if present
        if line.hasPrefix("["),
           let closeBracket = line.firstIndex(of: "]")
        {
            let prefixStart = line.index(after: line.startIndex)
            category = String(line[prefixStart..<closeBracket])
                .components(separatedBy: ":").first ?? "sidecar"
            let afterBracket = line.index(after: closeBracket)
            message = String(line[afterBracket...]).trimmingCharacters(in: .whitespaces)
        }

        // Guess level from keywords
        let lower = message.lowercased()
        if lower.contains("error") || lower.contains("failed") || lower.contains("crash") {
            level = .error
        } else if lower.contains("warn") {
            level = .warn
        }

        return UnifiedLogEntry(
            timestamp: Date(),
            level: level,
            source: .sidecar,
            category: category,
            message: message
        )
    }

    private struct SidecarLogLine: Decodable {
        let ts: String
        let level: String
        let category: String
        let message: String
    }
}
