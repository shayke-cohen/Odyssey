# Release Pipeline Design

**Date:** 2026-04-17
**Status:** Approved

## Goal

Enable direct (non-App-Store) distribution of Odyssey to external users, with cryptographically signed auto-updates via Sparkle.

## Architecture

Five components work together:

| Component | Purpose |
|---|---|
| Sparkle (SPM) | Auto-update framework embedded in the app |
| EdDSA keypair | Signs update packages; public key in app, private key local-only |
| `ExportOptions.plist` | Configures Developer ID export for `xcodebuild -exportArchive` |
| `scripts/release.sh` | Local script to cut a release end-to-end |
| `distribution/appcast.xml` | Sparkle feed committed to repo, updated by release script |

## 1. Sparkle Integration

### SPM Dependency

Add to `project.yml`:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
```

Add `Sparkle` to the `Odyssey` target dependencies.

### App Integration (`OdysseyApp.swift`)

Add `SPUStandardUpdaterController` as a `@StateObject`. This automatically wires up a "Check for Updates…" menu item under the application menu.

```swift
@StateObject private var updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
```

### Info.plist Keys (via `project.yml` `INFOPLIST_KEY_*`)

| Key | Value |
|---|---|
| `SUFeedURL` | `https://raw.githubusercontent.com/shayke-cohen/odyssey/main/distribution/appcast.xml` |
| `SUPublicEDKey` | Base64 public key (generated once during setup) |

### No sandbox

Odyssey runs without app sandbox, so Sparkle can replace the app bundle directly — no separate XPC installer needed.

## 2. ExportOptions.plist

Committed to `distribution/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>U6BSY4N9E3</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>hardcodedSigningIdentity</key>
    <string>Developer ID Application</string>
</dict>
</plist>
```

## 3. `scripts/release.sh`

Run as: `./scripts/release.sh 0.2.0`

### Steps

1. **Validate prerequisites** — abort if `create-dmg`, `gh`, `xcrun notarytool`, or `sign_update` (from Sparkle) are not available
2. **Bump version** — patch `MARKETING_VERSION` to the passed-in version and auto-increment `CURRENT_PROJECT_VERSION` (integer build number) in `project.yml`, then run `xcodegen generate`. Sparkle uses the build number for update ordering.
3. **Archive** — `xcodebuild archive -scheme Odyssey -archivePath /tmp/Odyssey.xcarchive`
4. **Export** — `xcodebuild -exportArchive` using `distribution/ExportOptions.plist` → signed `.app`
5. **Notarize** — `xcrun notarytool submit` (zip of `.app`), `--wait`, using Keychain profile `odyssey-notarize`
6. **Staple** — `xcrun stapler staple` the notarization ticket onto the `.app`
7. **DMG** — `create-dmg` wraps the `.app` in a signed DMG: `Odyssey-{VERSION}.dmg`
8. **Sparkle-sign** — `sign_update Odyssey-{VERSION}.dmg $SPARKLE_PRIVATE_KEY_PATH` → EdDSA signature
9. **GitHub Release** — `gh release create v{VERSION} Odyssey-{VERSION}.dmg --generate-notes`
10. **Update appcast** — script prepends a new `<item>` to `distribution/appcast.xml` using a Python one-liner (stdlib `xml.etree.ElementTree`) with version, DMG URL, EdDSA signature, and file length; then commits and pushes the file

### Error handling

- `set -euo pipefail` — any step failure aborts the script
- Temp dir cleaned up on exit via `trap`
- Each step prints a progress header for visibility

## 4. `distribution/appcast.xml`

Minimal Sparkle 2 appcast format. The release script prepends a new `<item>` on each release:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Odyssey</title>
    <item>
      <title>Version 0.1.0</title>
      <pubDate>Thu, 17 Apr 2026 00:00:00 +0000</pubDate>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
      <enclosure
        url="https://github.com/shayke-cohen/odyssey/releases/download/v0.1.0/Odyssey-0.1.0.dmg"
        sparkle:edSignature="..."
        length="..."
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

## 5. Credential Handling

| Secret | Storage | How script accesses it |
|---|---|---|
| Apple ID + app-specific password | macOS Keychain profile `odyssey-notarize` | `--keychain-profile odyssey-notarize` |
| Sparkle EdDSA private key | File at `~/.sparkle/odyssey_private_key` (never committed) | `SPARKLE_PRIVATE_KEY_PATH` env var |
| GitHub CLI token | `gh auth login` session | `gh` CLI uses existing session |

### One-time setup commands

```sh
# Store notarization credentials
xcrun notarytool store-credentials odyssey-notarize \
  --apple-id you@example.com \
  --team-id U6BSY4N9E3 \
  --password <app-specific-password>

# Download Sparkle tools (generate_keys + sign_update are CLI binaries in the
# Sparkle release ZIP — they are NOT included in the SPM package).
# Download the latest Sparkle release ZIP from:
#   https://github.com/sparkle-project/Sparkle/releases
# Extract and move the tools:
mkdir -p ~/tools/sparkle
# From the extracted ZIP: bin/generate_keys and bin/sign_update
mv path/to/extracted/bin/generate_keys ~/tools/sparkle/
mv path/to/extracted/bin/sign_update ~/tools/sparkle/
chmod +x ~/tools/sparkle/generate_keys ~/tools/sparkle/sign_update

# Generate EdDSA keypair — run once, save the output
~/tools/sparkle/generate_keys
# Private key printed to stdout → save to $SPARKLE_PRIVATE_KEY_PATH
# Public key printed to stdout → paste into project.yml as SUPublicEDKey infoplist key

# Add to ~/.zshrc or .env.local
export SPARKLE_PRIVATE_KEY_PATH="$HOME/.sparkle/odyssey_private_key"
export SIGN_UPDATE_PATH="$HOME/tools/sparkle/sign_update"
```

## Files Changed / Created

| Path | Action |
|---|---|
| `project.yml` | Add Sparkle SPM dependency + `SUFeedURL` + `SUPublicEDKey` Info.plist keys |
| `Odyssey/OdysseyApp.swift` | Add `SPUStandardUpdaterController` |
| `distribution/ExportOptions.plist` | New — Developer ID export config |
| `distribution/appcast.xml` | New — initial empty Sparkle feed |
| `scripts/release.sh` | New — full release pipeline script |

## Out of Scope

- GitHub Actions / CI automation
- App Store distribution
- Windows / Linux builds
