import SwiftUI
import SwiftData

struct PeerNetworkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var p2p: P2PNetworkManager

    @State private var selectedPeerId: String?
    @State private var peerSourceUUID = UUID()
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
                    .accessibilityIdentifier("peerNetwork.title")
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("peerNetwork.closeButton")
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
                    .accessibilityIdentifier("peerNetwork.bannerError")
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
                .accessibilityIdentifier("peerNetwork.refreshButton")
                Spacer()
                Text("Advertising local agents for LAN import.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(width: 720, height: 520)
        .onAppear {
            p2p.attach(modelContext: modelContext)
            p2p.start()
        }
        .onDisappear {
            p2p.stop()
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
                .accessibilityIdentifier("peerNetwork.emptyPeers")
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
                    .accessibilityIdentifier("peerNetwork.peerRow.\(peer.id)")
                }
                .accessibilityIdentifier("peerNetwork.peerList")
            }
        }
        .onChange(of: selectedPeerId) { _, newId in
            if newId != nil {
                peerSourceUUID = UUID()
                remoteAgents = []
                listError = nil
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if let peer = selectedPeer {
                VStack(alignment: .leading, spacing: 12) {
                    Text(peer.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("peerNetwork.detailTitle")

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
                        .accessibilityIdentifier("peerNetwork.browseAgentsButton")
                    }

                    if let listError {
                        Text(listError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("peerNetwork.listError")
                    }

                    if let importMessage {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("peerNetwork.importMessage")
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
                                importAgent(agent)
                            }
                            .disabled(importInFlight)
                            .accessibilityIdentifier("peerNetwork.importButton.\(agent.id.uuidString)")
                        }
                    }
                    .accessibilityIdentifier("peerNetwork.remoteAgentList")
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "Select a Peer",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Choose a ClaudPeer instance on your network.")
                )
                .accessibilityIdentifier("peerNetwork.selectPeerPlaceholder")
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

    private func importAgent(_ w: WireAgentExport) {
        importInFlight = true
        importMessage = nil
        defer { importInFlight = false }
        do {
            let agent = try PeerAgentImporter.importFromWire(w, peerSourceId: peerSourceUUID, modelContext: modelContext)
            importMessage = "Imported “\(agent.name)”."
            p2p.refreshExportCache()
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
