# Parallel Odyssey Instances — Design Spec

**Date:** 2026-04-21
**Status:** Approved

## Context

Running two Odyssey.app processes simultaneously fails today because both claim the same WebSocket port (9849) and HTTP port (9850), and the second process opens the same SwiftData store — causing a port conflict and potential data corruption.

Multi-instance infrastructure already exists (`InstanceConfig`, `--instance` flag, `findFreePort()`), but two gaps prevent it from working automatically:

1. No mechanism to auto-assign a unique instance name when the user opens a second window without passing `--instance`
2. `SidecarManager.Config` is initialized without `instanceName`, so non-default instances use the wrong Keychain keys for their WS bearer token and Nostr keypair

## Goal

Opening a second Odyssey window (with or without `--instance`) must work without any manual intervention — separate ports, separate data, separate sidecar process, no collisions.

## Design

### Lock-based auto-naming (InstanceConfig.swift)

`InstanceConfig.name` is a `static let` evaluated lazily on first access (in `OdysseyApp.init()`, before SwiftData is opened). Auto-naming is added here so the resolved name flows through all downstream computed properties automatically: `isDefault`, `baseDirectory`, `dataDirectory`, `logDirectory`, `userDefaultsSuiteName`, and port allocation.

**Mechanism:** when no `--instance` flag is given, the process attempts to acquire an exclusive non-blocking `flock()` on `~/.odyssey/instances/default/.instance.lock`.

- If acquired → instance name is `"default"` (first process, unchanged behavior)
- If not acquired → instance name is `"instance-<8-char-uuid>"` (second+ process)

The lock fd is kept open in a `static var _lockFd: Int32` for the process lifetime. On process exit, the fd is closed and the lock is released, making `default` available again.

```swift
static let name: String = {
    // Explicit --instance flag: always use as-is
    if let idx = args.firstIndex(of: "--instance"), idx + 1 < args.count {
        return args[idx + 1]
    }
    // No flag: race for "default"
    if tryAcquireLock(for: "default") { return "default" }
    return "instance-\(UUID().uuidString.prefix(8).lowercased())"
}()
```

`tryAcquireLock(for:)`:

1. Creates the instance base directory (`~/.odyssey/instances/<name>/`) if it doesn't exist
2. Opens (or creates) `.instance.lock` in that directory
3. Calls `flock(fd, LOCK_EX | LOCK_NB)`
4. Returns `true` if acquired, `false` if `EWOULDBLOCK`

### Cascade from the resolved name

Once `name` resolves, no other InstanceConfig code changes:

| Property | Default instance | Auto-named instance |
| --- | --- | --- |
| `isDefault` | `true` | `false` |
| `baseDirectory` | `~/.odyssey/instances/default/` | `~/.odyssey/instances/instance-<id>/` |
| `dataDirectory` | `.../default/data/` | `.../instance-<id>/data/` |
| `userDefaultsSuiteName` | `com.odyssey.app.default` | `com.odyssey.app.instance-<id>` |
| Port allocation | Fixed (9849/9850) | `findFreePort()` |

SwiftData store, blackboard, logs, and Keychain keys are all isolated automatically.

### Bug fix (AppState.swift)

In `initializeSidecar()` at line 674, `SidecarManager.Config` is missing `instanceName`. This causes non-default instances to look up Keychain entries under `"default"`, getting the wrong WS bearer token and Nostr keypair.

**Fix:** add `instanceName: InstanceConfig.name` to the `SidecarManager.Config` initializer.

### Window title indicator (OdysseyApp.swift)

When `!InstanceConfig.isDefault`, the window title appends the instance name so the user can distinguish windows:

- Default: `"Odyssey"` (unchanged)
- Second instance: `"Odyssey — instance-a3f2c1b0"` or `"Odyssey — my-project"` (if named)

The window title at line 454 of OdysseyApp.swift already reads `.navigationTitle(windowState.map { "Odyssey — \($0.projectName)" } ?? "Odyssey")`. The instance suffix is added as a fallback suffix independent of project name.

## Files Changed

| File | Change | Size |
| --- | --- | --- |
| `Odyssey/App/InstanceConfig.swift` | Lock acquisition in `name`, `tryAcquireLock()` helper, `_lockFd` static | +30 lines |
| `Odyssey/App/AppState.swift` | Add `instanceName: InstanceConfig.name` to `SidecarManager.Config` init | +1 line |
| `Odyssey/App/OdysseyApp.swift` | Instance name suffix in window title when non-default | +3 lines |

## What Does Not Change

- Explicit `--instance <name>` continues to work exactly as before
- Default instance behavior is identical (lock acquired on first launch, fixed ports)
- No new external dependencies
- Sidecar port passing, data directory passing, and all other SidecarManager logic unchanged

## Verification

1. Build and launch Odyssey (`make build-check`)
1. Open a second Odyssey window: `open -n /Applications/Odyssey.app` (no `--instance`)
1. Confirm second window title shows `"Odyssey — instance-<id>"`
1. Confirm both sidecars are running on different ports:

```sh
lsof -iTCP -sTCP:LISTEN | grep bun
```

1. Confirm second instance has its own data directory:

```sh
ls ~/.odyssey/instances/
```

1. Close second window → lock released → opening another second window gets a fresh auto-name
1. `make feedback` passes on both changes
