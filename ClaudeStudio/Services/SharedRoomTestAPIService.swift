import Foundation
import Network
import SwiftData

@MainActor
final class SharedRoomTestAPIService: ObservableObject {
    struct RoomSnapshot: Codable, Sendable {
        struct ParticipantSnapshot: Codable, Sendable {
            let displayName: String
            let type: String
            let isLocal: Bool
            let membershipStatus: String
            let participantId: String?
            let userId: String?
            let homeNodeId: String?
        }

        struct MessageSnapshot: Codable, Sendable {
            let text: String
            let type: String
            let senderDisplayName: String?
            let roomMessageId: String?
            let hostSequence: Int
            let deliveryMode: String?
            let timestamp: Date
        }

        let roomId: String
        let topic: String
        let status: String
        let transportMode: String
        let historySyncState: String
        let participants: [ParticipantSnapshot]
        let messages: [MessageSnapshot]
    }

    private let queue = DispatchQueue(label: "com.claudestudio.shared-room.test-api")
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private weak var sharedRoomService: SharedRoomService?
    private var modelContext: ModelContext?

    init() {
        self.port = Self.resolvePort()
    }

    func configure(sharedRoomService: SharedRoomService, modelContext: ModelContext) {
        self.sharedRoomService = sharedRoomService
        self.modelContext = modelContext
    }

    func startIfEnabled() {
        guard listener == nil else { return }
        guard Self.isEnabled else { return }

        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("SharedRoomTestAPIService failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        let state = RequestState()
        receive(on: connection, state: state)
    }

    private nonisolated func receive(on connection: NWConnection, state: RequestState) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 131_072) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                Self.send(connection, status: 500, payload: ["error": error.localizedDescription])
                return
            }

            if let data, !data.isEmpty {
                state.append(data)
            }

            if let request = HTTPRequestParser.parse(state.snapshot()) {
                Task { @MainActor in
                    let response = await self.route(request)
                    Self.send(connection, status: response.status, payload: response.payload)
                }
            } else if isComplete {
                Self.send(connection, status: 400, payload: ["error": "Invalid request"])
            } else {
                self.receive(on: connection, state: state)
            }
        }
    }

    private func route(_ request: HTTPRequestParser.Request) async -> (status: Int, payload: [String: Any]) {
        guard let sharedRoomService, modelContext != nil else {
            return (500, ["error": "Service unavailable"])
        }

        do {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return (200, [
                    "ok": true,
                    "instance": InstanceConfig.name,
                    "port": port.rawValue
                ])

            case ("POST", "/api/shared-room/create"):
                let body = try request.jsonBody()
                let topic = body["topic"] as? String ?? "Shared Room"
                let conversation = try await sharedRoomService.createLocalTestRoom(topic: topic)
                return (200, [
                    "conversationId": conversation.id.uuidString,
                    "roomId": conversation.roomId ?? ""
                ])

            case ("POST", "/api/shared-room/invite"):
                let body = try request.jsonBody()
                guard let roomId = body["roomId"] as? String,
                      let conversation = sharedRoomService.roomConversation(roomId: roomId)
                else {
                    return (404, ["error": "Room not found"])
                }
                let invite = try await sharedRoomService.createInvite(
                    for: conversation,
                    recipientLabel: body["recipientLabel"] as? String,
                    expiresIn: body["expiresIn"] as? TimeInterval ?? (24 * 60 * 60),
                    singleUse: body["singleUse"] as? Bool ?? true
                )
                return (200, [
                    "inviteId": invite.inviteId,
                    "inviteToken": invite.inviteToken ?? "",
                    "deepLink": invite.deepLink,
                    "roomId": invite.roomId
                ])

            case ("POST", "/api/shared-room/join"):
                let body = try request.jsonBody()
                guard let roomId = body["roomId"] as? String,
                      let inviteId = body["inviteId"] as? String
                else {
                    return (400, ["error": "roomId and inviteId are required"])
                }
                let conversation = try await sharedRoomService.acceptInvite(
                    roomId: roomId,
                    inviteId: inviteId,
                    inviteToken: body["inviteToken"] as? String,
                    projectId: nil
                )
                return (200, [
                    "conversationId": conversation.id.uuidString,
                    "roomId": conversation.roomId ?? roomId
                ])

            case ("POST", "/api/shared-room/send"):
                let body = try request.jsonBody()
                guard let roomId = body["roomId"] as? String,
                      let text = body["text"] as? String
                else {
                    return (400, ["error": "roomId and text are required"])
                }
                let message = try await sharedRoomService.sendLocalUserMessage(text: text, roomId: roomId)
                return (200, [
                    "messageId": message.id.uuidString,
                    "roomMessageId": message.roomMessageId ?? "",
                    "hostSequence": message.roomHostSequence
                ])

            case ("POST", "/api/shared-room/refresh"):
                let body = try request.jsonBody()
                guard let roomId = body["roomId"] as? String else {
                    return (400, ["error": "roomId is required"])
                }
                try await sharedRoomService.refreshRoom(roomId: roomId)
                return (200, ["ok": true])

            case ("GET", "/api/shared-room/state"):
                guard let roomId = request.queryValue(named: "roomId"),
                      let snapshot = sharedRoomService.roomSnapshot(roomId: roomId)
                else {
                    return (404, ["error": "Room not found"])
                }
                return (200, try Self.dictionary(from: snapshot))

            default:
                return (404, ["error": "Unknown endpoint"])
            }
        } catch {
            return (500, ["error": error.localizedDescription])
        }
    }

    private nonisolated static func send(_ connection: NWConnection, status: Int, payload: [String: Any]) {
        let body: Data
        if JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            body = data
        } else {
            body = Data("{\"error\":\"Serialization failed\"}".utf8)
        }

        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default: reason = "Internal Server Error"
        }

        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var output = Data(header.utf8)
        output.append(body)
        connection.send(content: output, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func dictionary(from snapshot: RoomSnapshot) throws -> [String: Any] {
        let data = try JSONEncoder().encode(snapshot)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CLAUDESTUDIO_TEST_API"] == "1"
    }

    private static func resolvePort() -> NWEndpoint.Port {
        if let raw = ProcessInfo.processInfo.environment["CLAUDESTUDIO_TEST_API_PORT"],
           let value = UInt16(raw),
           let port = NWEndpoint.Port(rawValue: value) {
            return port
        }
        let fallback = UInt16(InstanceConfig.findFreePort())
        return NWEndpoint.Port(rawValue: fallback) ?? 19510
    }
}

private final class RequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let current = buffer
        lock.unlock()
        return current
    }
}

private enum HTTPRequestParser {
    struct Request {
        let method: String
        let path: String
        let queryItems: [URLQueryItem]
        let body: Data

        func jsonBody() throws -> [String: Any] {
            guard !body.isEmpty else { return [:] }
            guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return [:]
            }
            return object
        }

        func queryValue(named name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }
    }

    static func parse(_ data: Data) -> Request? {
        guard let string = String(data: data, encoding: .utf8),
              let headerRange = string.range(of: "\r\n\r\n")
        else {
            return nil
        }

        let headerText = String(string[..<headerRange.lowerBound])
        let bodyText = String(string[headerRange.upperBound...])
        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        let rawPath = parts[1]
        let components = URLComponents(string: "http://localhost\(rawPath)")
        return Request(
            method: parts[0],
            path: components?.path ?? rawPath,
            queryItems: components?.queryItems ?? [],
            body: Data(bodyText.utf8)
        )
    }
}
