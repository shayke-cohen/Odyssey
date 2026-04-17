# Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Sparkle auto-update to the app, a Developer ID export config, an initial appcast feed, and a local `scripts/release.sh` that archives → notarizes → packages → publishes a DMG to GitHub Releases in one command.

**Architecture:** Sparkle 2 is added via SPM and wired into `OdysseyApp.swift` via `SPUStandardUpdaterController`. A local `scripts/release.sh` orchestrates `xcodebuild`, `xcrun notarytool`, `create-dmg`, Sparkle's `sign_update`, and `gh release create`. The appcast feed lives at `distribution/appcast.xml` (committed to the repo) and is updated by the release script on each release.

**Tech Stack:** Swift 6 / SwiftUI, Sparkle 2 (SPM), XcodeGen, `xcrun notarytool`, `create-dmg` (Homebrew), `gh` CLI, Python 3 (stdlib, for appcast XML editing)

---

## File Map

| Path | Action | Purpose |
|---|---|---|
| `project.yml` | Modify | Add Sparkle SPM package + target dep + `SUPublicEDKey` build setting |
| `Odyssey/Resources/Info.plist` | Modify | Add `SUFeedURL` and `SUPublicEDKey` keys |
| `Odyssey/App/OdysseyApp.swift` | Modify | Import Sparkle, add `SPUStandardUpdaterController`, add "Check for Updates…" menu item |
| `distribution/ExportOptions.plist` | Create | Tells `xcodebuild -exportArchive` to use Developer ID signing |
| `distribution/appcast.xml` | Create | Sparkle feed; updated by release script each release |
| `scripts/release.sh` | Create | Full release pipeline: archive → export → notarize → staple → DMG → sign → publish → appcast |

---

## Task 1: One-time pre-setup (manual — no code changes)

**Files:** None — setup steps only.

- [ ] **Step 1: Install prerequisites via Homebrew**

```bash
brew install create-dmg xcodegen gh
```

Expected: all three install (or "already installed").

- [ ] **Step 2: Download Sparkle 2 CLI tools**

The `generate_keys` and `sign_update` binaries ship in Sparkle's release ZIP — they are NOT included in the SPM package.

```bash
# Download latest Sparkle release ZIP (check https://github.com/sparkle-project/Sparkle/releases for the latest version)
curl -L -o /tmp/Sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
mkdir -p ~/tools/sparkle
tar -xJf /tmp/Sparkle.tar.xz -C /tmp/sparkle-extract 2>/dev/null || \
  (mkdir -p /tmp/sparkle-extract && tar -xf /tmp/Sparkle.tar.xz -C /tmp/sparkle-extract)
# The bin/ folder is inside the extracted archive:
find /tmp/sparkle-extract -name "generate_keys" -exec cp {} ~/tools/sparkle/ \;
find /tmp/sparkle-extract -name "sign_update" -exec cp {} ~/tools/sparkle/ \;
chmod +x ~/tools/sparkle/generate_keys ~/tools/sparkle/sign_update
ls ~/tools/sparkle/
```

Expected output: `generate_keys  sign_update`

- [ ] **Step 3: Generate EdDSA keypair**

```bash
~/tools/sparkle/generate_keys
```

Expected output (example — your values will differ):
```
A private key was generated and saved in your Keychain. To use it:
Public key (SUPublicEDKey): <BASE64_PUBLIC_KEY_STRING>

Please back up your private key file to a secure location.
```

Copy the `SUPublicEDKey` value — you'll need it in Task 2.

> **Note:** If `generate_keys` saves to the Keychain, `sign_update` will find it automatically. If it outputs a file path, set `SPARKLE_PRIVATE_KEY_PATH` to that path and pass `--ed-key-file "$SPARKLE_PRIVATE_KEY_PATH"` to `sign_update` in Task 6.

- [ ] **Step 4: Add env vars to `~/.zshrc`**

```bash
cat >> ~/.zshrc << 'EOF'
export SIGN_UPDATE_PATH="$HOME/tools/sparkle/sign_update"
# If generate_keys saved a key file (not Keychain), set this:
# export SPARKLE_PRIVATE_KEY_PATH="$HOME/.sparkle/odyssey_private_key"
EOF
source ~/.zshrc
```

- [ ] **Step 5: Store notarization credentials in Keychain**

