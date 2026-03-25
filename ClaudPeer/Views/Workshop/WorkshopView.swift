import SwiftUI

struct WorkshopView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Workshop")
                .font(.title)
            Button("Close") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
