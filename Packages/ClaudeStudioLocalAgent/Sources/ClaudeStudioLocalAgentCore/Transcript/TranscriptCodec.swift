import Foundation

public enum TranscriptCodec {
    public static func encode(_ transcript: [TranscriptItem]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(transcript), as: UTF8.self)
    }

    public static func decode(_ payload: String) throws -> [TranscriptItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TranscriptItem].self, from: Data(payload.utf8))
    }
}