You need an app-specific password from https://appleid.apple.com (under Security → App-Specific Passwords).

```bash
xcrun notarytool store-credentials odyssey-notarize \
  --apple-id YOUR_APPLE_ID@example.com \
  --team-id U6BSY4N9E3 \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

Expected: `Credentials saved to Keychain.`

- [ ] **Step 6: Authenticate GitHub CLI**

```bash
gh auth status
```

Expected: shows an authenticated account. If not, run `gh auth login`.

---

## Task 2: Add Sparkle SPM dependency to project.yml

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add Sparkle to the `packages` section**

In `project.yml`, find the `packages:` block (currently has AppXray, MarkdownUI, Highlightr, OdysseyCore, secp256k1) and add Sparkle:

```yaml
packages:
  AppXray:
    path: Dependencies/appxray/packages/sdk-ios
  MarkdownUI:
    url: https://github.com/gonzalezreal/swift-markdown-ui
    from: "2.4.1"
  Highlightr:
    url: https://github.com/raspu/Highlightr
    from: "2.2.1"
  OdysseyCore:
    path: Packages/OdysseyCore
  secp256k1:
    url: https://github.com/GigaBitcoin/secp256k1.swift
    from: "0.15.0"
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
```

- [ ] **Step 2: Add Sparkle to the Odyssey target `dependencies`**

In `project.yml`, find the `Odyssey:` target's `dependencies:` list (currently AppXray, MarkdownUI, Highlightr, OdysseyCore, secp256k1/P256K) and append:

```yaml
    dependencies:
      - package: AppXray
      - package: MarkdownUI
      - package: Highlightr
      - package: OdysseyCore
      - package: secp256k1
        product: P256K
      - package: Sparkle
```

- [ ] **Step 3: Regenerate Xcode project**

```bash
cd /Users/shayco/Odyssey
xcodegen generate
```

Expected: `⚙️  Generating project...` followed by `✅ Done!` (or similar success output).

- [ ] **Step 4: Verify SPM resolves**

```bash
xcodebuild -resolvePackageDependencies -scheme Odyssey 2>&1 | tail -5
```

Expected: ends with `** RESOLVE SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add project.yml Odyssey.xcodeproj/
git commit -m "chore(deps): add Sparkle 2 SPM dependency"
```

---

## Task 3: Add Sparkle Info.plist keys

**Files:**
- Modify: `Odyssey/Resources/Info.plist`

- [ ] **Step 1: Add SUFeedURL and SUPublicEDKey to Info.plist**

Replace `YOUR_PUBLIC_KEY_HERE` with the base64 string from Task 1 Step 3.

Edit `Odyssey/Resources/Info.plist` — add the two Sparkle keys inside the root `<dict>`, after the existing `CFBundleURLTypes` entry:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ODYSSEY_SOURCE_ROOT</key>
	<string>$(SRCROOT)</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.odyssey.app</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>odyssey</string>
				<!-- Legacy deep links kept for backward compatibility. -->
				<string>claudestudio</string>
				<string>claudpeer</string>
			</array>
		</dict>
	</array>
	<key>SUFeedURL</key>
	<string>https://raw.githubusercontent.com/shayke-cohen/odyssey/main/distribution/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>YOUR_PUBLIC_KEY_HERE</string>
</dict>
</plist>
```

- [ ] **Step 2: Build to verify Info.plist is valid**

