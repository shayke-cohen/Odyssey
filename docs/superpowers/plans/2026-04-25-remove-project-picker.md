# Remove Project Picker from Launch Flow

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app always opens straight to `MainWindowView` with no project pre-selected; the project picker is shown only in Cmd+O new-window windows.

**Architecture:** `WindowState` gets a no-project `init()`. `ProjectWindowContent` creates it immediately in `onAppear` so `MainWindowView` renders right away. The Cmd+O sentinel (`initialProjectDirectory == ""`) is the only path that still shows `ProjectPickerView`. The inspector files tab already hides itself when `projectDirectory` is empty — no change needed there.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, macOS 14+

---

## File Map

| File | Change |
|---|---|
| `Odyssey/App/WindowState.swift` | Add no-project `init()` |
| `Odyssey/App/OdysseyApp.swift` | Remove `preferredProject()`, rework `ProjectWindowContent` body + onAppear + initializeWindow |

---

### Task 1: Add no-project `init()` to `WindowState`

**Files:**
- Modify: `Odyssey/App/WindowState.swift:300-304`

- [ ] **Step 1: Add the new init alongside the existing one**

In `WindowState.swift`, after the `init(project: Project)` (around line 300), add:

```swift
    init(project: Project) {
        self.selectedProjectId = project.id
        self.currentProjectDirectory = project.rootPath
        self.currentProjectDisplayName = project.name
    }

    init() {
        self.selectedProjectId = nil
        self.currentProjectDirectory = ""
        self.currentProjectDisplayName = ""
    }
```

- [ ] **Step 2: Build to confirm no errors**

```bash
cd /Users/shayco/Odyssey && make build-check
```
Expected: `✓ Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add Odyssey/App/WindowState.swift
git commit -m "feat: add no-project WindowState init"
```

---

### Task 2: Rework `ProjectWindowContent` launch flow

**Files:**
- Modify: `Odyssey/App/OdysseyApp.swift`

This task makes three targeted changes to `ProjectWindowContent`:
1. Add a `showPicker` computed var
2. Rework `body` to use it
3. Rework `onAppear` + `initializeWindow` methods

- [ ] **Step 1: Add `showPicker` computed var and update `body`**

Replace the current `effectiveDirectory` computed var and `body` block in `ProjectWindowContent`:

Current `effectiveDirectory`:
```swift
    private var effectiveDirectory: String? {
        // Empty string means "show picker" (from Cmd+O)
        if let chosen = chosenDirectory, !chosen.isEmpty { return chosen }
        if let initial = initialProjectDirectory, !initial.isEmpty { return initial }
        return nil
    }
```

Replace with:
```swift
    private var effectiveDirectory: String? {
        if let chosen = chosenDirectory, !chosen.isEmpty { return chosen }
        if let initial = initialProjectDirectory, !initial.isEmpty { return initial }
        return nil
    }

    // Show the picker only for Cmd+O windows (sentinel = empty string) until a dir is chosen
    private var showPicker: Bool {
        initialProjectDirectory == "" && chosenDirectory == nil
    }
```

Replace the current `body` block:
```swift
    var body: some View {
        Group {
            if let ws = windowState {
                MainWindowView()
                    .environment(ws)
            } else if effectiveDirectory != nil {
                ProgressView("Opening project\u{2026}")
            } else {
                ProjectPickerView { path in
                    chosenDirectory = path
                }
            }
        }
```

With:
```swift
    var body: some View {
        Group {
            if let ws = windowState {
                if showPicker {
                    ProjectPickerView { path in
                        chosenDirectory = path
                    }
                    .environment(ws)
                } else {
                    MainWindowView()
                        .environment(ws)
                }
            }
        }
```

- [ ] **Step 2: Rework `onAppear` — initialize `WindowState` immediately, remove `preferredProject()` call**

Replace the end of the `onAppear` block (the part after `DefaultsSeeder.migrateConfigAgentToUlyssesIfNeeded`):

