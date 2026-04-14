// Odyssey/Services/NATTraversalManager.swift
import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "NATTraversal")

/// Discovers the machine's public WAN endpoint via STUN (RFC 5389) and
/// optionally attempts UDP hole-punching to a remote peer.
@MainActor
final class NATTraversalManager: ObservableObject {

    // MARK: - Published State

    /// The discovered public endpoint, e.g. "203.0.113.5:9849", or nil.
    @Published var publicEndpoint: String? = nil

    @Published var stunStatus: STUNStatus = .idle

    enum STUNStatus: Equatable {
        case idle
        case discovering
        case success
        case failed(String)
    }

    // MARK: - Constants

    nonisolated fileprivate static let stunHost = "stun.l.google.com"
    nonisolated fileprivate static let stunPort: UInt16 = 19302
    nonisolated static let magicCookie: UInt32 = 0x2112_A442

    // MARK: - STUN Discovery

    /// Sends a STUN Binding Request over UDP to stun.l.google.com:19302 and
    /// parses the XOR-MAPPED-ADDRESS (or MAPPED-ADDRESS) from the response.
    ///
    /// - Parameter localPort: The UDP local port to bind (should match the sidecar WS port).
    func discoverPublicEndpoint(localPort: Int) async {
        stunStatus = .discovering
        publicEndpoint = nil

        do {
            let endpoint = try await Self.performSTUNRequest(localPort: localPort)
            publicEndpoint = endpoint
            stunStatus = .success
            logger.info("STUN discovery succeeded: \(endpoint)")
        } catch {
            stunStatus = .failed(error.localizedDescription)
            logger.error("STUN discovery failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Hole-Punch

    /// Attempts UDP hole-punch to the peer's public endpoint by sending
    /// small keepalive packets and waiting for a reply.
    ///
    /// - Parameters:
    ///   - peerEndpoint: "ip:port" string of the remote peer.
    ///   - localPort: UDP local port to bind.
    /// - Returns: A ready `NWConnection` on success, or `nil` on failure.
    func holePunch(to peerEndpoint: String, localPort: Int) async -> NWConnection? {
        guard let (host, port) = Self.parseEndpoint(peerEndpoint) else {
            logger.error("holePunch: cannot parse endpoint '\(peerEndpoint)'")
            return nil
        }

        let params = NWParameters.udp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("0.0.0.0"),
            port: NWEndpoint.Port(rawValue: UInt16(clamping: max(0, localPort))) ?? .any
        )
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: 9849),
            using: params
        )

        return await withCheckedContinuation { continuation in
            let hp = HolePunchState(continuation: continuation)
            let queue = DispatchQueue(label: "com.odyssey.p2p.holepunch")

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ping = Data("ODYSSEY-PUNCH".utf8)
                    conn.send(content: ping, completion: .contentProcessed { _ in })
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { _, _, _, _ in
                        hp.complete(with: conn, cancel: nil)
                    }
                    queue.asyncAfter(deadline: .now() + 3) {
                        hp.complete(with: nil, cancel: conn)
                    }
                case .failed:
                    hp.complete(with: nil, cancel: nil)
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    // MARK: - Internal STUN Implementation

    nonisolated static func performSTUNRequest(localPort: Int) async throws -> String {
        let txID = Self.randomTransactionID()
        let request = Self.buildBindingRequest(transactionID: txID)

        return try await withCheckedThrowingContinuation { continuation in
            let state = STUNState(transactionID: txID, continuation: continuation)
            let fetch = STUNFetch(localPort: localPort, request: request, state: state)
            fetch.start()
        }
    }

    /// Builds the 20-byte STUN Binding Request header (RFC 5389 §6).
    nonisolated static func buildBindingRequest(transactionID: Data) -> Data {
        precondition(transactionID.count == 12)
        var buf = Data(count: 20)
        buf[0] = 0x00
        buf[1] = 0x01
        buf[2] = 0x00
        buf[3] = 0x00
        buf[4] = 0x21
        buf[5] = 0x12
        buf[6] = 0xA4
        buf[7] = 0x42
        buf.replaceSubrange(8..<20, with: transactionID)
        return buf
    }

    /// Generates 12 cryptographically random bytes for a STUN transaction ID.
    nonisolated static func randomTransactionID() -> Data {
        var bytes = [UInt8](repeating: 0, count: 12)
        for i in 0..<12 { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes)
    }

    /// Parses a STUN Binding Response, returning "ip:port" from XOR-MAPPED-ADDRESS (0x0020)
    /// or MAPPED-ADDRESS (0x0001) if the former is absent.
    nonisolated static func parseBindingResponse(_ data: Data) throws -> String {
        guard data.count >= 20 else { throw STUNError.truncatedResponse }

        let msgType = (UInt16(data[0]) << 8) | UInt16(data[1])
        guard msgType == 0x0101 else { throw STUNError.unexpectedMessageType(msgType) }

        let cookie = (UInt32(data[4]) << 24) | (UInt32(data[5]) << 16)
                   | (UInt32(data[6]) << 8)  |  UInt32(data[7])
        guard cookie == magicCookie else { throw STUNError.badMagicCookie }

        let messageLength = Int((UInt16(data[2]) << 8) | UInt16(data[3]))
        guard data.count >= 20 + messageLength else { throw STUNError.truncatedResponse }

        var offset = 20
        var xorMapped: String? = nil
        var mapped: String? = nil

        while offset + 4 <= 20 + messageLength {
            let attrType = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
            let attrLen  = Int((UInt16(data[offset + 2]) << 8) | UInt16(data[offset + 3]))
            let valueStart = offset + 4
            guard valueStart + attrLen <= data.count else { throw STUNError.truncatedResponse }

            switch attrType {
            case 0x0020:
                xorMapped = try parseXORMappedAddress(data, at: valueStart)
            case 0x0001:
                mapped = try parseMappedAddress(data, at: valueStart)
            default:
                break
            }
            offset = valueStart + ((attrLen + 3) & ~3)
        }

        if let addr = xorMapped { return addr }
        if let addr = mapped { return addr }
        throw STUNError.noAddressAttribute
    }

    // MARK: - Attribute Parsers

    nonisolated static func parseXORMappedAddress(_ data: Data, at offset: Int) throws -> String {
        guard offset + 8 <= data.count else { throw STUNError.truncatedResponse }
        let family = data[offset + 1]
        guard family == 0x01 else { throw STUNError.unsupportedAddressFamily(family) }

        let xorPort = (UInt16(data[offset + 2]) << 8) | UInt16(data[offset + 3])
        let port = xorPort ^ UInt16(magicCookie >> 16)

        let xorAddr = (UInt32(data[offset + 4]) << 24)
                    | (UInt32(data[offset + 5]) << 16)
                    | (UInt32(data[offset + 6]) << 8)
                    |  UInt32(data[offset + 7])
        let addr = xorAddr ^ magicCookie

        let ip = "\((addr >> 24) & 0xFF).\((addr >> 16) & 0xFF).\((addr >> 8) & 0xFF).\(addr & 0xFF)"
        return "\(ip):\(port)"
    }

    nonisolated static func parseMappedAddress(_ data: Data, at offset: Int) throws -> String {
        guard offset + 8 <= data.count else { throw STUNError.truncatedResponse }
        let family = data[offset + 1]
        guard family == 0x01 else { throw STUNError.unsupportedAddressFamily(family) }

        let port = (UInt16(data[offset + 2]) << 8) | UInt16(data[offset + 3])
        let a0 = data[offset + 4], a1 = data[offset + 5]
        let a2 = data[offset + 6], a3 = data[offset + 7]
        return "\(a0).\(a1).\(a2).\(a3):\(port)"
    }

    // MARK: - Helpers

    nonisolated static func parseEndpoint(_ endpoint: String) -> (host: String, port: UInt16)? {
        let parts = endpoint.split(separator: ":").map(String.init)
        guard parts.count == 2, let port = UInt16(parts[1]) else { return nil }
        return (parts[0], port)
    }
}

// MARK: - Hole-Punch State (thread-safe continuation guard)

private final class HolePunchState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<NWConnection?, Never>

    init(continuation: CheckedContinuation<NWConnection?, Never>) {
        self.continuation = continuation
    }

    /// Resumes the continuation exactly once.
    /// - Parameters:
    ///   - conn: The connection to return (nil signals failure).
    ///   - cancel: An optional connection to cancel before returning nil.
    func complete(with conn: NWConnection?, cancel: NWConnection?) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        guard shouldResume else { return }
        cancel?.cancel()
        continuation.resume(returning: conn)
    }
}

