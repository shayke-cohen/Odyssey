// OdysseyiOS/App/OdysseyiOSApp.swift
import SwiftUI
import OdysseyCore

@main
struct OdysseyiOSApp: App {
    @State private var appState = iOSAppState()
    @State private var hasPairedMac: Bool = PeerCredentialStore().hasPairedMacs

    var body: some Scene {
        WindowGroup {
            Group {
                if hasPairedMac {
                    MainTabView()
                        .environment(appState)
                        .task {
                            await appState.connectToFirstPairedMac()
                        }
                } else {
                    iOSPairingView {
                        hasPairedMac = true
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification
                )
            ) { _ in
                Task { await appState.sidecarManager.reconnectIfNeeded() }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didEnterBackgroundNotification
                )
            ) { _ in
                Task { await appState.sidecarManager.suspendForBackground() }
            }
        }
    }
}

// MARK: - Main tab view

struct MainTabView: View {
    @Environment(iOSAppState.self) private var appState

    var body: some View {
        TabView {
            ConversationListView()
                .tabItem {
                    Label("Conversations", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityIdentifier("tab.conversations")

            iOSAgentListView()
                .tabItem {
                    Label("Agents", systemImage: "person.2")
                }
                .accessibilityIdentifier("tab.agents")

            iOSSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("tab.settings")
        }
    }
}

// MARK: - PeerCredentialStore convenience

private extension PeerCredentialStore {
    var hasPairedMacs: Bool {
        (try? load()).map { !$0.isEmpty } ?? false
    }
}