Current (from the `#if DEBUG` block onward through the end of `onAppear`):
```swift
            // If we already have an explicit directory (CLI arg or Cmd+O), initialize immediately.
            // Otherwise auto-open the most recently used project (returning users only).
            if let dir = effectiveDirectory {
                initializeWindow(projectDirectory: dir)
            } else if let project = preferredProject() {
                initializeWindow(project: project)
            }
```

Replace with:
```swift
            // Create WindowState immediately — no project required.
            // MainWindowView renders right away; project is selected via sidebar click.
            let ws = WindowState()
            ws.appState = appState
            windowState = ws

            // If an explicit directory was provided (CLI arg), open it straight away.
            if let dir = effectiveDirectory {
                initializeWindow(projectDirectory: dir)
            }
```

- [ ] **Step 3: Remove `preferredProject()` and update `initializeWindow` methods**

Remove the entire `preferredProject()` method:
```swift
    private func preferredProject() -> Project? {
        let descriptor = FetchDescriptor<Project>()
        let projects = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
        guard !projects.isEmpty else { return nil }
        let lastDir = InstanceConfig.userDefaults.string(forKey: AppSettings.instanceWorkingDirectoryKey)
        if let lastDir {
            let canonical = ProjectRecords.canonicalPath(for: lastDir)
            if let match = projects.first(where: { $0.canonicalRootPath == canonical }) {
                return match
            }
        }
        return projects.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt }).first
    }
```

Replace `initializeWindow(projectDirectory:)` — it can now assume `windowState` exists:
```swift
    private func initializeWindow(projectDirectory: String) {
        let project = ProjectRecords.upsertProject(at: projectDirectory, in: modelContainer.mainContext)
        initializeWindow(project: project)
    }
```
(No change needed here — it already delegates to `initializeWindow(project:)`.)

Replace `initializeWindow(project:)` to use the existing `windowState` instead of creating one:
```swift
    private func initializeWindow(project: Project) {
        guard let ws = windowState else { return }
        ws.selectProject(project)

        InstanceConfig.userDefaults.set(project.rootPath, forKey: AppSettings.instanceWorkingDirectoryKey)
        RecentDirectories.add(project.rootPath)

        if let intent = launchIntent {
            let ctx = modelContainer.mainContext
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                appState.executeLaunchIntent(intent, modelContext: ctx, windowState: ws)
            }
        }
    }
```

- [ ] **Step 4: Fix `navigationTitle` — handle empty `projectName`**

Replace the current `navigationTitle` modifier:
```swift
        .navigationTitle(windowState.map { "Odyssey — \($0.projectName)" } ?? (InstanceConfig.isDefault ? "Odyssey" : "Odyssey — \(InstanceConfig.name)"))
```

With:
```swift
        .navigationTitle({
            if let ws = windowState, !ws.projectName.isEmpty {
                return "Odyssey \u{2014} \(ws.projectName)"
            }
            return InstanceConfig.isDefault ? "Odyssey" : "Odyssey \u{2014} \(InstanceConfig.name)"
        }())
```

- [ ] **Step 5: Also update `onChange(of: effectiveDirectory)` — it should only open project, not create state**

The `onChange` handler currently guards `windowState == nil`. Since `windowState` is now always set, remove that guard:

Current:
```swift
        .onChange(of: effectiveDirectory) { _, newDir in
            if let dir = newDir, windowState == nil {
                initializeWindow(projectDirectory: dir)
            }
        }
```

Replace with:
```swift
        .onChange(of: effectiveDirectory) { _, newDir in
            if let dir = newDir {
                initializeWindow(projectDirectory: dir)
            }
        }
```

- [ ] **Step 6: Build**

```bash
cd /Users/shayco/Odyssey && make build-check
```
Expected: `✓ Build succeeded`

- [ ] **Step 7: Commit**

```bash
git add Odyssey/App/OdysseyApp.swift
git commit -m "feat: open MainWindowView directly at launch, no project picker

App now starts without requiring a project selection. ProjectPickerView
is shown only in Cmd+O new-window windows (empty-string sentinel).
Inspector files tab already hides itself when no project directory is set."
```
