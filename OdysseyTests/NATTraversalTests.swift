// OdysseyTests/NATTraversalTests.swift
import XCTest
@testable import Odyssey

final class NATTraversalTests: XCTestCase {

    // MARK: - STUN Request Encoding

    func testSTUNRequestEncoding() {
        let txID = Data([
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C
        ])
        let request = NATTraversalManager.buildBindingRequest(transactionID: txID)

        XCTAssertEqual(request.count, 20, "STUN Binding Request must be exactly 20 bytes")
        XCTAssertEqual(request[0], 0x00)
        XCTAssertEqual(request[1], 0x01)
        XCTAssertEqual(request[2], 0x00)
        XCTAssertEqual(request[3], 0x00)
        XCTAssertEqual(request[4], 0x21)
        XCTAssertEqual(request[5], 0x12)
        XCTAssertEqual(request[6], 0xA4)
        XCTAssertEqual(request[7], 0x42)
        XCTAssertEqual(Array(request[8..<20]), [
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C
        ])
    }

    // MARK: - STUN Response Parsing

    private func syntheticXORMappedResponse(ip: UInt32, port: UInt16) -> Data {
        let magic: UInt32 = NATTraversalManager.magicCookie
        let xorPort = port ^ UInt16(magic >> 16)
        let xorAddr = ip ^ magic

        var attrValue = Data(count: 8)
        attrValue[0] = 0x00
        attrValue[1] = 0x01
        attrValue[2] = UInt8(xorPort >> 8)
        attrValue[3] = UInt8(xorPort & 0xFF)
        attrValue[4] = UInt8((xorAddr >> 24) & 0xFF)
        attrValue[5] = UInt8((xorAddr >> 16) & 0xFF)
        attrValue[6] = UInt8((xorAddr >>  8) & 0xFF)
        attrValue[7] = UInt8( xorAddr        & 0xFF)

        var attrHeader = Data(count: 4)
        attrHeader[0] = 0x00; attrHeader[1] = 0x20
        attrHeader[2] = 0x00; attrHeader[3] = 0x08

        let attrTotal = attrHeader + attrValue

        var header = Data(count: 20)
        header[0] = 0x01; header[1] = 0x01
        header[2] = 0x00; header[3] = 0x0C
        header[4] = 0x21; header[5] = 0x12; header[6] = 0xA4; header[7] = 0x42
        for i in 8..<20 { header[i] = 0x00 }

        return header + attrTotal
    }

    func testSTUNResponseParsing() throws {
        let ip: UInt32 = 0xCB00_7105
        let port: UInt16 = 9849
        let response = syntheticXORMappedResponse(ip: ip, port: port)

        let result = try NATTraversalManager.parseBindingResponse(response)
        XCTAssertEqual(result, "203.0.113.5:9849")
    }

    func testXORMappedAddressIPv4() throws {
        let magic: UInt32 = NATTraversalManager.magicCookie
        let rawPort: UInt16 = 0x2679
        let xorPort = rawPort ^ UInt16(magic >> 16)
        let xorAddr: UInt32 = 0x00000000 ^ magic

        var attrValue = Data(count: 8)
        attrValue[0] = 0x00; attrValue[1] = 0x01
        attrValue[2] = UInt8(xorPort >> 8); attrValue[3] = UInt8(xorPort & 0xFF)
        attrValue[4] = UInt8((xorAddr >> 24) & 0xFF)
        attrValue[5] = UInt8((xorAddr >> 16) & 0xFF)
        attrValue[6] = UInt8((xorAddr >>  8) & 0xFF)
        attrValue[7] = UInt8( xorAddr        & 0xFF)

        var buf = Data(count: 8)
        buf.replaceSubrange(0..<8, with: attrValue)
        let result = try NATTraversalManager.parseXORMappedAddress(buf, at: 0)

        let parts = result.split(separator: ":")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(UInt16(parts[1]), rawPort, "Port must survive XOR round-trip")
    }

    func testParseEndpointValid() {
        let result = NATTraversalManager.parseEndpoint("203.0.113.5:9849")
        XCTAssertEqual(result?.host, "203.0.113.5")
        XCTAssertEqual(result?.port, 9849)
    }

    func testParseEndpointInvalid() {
        XCTAssertNil(NATTraversalManager.parseEndpoint("notanendpoint"))
        XCTAssertNil(NATTraversalManager.parseEndpoint("192.168.1.1:notaport"))
    }

    func testTruncatedResponseThrows() {
        let shortData = Data([0x01, 0x01])
        XCTAssertThrowsError(try NATTraversalManager.parseBindingResponse(shortData))
    }

    func testBadMagicCookieThrows() {
        var data = Data(count: 20)
        data[0] = 0x01; data[1] = 0x01
        data[2] = 0x00; data[3] = 0x00
        data[4] = 0xDE; data[5] = 0xAD; data[6] = 0xBE; data[7] = 0xEF
        XCTAssertThrowsError(try NATTraversalManager.parseBindingResponse(data)) { error in
            XCTAssertEqual(error as? STUNError, STUNError.badMagicCookie)
        }
    }
}

extension STUNError: Equatable {
    public static func == (lhs: STUNError, rhs: STUNError) -> Bool {
        switch (lhs, rhs) {
        case (.truncatedResponse, .truncatedResponse): return true
        case (.badMagicCookie, .badMagicCookie): return true
        case (.noAddressAttribute, .noAddressAttribute): return true
        case (.timeout, .timeout): return true
        case (.unexpectedMessageType(let a), .unexpectedMessageType(let b)): return a == b
        case (.unsupportedAddressFamily(let a), .unsupportedAddressFamily(let b)): return a == b
        default: return false
        }
    }
}
