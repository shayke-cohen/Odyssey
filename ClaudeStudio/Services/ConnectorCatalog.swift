import Foundation

struct ConnectorProviderDefinition: Sendable {
    let provider: ConnectionProvider
    let authMode: ConnectionAuthMode
    let defaultScopes: [String]
    let docsURL: URL
    let authURL: URL?
    let tokenURL: URL?
    let clientIdSettingKey: String?
    let setupSummary: String
}

enum ConnectorCatalog {
    static let callbackScheme = "claudestudio"
    static let callbackHost = "connector-auth"

    static func definition(for provider: ConnectionProvider) -> ConnectorProviderDefinition {
        switch provider {
        case .slack:
            return .init(
                provider: provider,
                authMode: .brokered,
                defaultScopes: ["channels:read", "chat:write"],
                docsURL: URL(string: "https://api.slack.com/authentication/oauth-v2")!,
                authURL: nil,
                tokenURL: nil,
                clientIdSettingKey: nil,
                setupSummary: "Brokered workspace install. Set a broker URL, then connect once."
            )
        case .linkedin:
            return .init(
                provider: provider,
                authMode: .pkceNative,
                defaultScopes: ["openid", "profile", "email", "w_member_social"],
                docsURL: URL(string: "https://learn.microsoft.com/en-us/linkedin/shared/authentication/getting-access")!,
                authURL: URL(string: "https://www.linkedin.com/oauth/v2/authorization"),
                tokenURL: URL(string: "https://www.linkedin.com/oauth/v2/accessToken"),
                clientIdSettingKey: AppSettings.linkedinClientIdKey,
                setupSummary: "Native PKCE. Paste your LinkedIn app client ID, then click Connect."
            )
        case .x:
            return .init(
                provider: provider,
                authMode: .pkceNative,
                defaultScopes: ["users.read", "tweet.read", "offline.access", "tweet.write"],
                docsURL: URL(string: "https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code")!,
                authURL: URL(string: "https://x.com/i/oauth2/authorize"),
                tokenURL: URL(string: "https://api.x.com/2/oauth2/token"),
                clientIdSettingKey: AppSettings.xClientIdKey,
                setupSummary: "Native PKCE. Paste your X app client ID, then click Connect."
            )
        case .facebook:
            return .init(
                provider: provider,
                authMode: .brokered,
                defaultScopes: ["public_profile", "pages_manage_posts"],
                docsURL: URL(string: "https://developers.facebook.com/docs/facebook-login")!,
                authURL: nil,
                tokenURL: nil,
                clientIdSettingKey: nil,
                setupSummary: "Brokered Meta app flow for page and business access."
            )
        case .whatsapp:
            return .init(
                provider: provider,
                authMode: .brokered,
                defaultScopes: ["whatsapp_business_management", "whatsapp_business_messaging"],
                docsURL: URL(string: "https://developers.facebook.com/docs/whatsapp/cloud-api/get-started")!,
                authURL: nil,
                tokenURL: nil,
                clientIdSettingKey: nil,
                setupSummary: "Brokered WhatsApp Business onboarding with business assets and phone IDs."
            )
        }
    }

    static func callbackURL(for provider: ConnectionProvider) -> String {
        "\(callbackScheme)://\(callbackHost)/\(provider.rawValue)"
    }

    static func missingConfiguration(for provider: ConnectionProvider) -> [String] {
        let definition = definition(for: provider)
        var issues: [String] = []

        if definition.authMode == .brokered,
           AppSettings.store.string(forKey: AppSettings.connectorBrokerBaseURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append("Broker Base URL")
        }

        if let key = definition.clientIdSettingKey,
           AppSettings.store.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append("Client ID")
        }

        return issues
    }
}
