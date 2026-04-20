import Foundation
import CryptoKit
import P256K
import OSLog

private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var idx = hexString.startIndex
        while idx < hexString.endIndex {
            let next = hexString.index(idx, offsetBy: 2)
            guard let byte = UInt8(hexString[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        self = data
    }
}

// MARK: - NostrEventRelay

/// Bridges iOS↔Mac communication over Nostr relay.
///
/// - Receives Nostr events from iOS devices, decrypts (NIP-44), wraps as
///   `nostr.injectCommand`, and injects into the sidecar via raw WebSocket.
/// - Intercepts raw sidecar messages and forwards them to the originating iOS
///   device (NIP-44 encrypted) when the session was initiated via Nostr.
/// - Announces this Mac's Nostr identity to the sidecar on connect.
@MainActor
final class NostrEventRelay {

    private let sidecarManager: SidecarManager
    private var relayManager: NostrRelayManager?
    private var privkeyHex: String?
    private var pubkeyHex: String?

    // Sessions initiated via Nostr: sessionId → iOS sender pubkeyHex
    private var nostrSessions: [String: String] = [:]
    // Last iOS device that sent any Nostr command — used for broadcasts like conversations.list.result
    private var lastKnownIosNpub: String?

    init(sidecarManager: SidecarManager) {
        self.sidecarManager = sidecarManager
    }

    // MARK: - Start / Stop

    func start(privkeyHex: String, pubkeyHex: String, relays: [String]) {
        self.privkeyHex = privkeyHex
        self.pubkeyHex = pubkeyHex
        let manager = NostrRelayManager(
            relayURLs: relays,
            privkeyHex: privkeyHex,
            pubkeyHex: pubkeyHex,
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleIncomingNostrEvent(event)
                }
            }
        )
        relayManager = manager
        manager.connect()

        // Intercept raw sidecar messages and forward to iOS via Nostr
        sidecarManager.rawMessageInterceptor = { [weak self] rawJSON in
            self?.interceptSidecarMessage(rawJSON)
        }

        Task {
            try? await sidecarManager.send(.nostrPeerAnnounce(pubkeyHex: pubkeyHex, relays: relays))
        }
    }

    func stop() {
        relayManager?.disconnect()
        relayManager = nil
        sidecarManager.rawMessageInterceptor = nil
    }

    // MARK: - Outbound: sidecar raw JSON → iOS device via Nostr

    private func interceptSidecarMessage(_ rawJSON: String) {
        guard let data = rawJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let relay = relayManager,
              let priv = privkeyHex,
              let pub = pubkeyHex else { return }

        // For session-scoped events, route to the originating iOS device
        let msgType = json["type"] as? String
        let sessionId = (json["sessionId"] as? String) ?? (json["conversationId"] as? String)
        let iOSPubkey: String?
        if let sid = sessionId {
            iOSPubkey = nostrSessions[sid]
        } else if msgType == "conversations.list.result" || msgType == "agents.list.result" {
            iOSPubkey = lastKnownIosNpub
        } else {
            iOSPubkey = nil
        }
        guard let iOSPubkey else { return }

        Task {
            do {
                let convKey = try NIP44.conversationKey(privkeyHex: priv, peerPubkeyHex: iOSPubkey)
                let encrypted = try NIP44.encrypt(plaintext: rawJSON, conversationKey: convKey)
                let nostrEventJSON = makeEventJSON(content: encrypted, recipientPubkey: iOSPubkey, senderPubkey: pub)
                relay.publish(to: iOSPubkey, eventJSON: nostrEventJSON)
            } catch {
                Log.sidecar.error("NostrEventRelay: outbound publish failed — \(error)")
            }
        }
    }

    // MARK: - Inbound: iOS Nostr event → sidecar via nostr.injectCommand

    private func handleIncomingNostrEvent(_ event: NostrEvent) {
        guard event.kind == 4, let priv = privkeyHex, let pub = pubkeyHex else { return }
        let pTags = event.tags.filter { $0.first == "p" }
        guard pTags.contains(where: { $0.count > 1 && $0[1] == pub }) else { return }

        do {
            let convKey = try NIP44.conversationKey(privkeyHex: priv, peerPubkeyHex: event.pubkey)
            let plaintext = try NIP44.decrypt(payload: event.content, conversationKey: convKey)

            // Track last known iOS sender for broadcast routing (e.g. conversations.list.result)
            lastKnownIosNpub = event.pubkey

            // Track which sessions came from iOS for reply routing
            if let cmdData = plaintext.data(using: .utf8),
               let cmdJSON = try? JSONSerialization.jsonObject(with: cmdData) as? [String: Any] {
                let cmdType = cmdJSON["type"] as? String
                if cmdType == "session.create", let cid = cmdJSON["conversationId"] as? String {
                    nostrSessions[cid] = event.pubkey
                } else if cmdType == "session.message", let sid = cmdJSON["sessionId"] as? String {
                    nostrSessions[sid] = event.pubkey
                }
            }

            // Wrap in nostr.injectCommand and forward to sidecar
            guard let innerData = plaintext.data(using: .utf8),
                  let innerObj = try? JSONSerialization.jsonObject(with: innerData) else { return }
            let wrapper: [String: Any] = ["type": "nostr.injectCommand", "command": innerObj]
            let wrapperData = try JSONSerialization.data(withJSONObject: wrapper)
            guard let wrapperText = String(data: wrapperData, encoding: .utf8) else { return }

            Task {
                try? await self.sidecarManager.sendRaw(wrapperText)
            }
        } catch {
            Log.sidecar.debug("NostrEventRelay: decrypt failed from \(event.pubkey.prefix(8)) — \(error)")
        }
    }

    // MARK: - Helpers

    private func makeEventJSON(content: String, recipientPubkey: String, senderPubkey: String) -> String {
        guard let priv = privkeyHex,
              let privBytes = Data(hexString: priv) else { return "" }

        let timestamp = Int(Date().timeIntervalSince1970)
        let tags: [Any] = [["p", recipientPubkey]]
        let canonical: [Any] = [0, senderPubkey, timestamp, 4, tags, content]
        // .withoutEscapingSlashes is required: JSONSerialization escapes '/' as '\/' by default,
        // but relays unescape '/' when parsing before re-computing the event ID hash.
        guard let canonicalData = try? JSONSerialization.data(withJSONObject: canonical, options: .withoutEscapingSlashes) else { return "" }

        let hashDigest = SHA256.hash(data: canonicalData)
        let id = hashDigest.map { String(format: "%02x", $0) }.joined()

        guard let schnorrKey = try? P256K.Schnorr.PrivateKey(dataRepresentation: privBytes),
              let sig = try? schnorrKey.signature(for: hashDigest) else { return "" }
        let sigHex = sig.dataRepresentation.map { String(format: "%02x", $0) }.joined()

        let eventObj: [String: Any] = [
            "kind": 4,
            "created_at": timestamp,
            "tags": tags,
            "content": content,
            "pubkey": senderPubkey,
            "id": id,
            "sig": sigHex
        ]
        guard let eventData = try? JSONSerialization.data(withJSONObject: eventObj, options: .withoutEscapingSlashes),
              let eventString = String(data: eventData, encoding: .utf8) else { return "" }
        return eventString
    }
}
