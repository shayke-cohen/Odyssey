import SwiftUI

struct SidebarActivityIndicator: View {
    let summary: AppState.ConversationActivitySummary
    let conversationStatus: ConversationStatus

    @State private var pulsing = false
    @State private var showDoneCheck = false
    @State private var doneTimer: Task<Void, Never>?

    var body: some View {
        Group {
            switch summary.aggregate {
            case .working(let count):
                workingIndicator(count: count)

            case .allDone where summary.totalSessions > 0:
                if showDoneCheck {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    idleDot
                }

            case .completedWithErrors:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)

            default:
                if conversationStatus == .active {
                    idleDot
                }
            }
        }
        .onChange(of: summary.aggregate) { old, new in
            if case .allDone = new, summary.totalSessions > 0 {
                withAnimation(.easeInOut(duration: 0.3)) { showDoneCheck = true }
                doneTimer?.cancel()
                doneTimer = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.5)) { showDoneCheck = false }
                    }
                }
            } else if case .allDone = new {} else {
                showDoneCheck = false
                doneTimer?.cancel()
            }
        }
        .xrayId("sidebarActivityIndicator")
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Subviews

    private var idleDot: some View {
        Circle()
            .fill(.green)
            .frame(width: 6, height: 6)
    }

    private func workingIndicator(count: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .scaleEffect(pulsing ? 1.0 : 0.6)
                .opacity(pulsing ? 1.0 : 0.4)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: pulsing
                )
                .onAppear { pulsing = true }
                .onDisappear { pulsing = false }

            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 10, height: 10)
                    .background(Circle().fill(.blue))
                    .offset(x: 5, y: -5)
            }
        }
    }

    private var accessibilityText: String {
        switch summary.aggregate {
        case .idle:
            return conversationStatus == .active ? "Active" : ""
        case .working(let count):
            return count == 1 ? "1 agent working" : "\(count) agents working"
        case .allDone:
            return "All agents done"
        case .completedWithErrors(let errorCount):
            return "\(errorCount) agent\(errorCount == 1 ? "" : "s") failed"
        }
    }
}
