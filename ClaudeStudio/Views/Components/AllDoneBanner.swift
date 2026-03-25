import SwiftUI

struct AllDoneBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("All agents finished")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.green.opacity(0.08))
        .clipShape(Capsule())
        .xrayId("chat.allDoneBanner")
        .accessibilityLabel("All agents finished")
    }
}
