import SwiftUI

@MainActor
struct QuickActionsSettingsView: View {
    @ObservedObject private var store = QuickActionStore.shared
    @State private var editingConfig: QuickActionConfig? = nil
    @State private var showAddSheet = false
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                ForEach(Array(store.configs.enumerated()), id: \.element.id) { index, config in
                    HStack(spacing: 10) {
                        VStack(spacing: 0) {
                            Button {
                                store.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                            } label: {
                                Image(systemName: "chevron.up").font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(config.name) up")
                            .accessibilityIdentifier("settings.quickActions.moveUp.\(config.id.uuidString)")

                            Button {
                                store.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                            } label: {
                                Image(systemName: "chevron.down").font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(index == store.configs.count - 1)
                            .accessibilityLabel("Move \(config.name) down")
                            .accessibilityIdentifier("settings.quickActions.moveDown.\(config.id.uuidString)")
                        }
                        .foregroundStyle(.tertiary)

                        Image(systemName: config.symbolName)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)

                        Text(config.name)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Edit") { editingConfig = config }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("settings.quickActions.editButton.\(config.id.uuidString)")

                        Button {
                            store.delete(id: config.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(config.name)")
                        .accessibilityIdentifier("settings.quickActions.deleteButton.\(config.id.uuidString)")
                    }
                    .accessibilityIdentifier("settings.quickActions.row.\(config.id.uuidString)")
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add chip", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("settings.quickActions.addButton")
            } header: {
                HStack {
                    Text("Chips")
                    Spacer()
                    Button("Reset to Defaults") { showResetConfirmation = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .accessibilityIdentifier("settings.quickActions.resetButton")
                }
            } footer: {
                Text("Use ▲▼ to reorder. Changes appear immediately in the chat bar.")
                    .foregroundStyle(.secondary)
            }

            Section("Ordering") {
                Toggle("Order by usage", isOn: Binding(
                    get: { store.usageOrderEnabled },
                    set: { store.setUsageOrderEnabled($0) }
                ))
                .help("Reorders chips by how often you use them after \(QuickActionConfig.usageThreshold) total uses.")
                .accessibilityIdentifier("settings.quickActions.usageOrderToggle")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingConfig) { config in
            QuickActionEditSheet(mode: .edit, existing: config) { updated in
                store.update(updated)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            QuickActionEditSheet(mode: .add) { newConfig in
                store.add(newConfig)
            }
        }
        .confirmationDialog("Reset all chips to defaults?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive) { store.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        }
        .navigationTitle("Quick Actions")
    }
}
