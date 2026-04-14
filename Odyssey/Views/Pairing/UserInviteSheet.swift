// Odyssey/Views/Pairing/UserInviteSheet.swift
import SwiftUI
import CoreImage.CIFilterBuiltins

struct UserInviteSheet: View {
    let matrixUserId: String
    let instanceName: String

    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: Image?
    @State private var inviteCode: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Share Your Profile")
                    .font(.title2.bold())

                Text(matrixUserId)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .stableXrayId("userInvite.matrixIdLabel")

                if let qr = qrImage {
                    qr
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .stableXrayId("userInvite.qrCode")
                        .accessibilityLabel("QR code for your Matrix profile invite")
                } else if let error = errorMessage {
                    Text(error).foregroundColor(.red)
                } else {
                    ProgressView()
                }

                if !inviteCode.isEmpty {
                    Button("Copy Invite Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "odyssey://connect/user?invite=\(inviteCode)",
                            forType: .string
                        )
                    }
                    .stableXrayId("userInvite.copyButton")
                    .accessibilityLabel("Copy invite link to clipboard")
                }
            }
            .padding(32)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .stableXrayId("userInvite.doneButton")
                }
            }
        }
        .task { await generateCode() }
    }

    @MainActor
    private func generateCode() async {
        do {
            let code = try InviteCodeGenerator.generateUser(
                instanceName: instanceName,
                matrixUserId: matrixUserId
            )
            inviteCode = code
            qrImage = makeQRImage(from: "odyssey://connect/user?invite=\(code)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeQRImage(from string: String) -> Image? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return Image(nsImage: nsImage)
    }
}
