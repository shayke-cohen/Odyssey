import SwiftUI

struct PairingSettingsTab: View {
    @State private var showingAcceptInvite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                iOSPairingSettingsView()

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Accept Invite")
                        .font(.headline)
                    Text("Pair with another Mac by pasting an invite code from their Odyssey app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Accept Invite Code…") {
                        showingAcceptInvite = true
                    }
                    .accessibilityIdentifier("settings.pairing.acceptInviteButton")
                }

                Divider()

                MatrixAccountView()
            }
            .padding(24)
        }
        .accessibilityIdentifier("settings.pairing.root")
        .sheet(isPresented: $showingAcceptInvite) {
            AcceptInviteView()
                .frame(minWidth: 480, minHeight: 360)
        }
    }
}
