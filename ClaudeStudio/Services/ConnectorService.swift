import AppKit
import CryptoKit
import Foundation
import SwiftData

@MainActor
enum ConnectorService {
    nonisolated(unsafe) static var httpTransport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        try await URLSession.shared.data(for: request)
    }

    static var openExternalURL: (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    static func upsertConnection(
        provider: ConnectionProvider,
        in context: ModelContext
    ) -> Connection {
        let descriptor = FetchDescriptor<Connection>(predicate: #Predicate { connection in
            connection.providerRaw == provider.rawValue
        })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let definition = ConnectorCatalog.definition(for: provider)
        let connection = Connection(
            provider: provider,
            authMode: definition.authMode
        )
        connection.grantedScopes = definition.defaultScopes
        context.insert(connection)
        try? context.save()
        return connection
    }

    static func saveManualConnection(
        provider: ConnectionProvider,
        displayName: String,
        scopes: [String],
        authMode: ConnectionAuthMode,
        writePolicy: ConnectionWritePolicy,
        accountId: String?,
        accountHandle: String?,
        brokerReference: String?,
        accessToken: String?,
        refreshToken: String?,
        tokenType: String?,
        expiresAt: Date?,
        in context: ModelContext,
        appState: AppState?
    ) throws {
        let connection = upsertConnection(provider: provider, in: context)
        let definition = ConnectorCatalog.definition(for: provider)
        connection.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.displayName
            : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        connection.grantedScopes = scopes.isEmpty ? definition.defaultScopes : scopes
        connection.authMode = authMode
        connection.writePolicy = writePolicy
        connection.accountId = accountId.flatMap { $0.nilIfBlank }
        connection.accountHandle = accountHandle.flatMap { $0.nilIfBlank }
        connection.brokerReference = brokerReference.flatMap { $0.nilIfBlank }
        connection.lastAuthenticatedAt = Date()
        connection.updatedAt = Date()

        let payload = ConnectionCredentialPayload(
            accessToken: accessToken.flatMap { $0.nilIfBlank },
            refreshToken: refreshToken.flatMap { $0.nilIfBlank },
            tokenType: tokenType.flatMap { $0.nilIfBlank },
            expiresAt: expiresAt,
            brokerReference: brokerReference.flatMap { $0.nilIfBlank },
            authorizationCode: nil,
            codeVerifier: nil
        )
        try ConnectionVault.saveCredentials(payload, connectionId: connection.id)

        if payload.hasRuntimeCredential {
            connection.status = .connected
            connection.statusMessage = "Credentials stored in Keychain."
        } else {
            connection.status = .disconnected
            connection.statusMessage = "Connection saved without runtime credentials."
        }

        try context.save()
        appState?.syncConnectionToSidecar(connection)
    }

    static func revoke(
        _ connection: Connection,
        in context: ModelContext,
        appState: AppState?
    ) {
        try? ConnectionVault.deleteCredentials(connectionId: connection.id)
        connection.status = .revoked
        connection.statusMessage = "Credentials removed."
        connection.lastCheckedAt = Date()
        connection.updatedAt = Date()
        try? context.save()
        appState?.sendToSidecar(.connectorRevoke(connectionId: connection.id.uuidString))
    }

    static func beginAuth(
        provider: ConnectionProvider,
        in context: ModelContext,
        appState: AppState?
    ) throws {
        let connection = upsertConnection(provider: provider, in: context)
        let definition = ConnectorCatalog.definition(for: provider)
        connection.authMode = definition.authMode
        if connection.grantedScopes.isEmpty {
            connection.grantedScopes = definition.defaultScopes
        }
        connection.status = .authorizing
        connection.statusMessage = "Authorization started in your browser."
        connection.updatedAt = Date()
        try context.save()

        appState?.sendToSidecar(.connectorBeginAuth(connection: connection.asWire()))

        let url: URL
        switch definition.authMode {
        case .brokered:
            guard let brokerBase = AppSettings.store.string(forKey: AppSettings.connectorBrokerBaseURLKey).flatMap({ $0.nilIfBlank }),
                  let baseURL = URL(string: brokerBase) else {
                throw NSError(domain: "ConnectorService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Set a connector broker URL in Settings before starting brokered auth."
                ])
            }
            var components = URLComponents(url: baseURL.appending(path: "connect/\(provider.rawValue)"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "connection_id", value: connection.id.uuidString),
                URLQueryItem(name: "redirect_uri", value: ConnectorCatalog.callbackURL(for: provider)),
            ]
            guard let resolved = components?.url else {
                throw NSError(domain: "ConnectorService", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to build broker authorization URL."
                ])
            }
            url = resolved

        case .pkceNative:
            guard let authURL = definition.authURL else {
                throw NSError(domain: "ConnectorService", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "This provider does not define a native authorization URL."
                ])
            }
            guard let clientId = definition.clientIdSettingKey.flatMap({ AppSettings.store.string(forKey: $0).flatMap { $0.nilIfBlank } }) else {
                throw NSError(domain: "ConnectorService", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "Set the provider client ID in Settings before starting PKCE auth."
                ])
            }
            let verifier = randomURLSafeString(length: 64)
            let state = UUID().uuidString
            try ConnectionVault.saveCredentials(.init(
                accessToken: nil,
                refreshToken: nil,
                tokenType: nil,
                expiresAt: nil,
                brokerReference: connection.brokerReference,
                authorizationCode: nil,
                codeVerifier: verifier
            ), connectionId: connection.id)

            let challenge = sha256(verifier)
            var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: clientId),
                URLQueryItem(name: "redirect_uri", value: ConnectorCatalog.callbackURL(for: provider)),
                URLQueryItem(name: "scope", value: connection.grantedScopes.joined(separator: " ")),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
            ]
            guard let resolved = components?.url else {
                throw NSError(domain: "ConnectorService", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to build authorization URL."
                ])
            }
            AppSettings.store.set(state, forKey: pendingStateKey(for: connection.id))
            url = resolved
        }

        openExternalURL(url)
    }

    static func handleCallback(
        _ url: URL,
        in context: ModelContext,
        appState: AppState?
    ) -> Bool {
        guard url.scheme == ConnectorCatalog.callbackScheme,
              url.host(percentEncoded: false) == ConnectorCatalog.callbackHost else {
            return false
        }

        let providerName = url.pathComponents.count > 1 ? url.pathComponents[1] : ""
        guard let provider = ConnectionProvider(rawValue: providerName) else {
            return false
        }

        let connection = upsertConnection(provider: provider, in: context)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        if let error = query["error"]?.nilIfBlank ?? query["error_description"]?.nilIfBlank {
            connection.status = .failed
            connection.statusMessage = error
            connection.updatedAt = Date()
            try? context.save()
            appState?.sendToSidecar(.connectorBeginAuth(connection: connection.asWire()))
            return true
        }

        let accessToken = query["access_token"]?.nilIfBlank
        let refreshToken = query["refresh_token"]?.nilIfBlank
        let brokerReference = query["broker_reference"]?.nilIfBlank ?? query["brokerReference"]?.nilIfBlank
        let expiresAt = query["expires_at"].flatMap(connectorISO8601Date(from:))
        let scopes = (query["scope"] ?? "")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        if accessToken != nil || brokerReference != nil {
            try? saveManualConnection(
                provider: provider,
                displayName: query["display_name"]?.nilIfBlank ?? connection.displayName,
                scopes: scopes.isEmpty ? connection.grantedScopes : scopes,
                authMode: connection.authMode,
                writePolicy: connection.writePolicy,
                accountId: query["account_id"] ?? connection.accountId,
                accountHandle: query["account_handle"] ?? connection.accountHandle,
                brokerReference: brokerReference ?? connection.brokerReference,
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenType: query["token_type"]?.nilIfBlank,
                expiresAt: expiresAt,
                in: context,
                appState: appState
            )
            if let appState {
                appState.sendToSidecar(.connectorTest(connectionId: connection.id.uuidString))
            }
            return true
        }

        if let code = query["code"]?.nilIfBlank {
            let expectedState = AppSettings.store.string(forKey: pendingStateKey(for: connection.id))
            let returnedState = query["state"]?.nilIfBlank
            guard expectedState == nil || expectedState == returnedState else {
                connection.status = .failed
                connection.statusMessage = "Connector authorization state validation failed."
                connection.updatedAt = Date()
                try? context.save()
                return true
            }

            connection.status = .authorizing
            connection.statusMessage = "Finishing authorization..."
            connection.updatedAt = Date()
            try? context.save()
            AppSettings.store.removeObject(forKey: pendingStateKey(for: connection.id))
            Task {
                await exchangeAuthorizationCode(
                    for: connection,
                    code: code,
                    scopes: scopes,
                    in: context,
                    appState: appState
                )
            }
            return true
        }

        return true
    }

    static func providerConnection(for provider: ConnectionProvider, in connections: [Connection]) -> Connection? {
        connections.first(where: { $0.provider == provider })
    }

    private static func pendingStateKey(for connectionId: UUID) -> String {
        "connector.pendingState.\(connectionId.uuidString)"
    }

    private static func randomURLSafeString(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).map { _ in alphabet.randomElement() ?? "a" })
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func exchangeAuthorizationCode(
        for connection: Connection,
        code: String,
        scopes: [String],
        in context: ModelContext,
        appState: AppState?
    ) async {
        do {
            let definition = ConnectorCatalog.definition(for: connection.provider)
            guard connection.authMode == .pkceNative else {
                throw ConnectorServiceError.unsupportedAuthMode
            }
            guard let tokenURL = definition.tokenURL else {
                throw ConnectorServiceError.missingTokenURL
            }
            guard let clientIdKey = definition.clientIdSettingKey,
                  let clientId = AppSettings.store.string(forKey: clientIdKey)?.nilIfBlank else {
                throw ConnectorServiceError.missingClientID
            }
            var payload = try ConnectionVault.loadCredentials(connectionId: connection.id) ?? .init()
            guard let codeVerifier = payload.codeVerifier?.nilIfBlank else {
                throw ConnectorServiceError.missingCodeVerifier
            }

            var request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formEncodedBody([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": ConnectorCatalog.callbackURL(for: connection.provider),
                "client_id": clientId,
                "code_verifier": codeVerifier,
            ])

            let (data, response) = try await httpTransport(request)
            guard let http = response as? HTTPURLResponse else {
                throw ConnectorServiceError.invalidHTTPResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw ConnectorServiceError.httpFailure(code: http.statusCode, message: String(data: data, encoding: .utf8))
            }

            let tokenResponse = try JSONDecoder().decode(ConnectorTokenResponse.self, from: data)
            let resolvedExpiresAt = tokenResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            payload = ConnectionCredentialPayload(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken,
                tokenType: tokenResponse.tokenType ?? "Bearer",
                expiresAt: resolvedExpiresAt,
                brokerReference: connection.brokerReference,
                authorizationCode: nil,
                codeVerifier: nil
            )
            try ConnectionVault.saveCredentials(payload, connectionId: connection.id)

            connection.grantedScopes = scopes.isEmpty ? connection.grantedScopes : scopes
            connection.status = .connected
            connection.statusMessage = "Authorization complete."
            connection.lastAuthenticatedAt = Date()
            connection.updatedAt = Date()
            try context.save()
            appState?.syncConnectionToSidecar(connection)
            appState?.sendToSidecar(.connectorTest(connectionId: connection.id.uuidString))
        } catch {
            connection.status = .failed
            connection.statusMessage = error.localizedDescription
            connection.updatedAt = Date()
            try? context.save()
            appState?.syncConnectionToSidecar(connection)
        }
    }

    private static func formEncodedBody(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

}

