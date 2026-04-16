import AppKit
import Foundation

struct ScheduledMissionCadence {
    static func nextOccurrence(
        for schedule: ScheduledMission,
        after referenceDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch schedule.cadenceKind {
        case .hourlyInterval:
            let hours = max(1, min(schedule.intervalHours ?? 1, 24))
            let anchor = schedule.lastScheduledOccurrenceAt ?? schedule.createdAt
            var next = schedule.lastScheduledOccurrenceAt == nil
                ? anchor.addingTimeInterval(TimeInterval(hours * 3600))
                : anchor
            while next <= referenceDate {
                guard let advanced = calendar.date(byAdding: .hour, value: hours, to: next) else { return nil }
                next = advanced
            }
            return next

        case .dailyTime:
            let hour = min(max(schedule.localHour ?? 9, 0), 23)
            let minute = min(max(schedule.localMinute ?? 0, 0), 59)
            let selectedDays = Set(schedule.daysOfWeek.map(\.rawValue))

            for dayOffset in 0...14 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: referenceDate) else {
                    continue
                }
                let weekday = calendar.component(.weekday, from: day)
                if !selectedDays.isEmpty, !selectedDays.contains(weekday) {
                    continue
                }
                guard let candidate = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: day
                ) else {
                    continue
                }
                if candidate > referenceDate {
                    return candidate
                }
            }
            return nil
        }
    }

    static func cadenceSummary(forDraft draft: ScheduledMissionDraft) -> String {
        switch draft.cadenceKind {
        case .hourlyInterval:
            let hours = max(1, draft.intervalHours)
            return hours == 1 ? "Every hour" : "Every \(hours) hours"
        case .dailyTime:
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("HH:mm")
            let base = Calendar.current.date(
                from: DateComponents(
                    year: 2001,
                    month: 1,
                    day: 1,
                    hour: draft.localHour,
                    minute: draft.localMinute
                )
            ) ?? Date()
            let time = formatter.string(from: base)
            let days = draft.daysOfWeek
            if days.isEmpty || days.count == ScheduledMissionWeekday.allCases.count {
                return "Daily at \(time)"
            }
            if days == [.monday, .tuesday, .wednesday, .thursday, .friday] {
                return "Weekdays at \(time)"
            }
            return "\(days.map(\.shortLabel).joined(separator: " ")) at \(time)"
        }
    }

    static func cadenceSummary(for schedule: ScheduledMission) -> String {
        switch schedule.cadenceKind {
        case .hourlyInterval:
            let hours = max(1, schedule.intervalHours ?? 1)
            return hours == 1 ? "Every hour" : "Every \(hours) hours"
        case .dailyTime:
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("HH:mm")
            let base = Calendar.current.date(
                from: DateComponents(
                    year: 2001,
                    month: 1,
                    day: 1,
                    hour: schedule.localHour ?? 9,
                    minute: schedule.localMinute ?? 0
                )
            ) ?? Date()
            let time = formatter.string(from: base)
            let days = schedule.daysOfWeek
            if days.isEmpty || days.count == ScheduledMissionWeekday.allCases.count {
                return "Daily at \(time)"
            }
            if days == [.monday, .tuesday, .wednesday, .thursday, .friday] {
                return "Weekdays at \(time)"
            }
            return "\(days.map(\.shortLabel).joined(separator: " ")) at \(time)"
        }
    }
}

struct ScheduledMissionPromptRenderer {
    static func render(
        schedule: ScheduledMission,
        runCount: Int,
        now: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()

        func format(_ date: Date?) -> String {
            guard let date else { return "never" }
            return formatter.string(from: date)
        }

        return schedule.promptTemplate
            .replacingOccurrences(of: "{{now}}", with: format(now))
            .replacingOccurrences(of: "{{lastRunAt}}", with: format(schedule.lastStartedAt))
            .replacingOccurrences(of: "{{lastSuccessAt}}", with: format(schedule.lastSucceededAt))
            .replacingOccurrences(of: "{{runCount}}", with: String(runCount))
            .replacingOccurrences(of: "{{projectDirectory}}", with: schedule.projectDirectory)
    }

    static func shortSummary(from text: String, limit: Int = 220) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: limit)
        return normalized[..<end].trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

