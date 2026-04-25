// OdysseyTests/InviteCodeTests.swift
import OdysseyCore
import XCTest
@testable import Odyssey

final class InviteCodeTests: XCTestCase {

    // MARK: - InvitePayload v2 structure

    func testDevicePayload_fields() {
        let payload = InviteCodeGenerator.generateDevice(
            instanceName: "My Mac",
            lanHint: "192.168.1.5",
            nostrPubkey: "abc123",
            nostrRelays: ["wss://relay.damus.io"]
        )
        XCTAssertEqual(payload.v, 2)
        XCTAssertEqual(payload.type, "device")
        XCTAssertEqual(payload.macNpub, "abc123")
        XCTAssertEqual(payload.displayName, "My Mac")
        XCTAssertEqual(payload.relays, ["wss://relay.damus.io"])
        XCTAssertEqual(payload.lanHint, "192.168.1.5")
    }

    func testDevicePayload_noLanHint() {
        let payload = InviteCodeGenerator.generateDevice(
            instanceName: "Headless",
            lanHint: nil,
            nostrPubkey: "npub1234",
            nostrRelays: []
        )
        XCTAssertNil(payload.lanHint)
        // Falls back to default relays when none provided
        XCTAssertFalse(payload.relays.isEmpty)
    }

    func testDevicePayload_defaultRelayFallback() {
        let payload = InviteCodeGenerator.generateDevice(
            instanceName: "X",
            lanHint: nil,
            nostrPubkey: "npub",
            nostrRelays: []
        )
        XCTAssertTrue(payload.relays.allSatisfy { $0.hasPrefix("wss://") })
    }

    // MARK: - Encode / Decode round-trip

    func testEncodeDecodeRoundTrip() throws {
        let payload = InviteCodeGenerator.generateDevice(
            instanceName: "Test Mac",
            lanHint: "10.0.0.1",
            nostrPubkey: "testpubkey",
            nostrRelays: ["wss://relay.nostr.band"]
        )
        let encoded = try InviteCodeGenerator.encode(payload)
        let decoded = try InviteCodeGenerator.decode(encoded)

        XCTAssertEqual(decoded.v, payload.v)
        XCTAssertEqual(decoded.type, payload.type)
        XCTAssertEqual(decoded.macNpub, payload.macNpub)
        XCTAssertEqual(decoded.displayName, payload.displayName)
        XCTAssertEqual(decoded.relays, payload.relays)
        XCTAssertEqual(decoded.lanHint, payload.lanHint)
    }

    func testDecode_invalidBase64_throws() {
        XCTAssertThrowsError(try InviteCodeGenerator.decode("!!!not-valid-base64!!!"))
    }

    func testDecode_emptyString_throws() {
        XCTAssertThrowsError(try InviteCodeGenerator.decode(""))
    }

    // MARK: - Verify

    func testVerify_validPayload_doesNotThrow() {
        let payload = InviteCodeGenerator.generateDevice(
            instanceName: "Mac",
            lanHint: nil,
            nostrPubkey: "validpubkey",
            nostrRelays: []
        )
        XCTAssertNoThrow(try InviteCodeGenerator.verify(payload))
    }

    func testVerify_emptyNpub_throws() {
        let payload = InvitePayload(macNpub: "", displayName: "Mac", relays: [], lanHint: nil)
        XCTAssertThrowsError(try InviteCodeGenerator.verify(payload))
    }

    func testVerify_emptyDisplayName_throws() {
        let payload = InvitePayload(macNpub: "validkey", displayName: "", relays: [], lanHint: nil)
        XCTAssertThrowsError(try InviteCodeGenerator.verify(payload))
    }

    // MARK: - Base64url encoding

    func testBase64urlEncode_noStandardBase64Chars() {
        let data = Data([0xFB, 0xFF, 0xFE, 0xFD, 0xFC])
        let encoded = InviteCodeGenerator.base64urlEncode(data)
        XCTAssertFalse(encoded.contains("+"), "base64url must replace + with -")
        XCTAssertFalse(encoded.contains("/"), "base64url must replace / with _")
        XCTAssertFalse(encoded.contains("="), "base64url must strip padding")
    }

    func testBase64urlEncode_roundtripVariousLengths() throws {
        for length in [1, 2, 3, 4, 16, 31, 32, 33, 64, 100] {
            let data = Data((0..<length).map { UInt8($0 % 256) })
            let encoded = InviteCodeGenerator.base64urlEncode(data)
            // Decode by reversing the base64url transform
            var padded = encoded
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let rem = padded.count % 4
            if rem != 0 { padded += String(repeating: "=", count: 4 - rem) }
            XCTAssertEqual(Data(base64Encoded: padded), data,
                           "base64url roundtrip failed for length \(length)")
        }
    }

    // MARK: - QR code

    func testQRCode_producesValidImage() throws {
        let payload = InviteCodeGenerator.generateDevice(
            instanceName: "QR Test",
            lanHint: nil,
            nostrPubkey: "qrpubkey",
            nostrRelays: []
        )
        let image = InviteCodeGenerator.qrCode(for: payload, size: 300)
        XCTAssertNotNil(image, "qrCode(for:) must return a non-nil CGImage")
        if let img = image {
            XCTAssertGreaterThan(img.width, 0)
            XCTAssertGreaterThan(img.height, 0)
        }
    }

    // MARK: - Deep link parsing

    func testDeepLinkParsing_connectInvite() {
        let url = URL(string: "odyssey://connect?invite=abc123def456")!
        let intent = LaunchIntent.fromURL(url)
        XCTAssertNotNil(intent, "odyssey://connect?invite=... should produce a LaunchIntent")
        guard let intent else { return }
        switch intent.mode {
        case .connectInvite(let payload):
            XCTAssertEqual(payload, "abc123def456")
        default:
            XCTFail("Expected .connectInvite mode, got \(intent.mode)")
        }
    }

    func testDeepLinkParsing_missingInviteParam_returnsNil() {
        let url = URL(string: "odyssey://connect")!
        let intent = LaunchIntent.fromURL(url)
        XCTAssertNil(intent, "odyssey://connect without invite= should return nil")
    }
}