// MARK: - STUN Errors

enum STUNError: LocalizedError {
    case truncatedResponse
    case unexpectedMessageType(UInt16)
    case badMagicCookie
    case unsupportedAddressFamily(UInt8)
    case noAddressAttribute
    case timeout

    var errorDescription: String? {
        switch self {
        case .truncatedResponse:              return "STUN response was truncated."
        case .unexpectedMessageType(let t):   return "Unexpected STUN message type: 0x\(String(t, radix: 16))."
        case .badMagicCookie:                 return "STUN magic cookie mismatch."
        case .unsupportedAddressFamily(let f): return "Unsupported address family: \(f). Only IPv4 is supported."
        case .noAddressAttribute:             return "STUN response contained no address attribute."
        case .timeout:                        return "STUN server did not respond in time."
        }
    }
}

// MARK: - STUN UDP Fetch (NWConnection wrapper)

private final class STUNState: @unchecked Sendable {
    let transactionID: Data
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<String, Error>

    init(transactionID: Data, continuation: CheckedContinuation<String, Error>) {
        self.transactionID = transactionID
        self.continuation = continuation
    }

    func complete(with result: Result<String, Error>, conn: NWConnection) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        guard shouldResume else { return }
        conn.cancel()
        switch result {
        case .success(let addr): continuation.resume(returning: addr)
        case .failure(let err):  continuation.resume(throwing: err)
        }
    }
}

