// Odyssey/Services/InviteCodeGenerator.swift
import CoreGraphics
import CoreImage
import Foundation
import OSLog
import OdysseyCore

private let logger = Logger(subsystem: "com.odyssey.app", category: "InviteCode")

// MARK: - Errors

enum InviteCodeError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode invite payload."
        }
    }
}

// MARK: - InviteCodeGenerator

struct InviteCodeGenerator {

    /// Build a device-invite payload using the Mac's Nostr identity.
    /// The payload contains only the Mac's npub + preferred relays + optional LAN hint.
    /// No TLS certs, no bearer tokens, no expiry.
    static func generateDevice(
        instanceName: String,
        lanHint: String?,
        nostrPubkey: String,
        nostrRelays: [String]
    ) -> InvitePayload {
        logger.info("InviteCodeGenerator: generating device invite for '\(instanceName, privacy: .public)'")
        return InvitePayload(
            macNpub: nostrPubkey,
            displayName: instanceName,
            relays: nostrRelays.isEmpty ? ["wss://relay.damus.io", "wss://relay.nostr.band"] : nostrRelays,
            lanHint: lanHint
        )
    }

    /// Build a user-invite code from a display name and Matrix user ID.
    /// Returns the base64url-encoded payload string.
    static func generateUser(
        instanceName: String,
        matrixUserId: String
    ) throws -> String {
        logger.info("InviteCodeGenerator: generating user invite for '\(instanceName, privacy: .public)'")
        let payload = InvitePayload(
            type: "user",
            macNpub: matrixUserId,
            displayName: instanceName,
            relays: [],
            lanHint: nil
        )
        return try encode(payload)
    }

    // MARK: - Decode / Verify

    /// Decode a base64url-encoded invite payload.
    static func decode(_ base64url: String) throws -> InvitePayload {
        try InvitePayload.decode(base64url)
    }

    /// Basic validation — ensures the payload has a non-empty identity and display name.
    static func verify(_ payload: InvitePayload) throws {
        guard !payload.macNpub.isEmpty else {
            throw InviteCodeError.encodingFailed
        }
        guard !payload.displayName.isEmpty else {
            throw InviteCodeError.encodingFailed
        }
    }

    // MARK: - Encode

    /// Encode a payload to a URL-safe base64url string.
    static func encode(_ payload: InvitePayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)
        return base64urlEncode(data)
    }

    // MARK: - QR Code

    /// Render a QR code for the `odyssey://connect?invite=<encoded>` deep link.
    static func qrCode(for payload: InvitePayload, size: CGFloat = 300) -> CGImage? {
        guard let encoded = try? encode(payload),
              let inputData = "odyssey://connect?invite=\(encoded)".data(using: .utf8)
        else { return nil }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(inputData, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }

    // MARK: - Base64url Helpers

    static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
