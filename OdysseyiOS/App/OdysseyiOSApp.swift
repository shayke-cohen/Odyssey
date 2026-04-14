// OdysseyiOS/App/OdysseyiOSApp.swift
import SwiftUI
import UIKit
import OdysseyCore

// MARK: - App delegate (forces full-screen on iOS 26 windowed mode via size restrictions)

private final class OdysseyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UIWindow.appearance().backgroundColor = .systemBackground
        // iOS 26 introduced iPhone windowing; pin the scene to the screen size so the app
        // fills the display instead of floating in a smaller window.
        NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let scene = notification.object as? UIWindowScene else { return }
            scene.windows.forEach { $0.backgroundColor = .systemBackground }
            if let restrictions = scene.sizeRestrictions {
                let screenSize = scene.screen.bounds.size
                restrictions.minimumSize = screenSize
                restrictions.maximumSize = screenSize
            }
        }
        return true
    }
}

@main
struct OdysseyiOSApp: App {
    @UIApplicationDelegateAdaptor(OdysseyAppDelegate.self) private var appDelegate
    @State private var appState = iOSAppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentRootView()
                .environment(appState)
                .onChange(of: scenePhase) { _, newPhase in
                    Task {
                        if newPhase == .background {
                            await appState.sidecarManager.suspendForBackground()
                        } else if newPhase == .active {
                            await appState.sidecarManager.reconnectIfNeeded()
                        }
                    }
                }
        }
    }
}

// MARK: - Content root

struct ContentRootView: View {
    @Environment(iOSAppState.self) private var appState
    @State private var hasPairedMac: Bool = PeerCredentialStore().hasPairedMacs

    var body: some View {
        Group {
            if hasPairedMac {
                MainTabView()
                    .task {
                        await appState.connectToFirstPairedMac()
                    }
            } else {
                iOSPairingView {
                    hasPairedMac = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
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
