import AppKit
import Foundation
import OSLog

/// Merges Swift (OSLog) and sidecar (JSON file) log entries into a single
/// chronological stream for the debug log window.
///
/// Performance design:
/// - `visibleEntries` is a capped slice (last 500) to keep SwiftUI diffing cheap
/// - Sidecar updates are batched (300ms throttle)
/// - Full entry list is kept for copy-to-clipboard only
@MainActor
final class LogAggregator: ObservableObject {

    // MARK: - Published State (drives the view)

    /// Capped slice of filtered entries for display. Max `visibleCap` items.
    @Published private(set) var visibleEntries: [UnifiedLogEntry] = []
    @Published private(set) var filteredCount: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var availableCategories: [String] = []

    /// Bumped on each flush so the view can auto-scroll without reading the array.
    @Published private(set) var scrollToken: Int = 0

    @Published var filterLevel: LogLevel = .debug { didSet { refilter() } }
    @Published var filterSource: UnifiedLogEntry.LogSource? = nil { didSet { refilter() } }
    @Published var filterCategory: String? = nil { didSet { refilter() } }
    @Published var searchText: String = "" { didSet { refilter() } }

    // MARK: - Internal Storage

    private var entries: [UnifiedLogEntry] = []
    private var filtered: [UnifiedLogEntry] = []
    private static let visibleCap = 500
    private static let maxEntries = 10_000
    private static let pruneCount = 2_000

    // MARK: - Streaming Control

    private var sidecarTailTask: Task<Void, Never>?
    private var swiftLogTimer: Timer?
    private var lastSwiftLogDate: Date = Date()
    private var pendingSidecarEntries: [UnifiedLogEntry] = []
    private var flushTask: Task<Void, Never>?

    func startStreaming(logDirectory: URL) {
        lastSwiftLogDate = Date()
        loadSwiftLogs()
        startSwiftLogPolling()
        startSidecarTail(logDirectory: logDirectory)
    }

    func stopStreaming() {
        sidecarTailTask?.cancel()
        sidecarTailTask = nil
        swiftLogTimer?.invalidate()
        swiftLogTimer = nil
        flushTask?.cancel()
        flushTask = nil
    }

    func clear() {
        entries.removeAll()
        filtered.removeAll()
        pendingSidecarEntries.removeAll()
        visibleEntries = []
        filteredCount = 0
        totalCount = 0
    }

    // MARK: - Copy to Clipboard (uses full filtered list, not capped)

    func copyFilteredToClipboard() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        let text = filtered.map { entry in
            let ts = formatter.string(from: entry.timestamp)
            let lvl = entry.level.rawValue.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0)
            let src = entry.source.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
            return "\(ts) \(lvl) [\(entry.category)] \(src) \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Filtering

    private func refilter() {
        let levelOrder: [LogLevel] = [.debug, .info, .warn, .error]
        let filterIdx = levelOrder.firstIndex(of: filterLevel) ?? 0
        let src = filterSource
        let cat = filterCategory
        let query = searchText.lowercased()
        let hasQuery = !query.isEmpty

        filtered = entries.filter { entry in
            guard let entryIdx = levelOrder.firstIndex(of: entry.level),
                  entryIdx >= filterIdx else { return false }
            if let src, entry.source != src { return false }
            if let cat, entry.category != cat { return false }
            if hasQuery {
                guard entry.message.localizedCaseInsensitiveContains(query)
                        || entry.category.localizedCaseInsensitiveContains(query) else { return false }
            }
            return true
        }

        publishVisible()
    }

    /// Push the tail of `filtered` into `visibleEntries` (capped).
    private func publishVisible() {
        let cap = Self.visibleCap
        if filtered.count > cap {
            visibleEntries = Array(filtered.suffix(cap))
        } else {
            visibleEntries = filtered
        }
        filteredCount = filtered.count
        totalCount = entries.count
        scrollToken += 1

        let cats = Set(entries.map(\.category))
        if cats.count != availableCategories.count {
            availableCategories = cats.sorted()
        }
    }

    // MARK: - Swift Logs (OSLogStore)

    private func loadSwiftLogs() {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: lastSwiftLogDate)
            let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
            let osEntries = try store.getEntries(at: position, matching: predicate)

            var newEntries: [UnifiedLogEntry] = []
            for entry in osEntries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }
                guard logEntry.date > lastSwiftLogDate else { continue }

                let level: LogLevel
                switch logEntry.level {
                case .debug: level = .debug
                case .info, .notice: level = .info
                case .error: level = .error
                case .fault: level = .error
                default: level = .info
                }

                newEntries.append(UnifiedLogEntry(
                    timestamp: logEntry.date,
                    level: level,
                    source: .app,
                    category: logEntry.category,
                    message: logEntry.composedMessage
                ))
            }

            if let latest = newEntries.last?.timestamp {
                lastSwiftLogDate = latest
            }

            if !newEntries.isEmpty {
                entries.append(contentsOf: newEntries)
                pruneIfNeeded()
                refilter()
            }
        } catch {
            // OSLogStore may not be available — silently skip
        }
    }

    private func startSwiftLogPolling() {
        swiftLogTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadSwiftLogs()
            }
        }
    }

    // MARK: - Sidecar Logs (file tail, batched)

    private func startSidecarTail(logDirectory: URL) {
        let logPath = logDirectory.appendingPathComponent("sidecar.log").path

        sidecarTailTask = Task.detached { [weak self] in
            guard let handle = FileHandle(forReadingAtPath: logPath) else { return }
            handle.seekToEndOfFile()

            let fd = handle.fileDescriptor
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: .write,
                queue: .global(qos: .utility)
            )

            source.setEventHandler { [weak self] in
                let data = handle.availableData
                guard !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else { return }

                let lines = text.components(separatedBy: "\n")
                let parsed = lines.compactMap { UnifiedLogEntry.parseSidecarLine($0) }

                guard !parsed.isEmpty else { return }
                Task { @MainActor [weak self] in
                    self?.enqueueSidecarEntries(parsed)
                }
            }

            source.setCancelHandler {
                handle.closeFile()
            }
            source.resume()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
            source.cancel()
        }
    }

    private func enqueueSidecarEntries(_ newEntries: [UnifiedLogEntry]) {
        pendingSidecarEntries.append(contentsOf: newEntries)

        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.flushPendingEntries()
            self?.flushTask = nil
        }
    }

    private func flushPendingEntries() {
        guard !pendingSidecarEntries.isEmpty else { return }
        entries.append(contentsOf: pendingSidecarEntries)
        pendingSidecarEntries.removeAll(keepingCapacity: true)
        pruneIfNeeded()
        refilter()
    }

    // MARK: - Housekeeping

    private func pruneIfNeeded() {
        if entries.count > Self.maxEntries {
            entries.removeFirst(Self.pruneCount)
        }
    }
}
