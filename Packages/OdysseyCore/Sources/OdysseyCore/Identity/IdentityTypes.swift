// Sources/OdysseyCore/Identity/IdentityTypes.swift
import Foundation

/// The persistent identity of the local user on this Mac.
public struct UserIdentity: Codable, Sendable, Equatable {
    /// Ed25519 public key bytes (32 bytes), base64url-encoded.
    public let publicKeyBase64url: String
    /// Human-readable display name (from user preferences).
    public let displayName: String
    /// Stable random node ID (UUID string), persisted across launches.
    public let nodeId: String

    public init(publicKeyBase64url: String, displayName: String, nodeId: String) {
        self.publicKeyBase64url = publicKeyBase64url
        self.displayName = displayName
        self.nodeId = nodeId
    }
}

/// Bundle of identity material for a single agent instance.
public struct AgentIdentityBundle: Codable, Sendable {
    public let agentName: String
    public let publicKeyBase64url: String
    public let createdAt: String

    public init(agentName: String, publicKeyBase64url: String, createdAt: String) {
        self.agentName = agentName
        self.publicKeyBase64url = publicKeyBase64url
        self.createdAt = createdAt
    }
}

/// TLS certificate material for the Mac sidecar's self-signed cert.
public struct TLSBundle: Codable, Sendable {
    /// DER-encoded self-signed certificate, base64-encoded.
    public let certDERBase64: String
    /// ISO 8601 expiry date of the certificate.
    public let expiresAt: String

    public init(certDERBase64: String, expiresAt: String) {
        self.certDERBase64 = certDERBase64
        self.expiresAt = expiresAt
    }
}
