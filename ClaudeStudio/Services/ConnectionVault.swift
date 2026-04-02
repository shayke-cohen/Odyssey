import Foundation
import Security

enum ConnectionVaultError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case malformedData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        case .malformedData:
            return "Stored connector credentials could not be decoded."
        }
    }
}

enum ConnectionVault {
    private static let service = "com.claudestudio.connectors"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func loadCredentials(connectionId: UUID) throws -> ConnectionCredentialPayload? {
        var query = baseQuery(connectionId: connectionId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw ConnectionVaultError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            throw ConnectionVaultError.malformedData
        }
        guard let payload = try? decoder.decode(ConnectionCredentialPayload.self, from: data) else {
            throw ConnectionVaultError.malformedData
        }
        return payload
    }

    static func saveCredentials(_ payload: ConnectionCredentialPayload, connectionId: UUID) throws {
        let data = try encoder.encode(payload)
        let query = baseQuery(connectionId: connectionId)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw ConnectionVaultError.unexpectedStatus(updateStatus)
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw ConnectionVaultError.unexpectedStatus(insertStatus)
        }
    }

    static func deleteCredentials(connectionId: UUID) throws {
        let status = SecItemDelete(baseQuery(connectionId: connectionId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ConnectionVaultError.unexpectedStatus(status)
        }
    }

    private static func baseQuery(connectionId: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionId.uuidString,
        ]
    }
}