```bash
xcodebuild build -scheme Odyssey -destination "platform=macOS" 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED` (no `error:` lines).

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Resources/Info.plist
git commit -m "chore(sparkle): add SUFeedURL and SUPublicEDKey to Info.plist"
```

---

## Task 4: Wire SPUStandardUpdaterController into OdysseyApp.swift

**Files:**
- Modify: `Odyssey/App/OdysseyApp.swift`

- [ ] **Step 1: Add Sparkle import and updaterController property**

At the top of `OdysseyApp.swift`, add `import Sparkle` after the existing imports:

```swift
import SwiftUI
import SwiftData
import OSLog
import Sparkle
#if DEBUG
import AppXray
#endif
```

In the `OdysseyApp` struct body, add `updaterController` after `sharedRoomTestAPIService`:

```swift
@StateObject private var appState: AppState
@StateObject private var p2pNetworkManager = P2PNetworkManager()
@StateObject private var sharedRoomService: SharedRoomService
@StateObject private var sharedRoomTestAPIService: SharedRoomTestAPIService
@StateObject private var updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
```

- [ ] **Step 2: Add "Check for Updates…" menu item**

In the `body` computed property, inside `.commands { ... }`, add a new `CommandGroup` after the existing help group:

```swift
CommandGroup(replacing: .help) {
    Button("Report a Bug...") {
        if let url = URL(string: "https://forms.gle/Cq4bWNwUVaX8zZr67") {
            NSWorkspace.shared.open(url)
        }
    }
}
CommandGroup(after: .appInfo) {
    Button("Check for Updates\u{2026}") {
        updaterController.updater.checkForUpdates()
    }
    .disabled(!updaterController.updater.canCheckForUpdates)
}
```

- [ ] **Step 3: Build to verify Sparkle wires up correctly**

```bash
xcodebuild build -scheme Odyssey -destination "platform=macOS" 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Odyssey/App/OdysseyApp.swift
git commit -m "feat(sparkle): add SPUStandardUpdaterController and Check for Updates menu item"
```

---

## Task 5: Create distribution/ExportOptions.plist

**Files:**
- Create: `distribution/ExportOptions.plist`

- [ ] **Step 1: Create the `distribution/` directory and ExportOptions.plist**

```bash
mkdir -p /Users/shayco/Odyssey/distribution
```

Create `distribution/ExportOptions.plist` with this content:

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
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

- [ ] **Step 2: Verify the plist is valid**

```bash
plutil -lint distribution/ExportOptions.plist
```

Expected: `distribution/ExportOptions.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add distribution/ExportOptions.plist
git commit -m "chore(release): add Developer ID ExportOptions.plist"
```

---

## Task 6: Create initial distribution/appcast.xml

**Files:**
- Create: `distribution/appcast.xml`

- [ ] **Step 1: Create the initial appcast feed**

Create `distribution/appcast.xml` with this content (an empty channel — the release script will add items):

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Odyssey</title>
    <link>https://github.com/shayko-cohen/odyssey</link>
    <description>Odyssey release feed</description>
    <language>en</language>
  </channel>
</rss>
```

- [ ] **Step 2: Verify the XML is well-formed**

```bash
python3 -c "import xml.etree.ElementTree as ET; ET.parse('distribution/appcast.xml'); print('OK')"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add distribution/appcast.xml
git commit -m "chore(release): add initial empty Sparkle appcast feed"
```

---

## Task 7: Write scripts/release.sh

**Files:**
- Create: `scripts/release.sh`

- [ ] **Step 1: Create the release script**

Create `scripts/release.sh`:

```bash
#!/bin/zsh
set -euo pipefail

# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.2.0

VERSION="${1:?Usage: ./scripts/release.sh <version> (e.g. 0.2.0)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/distribution"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

ARCHIVE_PATH="$TEMP_DIR/Odyssey.xcarchive"
EXPORT_DIR="$TEMP_DIR/export"
APP_PATH="$EXPORT_DIR/Odyssey.app"
ZIP_PATH="$TEMP_DIR/Odyssey-notarize.zip"
DMG_NAME="Odyssey-${VERSION}.dmg"
DMG_PATH="$TEMP_DIR/$DMG_NAME"

# ── Step 1: Validate prerequisites ──────────────────────────────────────────

echo "==> Validating prerequisites..."

for tool in xcodegen create-dmg gh xcrun plutil; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: '$tool' not found. Install via Homebrew: brew install $tool" >&2
    exit 1
  fi
done

SIGN_UPDATE="${SIGN_UPDATE_PATH:?ERROR: Set SIGN_UPDATE_PATH to the path of ~/tools/sparkle/sign_update}"
if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "ERROR: sign_update not executable at $SIGN_UPDATE" >&2
  exit 1
fi

echo "    Prerequisites OK."

# ── Step 2: Bump version ────────────────────────────────────────────────────

echo "==> Bumping version to $VERSION..."
cd "$REPO_ROOT"

# Bump MARKETING_VERSION in project.yml
sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml

# Auto-increment CURRENT_PROJECT_VERSION (Sparkle uses this for update ordering)
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*CURRENT_PROJECT_VERSION: //' | tr -d ' ')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: ${CURRENT_BUILD}/CURRENT_PROJECT_VERSION: ${NEW_BUILD}/" project.yml

echo "    Version: $VERSION  |  Build: $CURRENT_BUILD → $NEW_BUILD"

xcodegen generate
echo "    Xcode project regenerated."

# ── Step 3: Archive ─────────────────────────────────────────────────────────

echo "==> Archiving (this takes a few minutes)..."
xcodebuild archive \
  -scheme Odyssey \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=U6BSY4N9E3 \
  2>&1 | grep -E "(error:|warning: 'Odyssey'|ARCHIVE SUCCEEDED|ARCHIVE FAILED)" | tail -10

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "ERROR: Archive not found at $ARCHIVE_PATH — xcodebuild archive failed." >&2
  exit 1
fi
echo "    Archive OK: $ARCHIVE_PATH"

# ── Step 4: Export with Developer ID ────────────────────────────────────────

echo "==> Exporting with Developer ID..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$DIST_DIR/ExportOptions.plist" \
  2>&1 | grep -E "(error:|EXPORT SUCCEEDED|EXPORT FAILED)" | tail -5

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Exported app not found at $APP_PATH" >&2
  exit 1
fi
echo "    Export OK: $APP_PATH"

# ── Step 5: Notarize ────────────────────────────────────────────────────────

echo "==> Notarizing (submitting to Apple — may take a few minutes)..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile odyssey-notarize \
  --wait \
  2>&1 | tail -10

echo "    Notarization OK."

# ── Step 6: Staple ──────────────────────────────────────────────────────────

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
echo "    Staple OK."

# ── Step 7: Create DMG ──────────────────────────────────────────────────────

echo "==> Creating DMG..."
# Detect Developer ID identity from Keychain for DMG signing
CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')

CREATE_DMG_ARGS=(
  --volname "Odyssey $VERSION"
  --window-pos 200 120
  --window-size 540 380
  --icon-size 128
  --icon "Odyssey.app" 140 180
  --hide-extension "Odyssey.app"
  --app-drop-link 400 180
)

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  CREATE_DMG_ARGS+=(--codesign "$CODESIGN_IDENTITY")
  echo "    Signing DMG as: $CODESIGN_IDENTITY"
fi

create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_PATH" "$EXPORT_DIR/"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "ERROR: DMG not created at $DMG_PATH" >&2
  exit 1
fi
echo "    DMG OK: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# ── Step 8: Sparkle-sign DMG ────────────────────────────────────────────────

echo "==> Signing DMG for Sparkle..."
# sign_update outputs a line like:
#   sparkle:edSignature="BASE64SIG" length="BYTES"
# Uses Keychain by default (generate_keys saves there); pass --ed-key-file if
# SPARKLE_PRIVATE_KEY_PATH is set (for file-based key storage).
SIGN_UPDATE_ARGS=("$DMG_PATH")
if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
  SIGN_UPDATE_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_PATH")
fi
SIG_OUTPUT=$("$SIGN_UPDATE" "${SIGN_UPDATE_ARGS[@]}" 2>&1)
ED_SIGNATURE=$(echo "$SIG_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
DMG_LENGTH=$(echo "$SIG_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

# Fallback: compute length ourselves if sign_update didn't output it
if [[ -z "$DMG_LENGTH" ]]; then
  DMG_LENGTH=$(wc -c < "$DMG_PATH" | tr -d ' ')
fi

if [[ -z "$ED_SIGNATURE" ]]; then
  echo "ERROR: Could not extract EdDSA signature from sign_update output:" >&2
  echo "$SIG_OUTPUT" >&2
  exit 1
fi

echo "    EdDSA signature: ${ED_SIGNATURE:0:20}..."
echo "    DMG length: $DMG_LENGTH bytes"

# ── Step 9: GitHub Release ──────────────────────────────────────────────────

echo "==> Creating GitHub release v$VERSION..."
gh release create "v${VERSION}" "$DMG_PATH" \
  --repo shayko-cohen/odyssey \
  --title "Odyssey v${VERSION}" \
  --generate-notes

DMG_URL="https://github.com/shayko-cohen/odyssey/releases/download/v${VERSION}/${DMG_NAME}"
echo "    GitHub release OK: $DMG_URL"

# ── Step 10: Update appcast.xml ─────────────────────────────────────────────

echo "==> Updating appcast.xml..."
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
APPCAST="$DIST_DIR/appcast.xml"

python3 - "$APPCAST" "$VERSION" "$NEW_BUILD" "$PUB_DATE" "$DMG_URL" "$ED_SIGNATURE" "$DMG_LENGTH" << 'PYEOF'
import sys
import xml.etree.ElementTree as ET

appcast_path, version, build, pub_date, dmg_url, ed_sig, dmg_len = sys.argv[1:]

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")

tree = ET.parse(appcast_path)
root = tree.getroot()
channel = root.find("channel")

item = ET.Element("item")
ET.SubElement(item, "title").text = f"Version {version}"
ET.SubElement(item, "pubDate").text = pub_date
ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = build
ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = version
enc = ET.SubElement(item, "enclosure")
enc.set("url", dmg_url)
enc.set(f"{{{SPARKLE_NS}}}edSignature", ed_sig)
enc.set("length", dmg_len)
enc.set("type", "application/octet-stream")

# Prepend the new item (insert after title/link/description, before existing items)
existing_items = channel.findall("item")
for existing in existing_items:
    channel.remove(existing)
channel.append(item)
for existing in existing_items:
    channel.append(existing)

tree.write(appcast_path, encoding="unicode", xml_declaration=True)
print(f"    appcast.xml updated with v{version} (build {build}).")
PYEOF

git add "$DIST_DIR/appcast.xml" project.yml
git commit -m "chore: release v${VERSION} (build ${NEW_BUILD})"
git push

echo ""
echo "✅  Release v${VERSION} complete!"
echo "   DMG URL:     $DMG_URL"
echo "   Build:       $NEW_BUILD"
echo "   Appcast:     https://raw.githubusercontent.com/shayko-cohen/odyssey/main/distribution/appcast.xml"
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x scripts/release.sh
```