private enum ConnectorServiceError: LocalizedError {
    case unsupportedAuthMode
    case missingTokenURL
    case missingClientID
    case missingCodeVerifier
    case invalidHTTPResponse
    case httpFailure(code: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .unsupportedAuthMode:
            return "This connector does not support native token exchange."
        case .missingTokenURL:
            return "The connector token endpoint is not configured."
        case .missingClientID:
            return "Set the provider client ID in Connectors settings before connecting."
        case .missingCodeVerifier:
            return "The PKCE code verifier is missing. Start the connection again."
        case .invalidHTTPResponse:
            return "The provider returned an invalid token response."
        case .httpFailure(let code, let message):
            return "Token exchange failed (\(code)): \(message?.nilIfBlank ?? "Unknown error")."
        }
    }
}

private struct ConnectorTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func connectorISO8601Date(from value: String) -> Date? {
    ISO8601DateFormatter().date(from: value)
}

private func connectorISO8601String(from value: Date) -> String {
    ISO8601DateFormatter().string(from: value)
}

extension Connection {
    func asWire() -> ConnectorWire {
        ConnectorWire(
            id: id.uuidString,
            provider: provider.rawValue,
            installScope: installScope.rawValue,
            displayName: displayName,
            accountId: accountId,
            accountHandle: accountHandle,
            accountMetadataJSON: accountMetadataJSON,
            grantedScopes: grantedScopes,
            authMode: authMode.rawValue,
            writePolicy: writePolicy.rawValue,
            status: status.rawValue,
            statusMessage: statusMessage,
            brokerReference: brokerReference,
            auditSummary: auditSummary,
            lastAuthenticatedAt: lastAuthenticatedAt.map(connectorISO8601String(from:)),
            lastCheckedAt: lastCheckedAt.map(connectorISO8601String(from:))
        )
    }
}

extension ConnectionCredentialPayload {
    func asWire() -> ConnectorCredentialsWire {
        ConnectorCredentialsWire(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresAt: expiresAt.map(connectorISO8601String(from:)),
            brokerReference: brokerReference
        )
    }
}
