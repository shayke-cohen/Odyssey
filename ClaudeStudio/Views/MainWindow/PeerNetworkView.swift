import SwiftUI
import SwiftData

struct PeerNetworkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var p2p: P2PNetworkManager

    @State private var selectedPeerId: String?
    @State private var remoteAgents: [WireAgentExport] = []
    @State private var isLoadingList = false
    @State private var listError: String?
    @State private var importMessage: String?
    @State private var importInFlight = false

    private var selectedPeer: DiscoveredLanPeer? {
        guard let selectedPeerId else { return nil }
        return p2p.peers.first { $0.id == selectedPeerId }
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
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .xrayId("peerNetwork.bannerError")
            }

            HSplitView {
                peerListColumn
                    .frame(minWidth: 200, idealWidth: 240)
                detailColumn
                    .frame(minWidth: 320)
            }
            .frame(minHeight: 360)

            Divider()

            HStack {
                Button("Refresh browse") {
                    p2p.stop()
                    p2p.attach(modelContext: modelContext)
                    p2p.start()
                }
                .xrayId("peerNetwork.refreshButton")
                Spacer()
                Text("Advertising local agents for LAN import.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(width: 720, height: 520)
        .onAppear {
            if !p2p.isRunning {
                p2p.attach(modelContext: modelContext)
                p2p.start()
            }
        }
    }

    private var peerListColumn: some View {
        Group {
            if p2p.peers.isEmpty {
                ContentUnavailableView(
                    "No Peers Found",
                    systemImage: "wifi.exclamationmark",
                    description: Text("Ensure other Macs run ClaudPeer on the same network.")
                )
                .xrayId("peerNetwork.emptyPeers")
            } else {
                List(p2p.peers, id: \.id, selection: $selectedPeerId) { peer in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.displayName)
                            .font(.headline)
                        if !peer.metadata.isEmpty {
                            Text(peer.metadata)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .xrayId("peerNetwork.peerRow.\(peer.id)")
                }
                .xrayId("peerNetwork.peerList")
            }
        }
        .onChange(of: selectedPeerId) { _, newId in
            if newId != nil {
                remoteAgents = []
                listError = nil
                importMessage = nil
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if let peer = selectedPeer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(peer.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .xrayId("peerNetwork.detailTitle")
                        Spacer()
                        Label("Relay ready", systemImage: "arrow.left.arrow.right.circle")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .xrayId("peerNetwork.relayStatus")
                    }

                    HStack {
                        Button {
                            Task { await loadAgents(from: peer) }
                        } label: {
                            if isLoadingList {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Browse agents")
                            }
                        }
                        .disabled(isLoadingList)
                        .xrayId("peerNetwork.browseAgentsButton")
                    }

                    if let listError {
                        Text(listError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .xrayId("peerNetwork.listError")
                    }

                    if let importMessage {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .xrayId("peerNetwork.importMessage")
                    }

                    List(remoteAgents) { agent in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(agent.name)
                                    .font(.body)
                                Text(agent.model)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Import") {
                                importAgent(agent, peerName: peer.displayName)
                            }
                            .disabled(importInFlight)
                            .xrayId("peerNetwork.importButton.\(agent.id.uuidString)")
                        }
                    }
                    .xrayId("peerNetwork.remoteAgentList")
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "Select a Peer",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Choose a ClaudPeer instance on your network.")
                )
                .xrayId("peerNetwork.selectPeerPlaceholder")
            }
        }
    }

    private func loadAgents(from peer: DiscoveredLanPeer) async {
        isLoadingList = true
        listError = nil
        defer { isLoadingList = false }
        do {
            remoteAgents = try await p2p.fetchAgents(from: peer)
            if remoteAgents.isEmpty {
                listError = "No agents returned."
            }
        } catch {
            listError = error.localizedDescription
            remoteAgents = []
        }
    }

    private func importAgent(_ w: WireAgentExport, peerName: String) {
        importInFlight = true
        importMessage = nil
        defer { importInFlight = false }
        do {
            let result = try PeerAgentImporter.importFromWire(w, peerDisplayName: peerName, modelContext: modelContext)
            var msg = "Imported \"\(result.agent.name)\"."
            let missing = result.missingSkills + result.missingMCPs + [result.missingPermission].compactMap { $0 }
            if !missing.isEmpty {
                msg += " Missing locally: \(missing.joined(separator: ", "))."
            }
            importMessage = msg
            p2p.refreshExportCache()
        } catch {
            importMessage = error.localizedDescription
        }
    }
}