- [ ] **Step 3: Run prerequisites-only check (no build)**

Test that the script fails gracefully when a required tool is missing, by temporarily renaming it:

```bash
# Verify error path: unset SIGN_UPDATE_PATH and confirm script aborts
(unset SIGN_UPDATE_PATH; ./scripts/release.sh 0.1.0 2>&1 | head -5)
```

Expected output contains:
```
ERROR: Set SIGN_UPDATE_PATH to the path of ~/tools/sparkle/sign_update
```

- [ ] **Step 4: Commit**

```bash
git add scripts/release.sh
git commit -m "feat(release): add release.sh — archive/notarize/DMG/Sparkle/GitHub pipeline"
```

---

## Task 8: End-to-end smoke test

**Files:** None — verification only.

- [ ] **Step 1: Verify the app builds cleanly**

```bash
xcodebuild build -scheme Odyssey -destination "platform=macOS" 2>&1 \
  | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 2: Verify the "Check for Updates" menu item appears in the built app**

Launch Odyssey from Xcode (Cmd+R). Open the Odyssey application menu. Confirm "Check for Updates…" appears and is enabled.

- [ ] **Step 3: Dry-run the version bump logic**

```bash
cd /Users/shayco/Odyssey

# Check current state
grep -E "(MARKETING_VERSION|CURRENT_PROJECT_VERSION)" project.yml
```

Expected output (values will match your current project.yml):
```
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: 1
```

- [ ] **Step 4: Cut a real release (when ready)**

```bash
./scripts/release.sh 0.2.0
```

The script will:
1. Bump `project.yml` version to 0.2.0, build number to 2
2. Archive (~5 min), export, notarize (~2 min), staple
3. Create `Odyssey-0.2.0.dmg`
4. Sign it with Sparkle EdDSA key
5. Create GitHub release `v0.2.0` and upload the DMG
6. Update `distribution/appcast.xml` and push

Expected final output:
```
✅  Release v0.2.0 complete!
   DMG URL:     https://github.com/shayko-cohen/odyssey/releases/download/v0.2.0/Odyssey-0.2.0.dmg
   Build:       2
   Appcast:     https://raw.githubusercontent.com/shayko-cohen/odyssey/main/distribution/appcast.xml
```

- [ ] **Step 5: Verify appcast is valid**

After the release script runs:

```bash
python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('distribution/appcast.xml')
items = tree.getroot().find('channel').findall('item')
print(f'Items in feed: {len(items)}')
for item in items:
    print('  -', item.find('title').text)
"
```

Expected:
```
Items in feed: 1
  - Version 0.2.0
```
