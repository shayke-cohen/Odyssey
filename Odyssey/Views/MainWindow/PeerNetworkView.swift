import SwiftUI
import SwiftData

struct PeerNetworkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var p2p: P2PNetworkManager
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState: WindowState

    @Query(sort: \NostrPeer.pairedAt, order: .reverse) private var nostrPeers: [NostrPeer]
    @Query(sort: \Agent.name) private var agents: [Agent]

    @State private var selectedPeerId: String?
    @State private var showAddToChatSheet = false

    private var selectedPeer: DiscoveredLanPeer? {
        guard let selectedPeerId else { return nil }
        return p2p.peers.first { $0.id == selectedPeerId }
    }

    private var selectedNostrPeer: NostrPeer? {
        guard let id = selectedPeerId, id.hasPrefix("nostr_") else { return nil }
        guard let uuid = UUID(uuidString: String(id.dropFirst(6))) else { return nil }
        return nostrPeers.first { $0.id == uuid }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Peer Network")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .xrayId("peerNetwork.title")
                Spacer()
                Circle()
                    .fill(p2p.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                    .xrayId("peerNetwork.statusDot")
                if appState.nostrRelayTotal > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.nostrRelayCount > 0 ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(appState.nostrRelayCount > 0
                             ? "\(appState.nostrRelayCount)/\(appState.nostrRelayTotal) relays"
                             : "Connecting to relays…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("peerNetwork.nostrRelayStatus")
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .xrayId("peerNetwork.closeButton")
                .accessibilityLabel("Close")
            }
            .padding(16)

            Divider()

            if let err = p2p.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(friendlyMessage(for: err))
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button("Try Again") {
                        p2p.stop()
                        p2p.attach(modelContext: modelContext)
                        p2p.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
                .xrayId("peerNetwork.bannerError")
            }

            HSplitView {
                peerListColumn
                    .frame(minWidth: 200, idealWidth: 240)
                detailColumn
                    .frame(minWidth: 320)
            }
            .frame(minHeight: 220)

            Divider()

            HStack {
                Button("Refresh") {
                    p2p.stop()
                    p2p.attach(modelContext: modelContext)
                    p2p.start()
                }
                .xrayId("peerNetwork.refreshButton")
                Spacer()
                Text("Connect to peers and chat across Odyssey instances.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(width: 720, height: 440)
        .onAppear {
            if !p2p.isRunning {
                p2p.attach(modelContext: modelContext)
                p2p.start()
            }
        }
    }

    // MARK: - Peer List

    private var peerListColumn: some View {
        Group {
            if p2p.peers.isEmpty && nostrPeers.isEmpty && appState.nostrDirectoryPeers.isEmpty && appState.nostrPublicKeyHex == nil {
                ContentUnavailableView(
                    "No Peers Found",
                    systemImage: "wifi.exclamationmark",
                    description: Text("Ensure other Macs run Odyssey on the same network or add peers via Nostr invite.")
                )
                .xrayId("peerNetwork.emptyPeers")
            } else {
                List(selection: $selectedPeerId) {
                    if !p2p.peers.isEmpty {
                        Section("Local Network (Bonjour)") {
                            ForEach(p2p.peers, id: \.id) { peer in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.displayName)
                                        .font(.headline)
                                    if !peer.metadata.isEmpty {
                                        Text(peer.metadata)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(peer.id)
                                .xrayId("peerNetwork.peerRow.\(peer.id)")
                            }
                        }
                    }

                    if !nostrPeers.isEmpty {
                        Section("Internet Peers (Nostr)") {
                            ForEach(nostrPeers) { peer in
                                HStack {
                                    Image(systemName: "globe")
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(peer.displayName)
                                            .font(.body)
                                        Text(peer.pubkeyHex.prefix(16) + "…")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospaced()
                                    }
                                    Spacer()
                                    if let lastSeen = peer.lastSeenAt {
                                        Text(lastSeen, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Never seen")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(nostrPeerTag(peer.id))
                                .xrayId("peerNetwork.nostrPeerRow.\(peer.id.uuidString)")
                                .contextMenu {
                                    Button("Copy Pubkey") {
                                        copyToClipboard(peer.pubkeyHex)
                                    }
                                    .xrayId("peerNetwork.copyPubkeyButton.\(peer.id.uuidString)")
                                    Button("Remove Peer", role: .destructive) {
                                        removePeer(peer)
                                    }
                                    .xrayId("peerNetwork.removePeerButton.\(peer.id.uuidString)")
                                }
                            }
                        }
                    }

                    if appState.nostrPublicKeyHex != nil {
                        Section("Internet Directory") {
                            selfDirectoryRow

                            ForEach(appState.nostrDirectoryPeers.filter { peer in
                                peer.pubkeyHex != appState.nostrPublicKeyHex &&
                                !nostrPeers.contains { $0.pubkeyHex == peer.pubkeyHex }
                            }) { peer in
                                HStack(spacing: 10) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(peer.displayName)
                                            .font(.body)
                                        if !peer.agents.isEmpty {
                                            Text(peer.agents.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text(peer.pubkeyHex.prefix(16) + "…")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospaced()
                                    }
                                    Spacer()
                                    Button("Connect") {
                                        connectToDirectoryPeer(peer)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .xrayId("peerNetwork.directoryConnectButton.\(peer.pubkeyHex.prefix(8))")
                                }
                                .xrayId("peerNetwork.directoryPeerRow.\(peer.pubkeyHex.prefix(8))")
                            }
                        }
                    }
                }
                .xrayId("peerNetwork.peerList")
            }
        }
    }

    // MARK: - Detail

    private var detailColumn: some View {
        Group {
            if let peer = selectedPeer {
                peerDetailView(
                    nostrPeer: nil,
                    name: peer.displayName,
                    caption: "On your local network",
                    agents: [],
                    lastSeen: nil
                )
            } else if let peer = selectedNostrPeer {
                let dirAgents = appState.nostrDirectoryPeers
                    .first { $0.pubkeyHex == peer.pubkeyHex }?.agents ?? []
                peerDetailView(
                    nostrPeer: peer,
                    name: peer.displayName,
                    caption: String(peer.pubkeyHex.prefix(16)) + "…",
                    agents: dirAgents,
                    lastSeen: peer.lastSeenAt
                )
            } else {
                ContentUnavailableView(
                    "Select a Peer",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Choose an Odyssey instance on your network.")
                )
                .xrayId("peerNetwork.selectPeerPlaceholder")
            }
        }
    }

    @ViewBuilder
    private func peerDetailView(nostrPeer: NostrPeer?, name: String, caption: String, agents: [String], lastSeen: Date?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .xrayId("peerNetwork.detailTitle")
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let lastSeen {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Last seen")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(lastSeen, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Online", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            if !agents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agents")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Text(agents.joined(separator: " · "))
                        .font(.callout)
                }
            }

            Divider()

            // Chat actions
            Button {
                if let peer = nostrPeer {
                    startPeerChatAndDismiss(peer)
                }
            } label: {
                Label("New Chat with \(name)", systemImage: "bubble.left.and.bubble.right.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(nostrPeer == nil)
            .xrayId("peerNetwork.newChatButton")

            Button {
                if nostrPeer != nil {
                    showAddToChatSheet = true
                }
            } label: {
                Label("Add to Existing Chat…", systemImage: "plus.bubble.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(nostrPeer == nil || windowState.selectedConversationId == nil)
            .xrayId("peerNetwork.addToChatButton")

            Text("Messages route through the encrypted Nostr channel.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showAddToChatSheet) {
            if let convId = windowState.selectedConversationId {
                AddAgentsToChatSheet(conversationId: convId)
            }
        }
    }

    private func startPeerChatAndDismiss(_ peer: NostrPeer) {
        let conversation = Conversation(topic: nil, sessions: [], projectId: nil, threadKind: .direct)
        let userParticipant = Participant(type: .user, displayName: "You")
        let peerParticipant = Participant(type: .nostrPeer(pubkeyHex: peer.pubkeyHex), displayName: peer.displayName)
        userParticipant.conversation = conversation
        peerParticipant.conversation = conversation
        conversation.participants = [userParticipant, peerParticipant]
        modelContext.insert(conversation)
        windowState.selectedConversationId = conversation.id
        Task { @MainActor in
            try? modelContext.save()
        }
        dismiss()
    }

    // MARK: - Helpers

    private func friendlyMessage(for error: String) -> String {
        let prefixes = ["NSURLErrorDomain", "Error Domain=", "The operation couldn't be completed."]
        var msg = error
        for prefix in prefixes {
            if msg.hasPrefix(prefix) {
                msg = "Network error — check your connection."
                break
            }
        }
        if msg.count > 80 {
            msg = String(msg.prefix(80)) + "…"
        }
        return msg
    }

    private func removePeer(_ peer: NostrPeer) {
        let name = peer.displayName
        modelContext.delete(peer)
        try? modelContext.save()
        Task {
            try? await appState.sidecarManager?.send(.nostrRemovePeer(name: name))
        }
    }

    private func copyToClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func nostrPeerTag(_ peerId: UUID) -> String {
        "nostr_\(peerId.uuidString)"
    }

    private var selfDirectoryRow: some View {
        let relayConnected = appState.nostrRelayCount > 0
        let displayName = InstanceConfig.userDefaults.string(forKey: AppSettings.sharedRoomDisplayNameKey)
            ?? Host.current().localizedName
            ?? "This Mac"
        let agentNames = agents.map { $0.name }
        let pubkeyPrefix = appState.nostrPublicKeyHex.map { String($0.prefix(16)) + "…" } ?? ""

        return HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(displayName)
                        .font(.body)
                    Text("You")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.18))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
                if !agentNames.isEmpty {
                    Text(agentNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(pubkeyPrefix)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(relayConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(relayConnected ? "Registered" : "Registering…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .xrayId("peerNetwork.selfDirectoryRow")
    }

    private func connectToDirectoryPeer(_ peer: AppState.DirectoryPeer) {
        if let existing = nostrPeers.first(where: { $0.pubkeyHex == peer.pubkeyHex }) {
            existing.displayName = peer.displayName
            existing.relays = peer.relays
            existing.lastSeenAt = peer.seenAt
        } else {
            let nostrPeer = NostrPeer(
                displayName: peer.displayName,
                pubkeyHex: peer.pubkeyHex,
                relays: peer.relays
            )
            modelContext.insert(nostrPeer)
        }
        Task {
            try? await appState.sidecarManager?.send(.nostrAddPeer(
                name: peer.displayName,
                pubkeyHex: peer.pubkeyHex,
                relays: peer.relays
            ))
        }
    }
}
