import SwiftUI

struct AgentActivityBar: View {
    let sessions: [Session]
    let sessionActivity: [String: AppState.SessionActivityState]

    var body: some View {
        let items = sessions.map { session -> AgentActivityItem in
            let key = session.id.uuidString
            let state = sessionActivity[key] ?? .idle
            return AgentActivityItem(
                id: session.id,
                name: session.agent?.name ?? "Agent",
                state: state
            )
        }

        if !items.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(items) { item in
                    agentPill(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .xrayId("chat.agentActivityBar")
        }
    }

    private func agentPill(_ item: AgentActivityItem) -> some View {
        HStack(spacing: 4) {
            ActivityDot(state: item.state)
                .frame(width: 6, height: 6)

            Text(item.name)
                .font(.caption2)
                .fontWeight(.medium)

            Text(item.state.displayLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(item.state.displayColor.opacity(0.1))
        .clipShape(Capsule())
        .xrayId("chat.agentPill.\(item.id.uuidString)")
        .accessibilityLabel("\(item.name): \(item.state.displayLabel)")
    }
}

// MARK: - Supporting Types

private struct AgentActivityItem: Identifiable {
    let id: UUID
    let name: String
    let state: AppState.SessionActivityState
}

struct ActivityDot: View {
    let state: AppState.SessionActivityState
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(state.displayColor)
            .scaleEffect(state.isActive && pulsing ? 1.0 : (state.isActive ? 0.5 : 1.0))
            .opacity(state.isActive && !pulsing ? 0.5 : 1.0)
            .animation(
                state.isActive
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
            .onAppear {
                if state.isActive { pulsing = true }
            }
            .onChange(of: state.isActive) { _, active in
                pulsing = active
            }
            .xrayId("activityDot")
            .accessibilityLabel(state.displayLabel)
    }
}

// Uses FlowLayout from AgentPreviewCard.swift
