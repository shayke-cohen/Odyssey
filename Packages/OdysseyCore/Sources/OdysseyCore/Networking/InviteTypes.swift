// Sources/OdysseyCore/Networking/InviteTypes.swift
import Foundation

/// Network location hints embedded in an invite payload.
public struct InviteHints: Codable, Sendable {
    public let lan: String?
    public let wan: String?
    public let bonjour: String?

    public init(lan: String?, wan: String?, bonjour: String?) {
        self.lan = lan
        self.wan = wan
        self.bonjour = bonjour
    }
}

/// TURN relay configuration for NAT traversal fallback.
public struct TURNConfig: Codable, Sendable {
    public let url: String
    public let username: String
    public let credential: String

    public init(url: String, username: String, credential: String) {
        self.url = url
        self.username = username
        self.credential = credential
    }
}

/// The signed payload embedded in an invite QR code or deep link.
public struct InvitePayload: Codable, Sendable {
    public let hostPublicKeyBase64url: String
    public let hostDisplayName: String
    public let bearerToken: String
    public let tlsCertDERBase64: String
    public let hints: InviteHints
    public let turn: TURNConfig?
    public let expiresAt: String
    public let signature: String

    public init(
        hostPublicKeyBase64url: String,
        hostDisplayName: String,
        bearerToken: String,
        tlsCertDERBase64: String,
        hints: InviteHints,
        turn: TURNConfig?,
        expiresAt: String,
        signature: String
    ) {
        self.hostPublicKeyBase64url = hostPublicKeyBase64url
        self.hostDisplayName = hostDisplayName
        self.bearerToken = bearerToken
        self.tlsCertDERBase64 = tlsCertDERBase64
        self.hints = hints
        self.turn = turn
        self.expiresAt = expiresAt
        self.signature = signature
    }
}
