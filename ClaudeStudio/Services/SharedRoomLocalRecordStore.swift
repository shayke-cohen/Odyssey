import CloudKit
import Foundation

final class SharedRoomLocalRecordStore: @unchecked Sendable {
    private struct StoredRecord: Codable, Equatable {
        let recordName: String
        let recordType: String
        let archivedData: Data
    }

    private let storeURL: URL
    private let lockURL: URL

    init(storeURL: URL) {
        self.storeURL = storeURL
        self.lockURL = storeURL.appendingPathExtension("lock")
    }

    func save(record: CKRecord) throws -> CKRecord {
        try withExclusiveAccess { records in
            let archivedData = try NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
            let stored = StoredRecord(
                recordName: record.recordID.recordName,
                recordType: record.recordType,
                archivedData: archivedData
            )

            var next = records.filter { $0.recordName != stored.recordName }
            next.append(stored)
            next.sort { $0.recordName < $1.recordName }
            return (record, next)
        }
    }

    func fetchRecord(recordName: String) throws -> CKRecord {
        try withExclusiveAccess { records in
            guard let stored = records.first(where: { $0.recordName == recordName }) else {
                throw SharedRoomError.recordNotFound(recordName)
            }
            return (try decodeRecord(stored), records)
        }
    }

    func queryRecords(
        recordType: String,
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor]
    ) throws -> [CKRecord] {
        try withExclusiveAccess { records in
            let matching = try records
                .filter { $0.recordType == recordType }
                .map(decodeRecord(_:))
                .filter { matches(predicate: predicate, record: $0) }
                .sorted { lhs, rhs in
                    compare(lhs, rhs, sortDescriptors: sortDescriptors)
                }
            return (matching, records)
        }
    }

    private func withExclusiveAccess<T>(
        _ body: ([StoredRecord]) throws -> (T, [StoredRecord])
    ) throws -> T {
        try ensureParentDirectory()
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw SharedRoomError.localTestBackendUnavailable
        }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        guard flock(fd, LOCK_EX) == 0 else {
            throw SharedRoomError.localTestBackendUnavailable
        }

        let current = try loadRecords()
        let (result, next) = try body(current)
        if next != current {
            try saveRecords(next)
        }
        return result
    }

    private func ensureParentDirectory() throws {
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func loadRecords() throws -> [StoredRecord] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return []
        }
        let data = try Data(contentsOf: storeURL)
        return try PropertyListDecoder().decode([StoredRecord].self, from: data)
    }

    private func saveRecords(_ records: [StoredRecord]) throws {
        let data = try PropertyListEncoder().encode(records)
        try data.write(to: storeURL, options: .atomic)
    }

    private func decodeRecord(_ stored: StoredRecord) throws -> CKRecord {
        guard let record = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: stored.archivedData) else {
            throw SharedRoomError.localTestBackendUnavailable
        }
        return record
    }

    private func matches(predicate: NSPredicate, record: CKRecord) -> Bool {
        let values = NSMutableDictionary()
        for key in record.allKeys() {
            if let value = record[key] {
                values[key] = normalizedPredicateValue(value)
            }
        }
        return predicate.evaluate(with: values)
    }

    private func normalizedPredicateValue(_ value: Any) -> Any {
        switch value {
        case let number as NSNumber:
            return number
        case let string as NSString:
            return string
        case let date as NSDate:
            return date
        default:
            return value
        }
    }

    private func compare(_ lhs: CKRecord, _ rhs: CKRecord, sortDescriptors: [NSSortDescriptor]) -> Bool {
        for descriptor in sortDescriptors {
            guard let key = descriptor.key else { continue }
            let lhsValue = sortValue(forKey: key, in: lhs)
            let rhsValue = sortValue(forKey: key, in: rhs)
            let comparison = compareValues(lhsValue, rhsValue)
            if comparison == 0 { continue }
            return descriptor.ascending ? comparison < 0 : comparison > 0
        }
        return lhs.recordID.recordName < rhs.recordID.recordName
    }

    private func sortValue(forKey key: String, in record: CKRecord) -> Any? {
        record[key]
    }

    private func compareValues(_ lhs: Any?, _ rhs: Any?) -> Int {
        switch (lhs, rhs) {
        case let (lhs as NSDate, rhs as NSDate):
            return lhs.compare(rhs as Date).rawValue
        case let (lhs as NSNumber, rhs as NSNumber):
            if lhs.doubleValue == rhs.doubleValue { return 0 }
            return lhs.doubleValue < rhs.doubleValue ? -1 : 1
        case let (lhs as NSString, rhs as NSString):
            return lhs.compare(rhs as String).rawValue
        case (nil, nil):
            return 0
        case (nil, _):
            return -1
        case (_, nil):
            return 1
        default:
            let lhsString = String(describing: lhs)
            let rhsString = String(describing: rhs)
            if lhsString == rhsString { return 0 }
            return lhsString < rhsString ? -1 : 1
        }
    }
}