private final class STUNFetch: @unchecked Sendable {
    private let conn: NWConnection
    private let state: STUNState
    private let queue = DispatchQueue(label: "com.odyssey.p2p.stun")

    init(localPort: Int, request: Data, state: STUNState) {
        let params = NWParameters.udp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("0.0.0.0"),
            port: NWEndpoint.Port(rawValue: UInt16(clamping: max(0, localPort))) ?? .any
        )
        self.conn = NWConnection(
            host: NWEndpoint.Host(NATTraversalManager.stunHost),
            port: NWEndpoint.Port(rawValue: NATTraversalManager.stunPort)!,
            using: params
        )
        self.state = state
        let req = request
        let s = state
        let c = conn
        let q = queue
        conn.stateUpdateHandler = { connState in
            switch connState {
            case .ready:
                c.send(content: req, completion: .contentProcessed { err in
                    if let err { s.complete(with: .failure(err), conn: c); return }
                    c.receive(minimumIncompleteLength: 20, maximumLength: 512) { data, _, _, error in
                        if let error { s.complete(with: .failure(error), conn: c); return }
                        guard let data else { s.complete(with: .failure(STUNError.truncatedResponse), conn: c); return }
                        do {
                            let addr = try NATTraversalManager.parseBindingResponse(data)
                            s.complete(with: .success(addr), conn: c)
                        } catch {
                            s.complete(with: .failure(error), conn: c)
                        }
                    }
                })
            case .failed(let err):
                s.complete(with: .failure(err), conn: c)
            default:
                break
            }
        }
        q.asyncAfter(deadline: .now() + 5) { [fetch = self] in
            _ = fetch
            s.complete(with: .failure(STUNError.timeout), conn: c)
        }
    }

    func start() {
        conn.start(queue: queue)
    }
}
