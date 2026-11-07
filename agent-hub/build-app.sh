#!/bin/bash
# Builds the CLI and the menu bar app, bundles both into Agent Hub.app and installs them.
set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")" && pwd)"
readonly APP="$ROOT/.build/Agent Hub.app"
readonly INSTALLED_APP="$HOME/Applications/Agent Hub.app"
readonly CLI_LINK="$HOME/.local/bin/agent-hub"
# Liquid Glass needs the macOS 26+ SDK; the default Xcode stays untouched for Unity iOS builds.
readonly LIQUID_GLASS_XCODE="/Applications/Xcode-27.app/Contents/Developer"

if [[ -d "$LIQUID_GLASS_XCODE" ]]; then
    export DEVELOPER_DIR="$LIQUID_GLASS_XCODE"
else
    echo "warning: $LIQUID_GLASS_XCODE not found, building with the default Xcode; the panel falls back to imitation glass" >&2
fi

# A stable certificate keeps the macOS Documents permission across rebuilds; ad-hoc signing resets it every time.
signing_identity="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')"
if [[ -z "$signing_identity" ]]; then
    echo "warning: no Apple Development identity found, signing ad-hoc; macOS will ask for Documents access after every rebuild" >&2
    signing_identity="-"
fi

swift build --package-path "$ROOT" -c release
bin_dir="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$bin_dir/AgentHubBar" "$bin_dir/agent-hub" "$APP/Contents/MacOS/"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Agent Hub</string>
    <key>CFBundleIdentifier</key><string>io.github.gallopingdino.agenthub</string>
    <key>CFBundleExecutable</key><string>AgentHubBar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "$signing_identity" "$APP/Contents/MacOS/agent-hub"
codesign --force --sign "$signing_identity" "$APP"

pkill -x AgentHubBar || true
mkdir -p "$(dirname "$INSTALLED_APP")" "$(dirname "$CLI_LINK")"
rm -rf "$INSTALLED_APP"
cp -R "$APP" "$INSTALLED_APP"
ln -sf "$INSTALLED_APP/Contents/MacOS/agent-hub" "$CLI_LINK"

echo "$INSTALLED_APP"