@MainActor
final class ScheduleLaunchdManager {
    private let fileManager: FileManager
    private let launchAgentsDirectory: URL
    private let scriptsDirectory: URL
    private let launchctlRunner: @MainActor ([String]) -> Void

    init(
        fileManager: FileManager = .default,
        launchAgentsDirectory: URL? = nil,
        scriptsDirectory: URL? = nil,
        launchctlRunner: @escaping @MainActor ([String]) -> Void = ScheduleLaunchdManager.defaultLaunchctlRunner
    ) {
        self.fileManager = fileManager
        let libraryDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
        self.launchAgentsDirectory = launchAgentsDirectory ?? libraryDirectory.appendingPathComponent("LaunchAgents", isDirectory: true)
        self.scriptsDirectory = scriptsDirectory ?? libraryDirectory
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Odyssey", isDirectory: true)
            .appendingPathComponent("Schedules", isDirectory: true)
        self.launchctlRunner = launchctlRunner
    }

    func sync(schedule: ScheduledMission) {
        if schedule.isEnabled && schedule.runWhenAppClosed {
            try? fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            try? fileManager.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
            let scriptURL = scriptURL(for: schedule)
            let plistURL = plistURL(for: schedule)
            try? writeScript(for: schedule, to: scriptURL)
            try? writePlist(for: schedule, scriptURL: scriptURL, to: plistURL)
            schedule.launchdJobLabel = jobLabel(for: schedule)
            reload(plistURL: plistURL)
        } else {
            remove(schedule: schedule)
        }
    }

    func remove(schedule: ScheduledMission) {
        let plistURL = plistURL(for: schedule)
        let scriptURL = scriptURL(for: schedule)
        unload(plistURL: plistURL)
        try? fileManager.removeItem(at: plistURL)
        try? fileManager.removeItem(at: scriptURL)
        schedule.launchdJobLabel = nil
    }

    func isInstalled(for schedule: ScheduledMission) -> Bool {
        fileManager.fileExists(atPath: plistURL(for: schedule).path)
    }

    func jobLabel(for schedule: ScheduledMission) -> String {
        "com.odyssey.schedule.\(schedule.id.uuidString.lowercased())"
    }

    private func plistURL(for schedule: ScheduledMission) -> URL {
        launchAgentsDirectory.appendingPathComponent("\(jobLabel(for: schedule)).plist")
    }

    private func scriptURL(for schedule: ScheduledMission) -> URL {
        scriptsDirectory.appendingPathComponent("\(schedule.id.uuidString).sh")
    }

    private func writeScript(for schedule: ScheduledMission, to url: URL) throws {
        let bundlePath = Bundle.main.bundleURL.path
        let script = """
        #!/bin/zsh
        set -euo pipefail
        OCCURRENCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        /usr/bin/open "\(bundlePath)" --args --schedule "\(schedule.id.uuidString)" --occurrence "$OCCURRENCE"
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func writePlist(for schedule: ScheduledMission, scriptURL: URL, to url: URL) throws {
        let launchd: NSMutableDictionary = [
            "Label": jobLabel(for: schedule),
            "ProgramArguments": ["/bin/zsh", scriptURL.path],
            "RunAtLoad": false,
        ]

        switch schedule.cadenceKind {
        case .hourlyInterval:
            let hours = max(1, schedule.intervalHours ?? 1)
            launchd["StartInterval"] = hours * 3600

        case .dailyTime:
            let hour = max(0, min(schedule.localHour ?? 9, 23))
            let minute = max(0, min(schedule.localMinute ?? 0, 59))
            let selectedDays = schedule.daysOfWeek

            if selectedDays.isEmpty || selectedDays.count == ScheduledMissionWeekday.allCases.count {
                launchd["StartCalendarInterval"] = [
                    "Hour": hour,
                    "Minute": minute,
                ]
            } else {
                launchd["StartCalendarInterval"] = selectedDays.map { day in
                    [
                        "Weekday": day.rawValue,
                        "Hour": hour,
                        "Minute": minute,
                    ]
                }
            }
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: launchd,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }

    private func reload(plistURL: URL) {
        unload(plistURL: plistURL)
        launchctlRunner(["load", plistURL.path])
    }

    private func unload(plistURL: URL) {
        launchctlRunner(["unload", plistURL.path])
    }

    private static func defaultLaunchctlRunner(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }
}
