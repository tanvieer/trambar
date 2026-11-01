#!/usr/bin/env bash
# Build TramBar.app: a menu bar app, so no Dock icon (LSUIElement), and a real
# bundle because Location Services and "open at login" both need one.
#
#   ./build.sh               build for this Mac's architecture
#   UNIVERSAL=1 ./build.sh   arm64 + x86_64 (needs full Xcode, not just the CLT)
#
# Homebrew runs this too, inside its own sandbox, where SwiftPM's sandbox
# cannot nest; it sets SWIFTPM_DISABLE_SANDBOX=1.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.0.0)}"
APP="build/TramBar.app"

flags=(-c release)
[[ "${UNIVERSAL:-0}" == 1 ]] && flags+=(--arch arm64 --arch x86_64)
[[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == 1 ]] && flags+=(--disable-sandbox)

swift build "${flags[@]}"
BIN="$(swift build "${flags[@]}" --show-bin-path)/TramBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TramBar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.tanvieer.trambar</string>
  <key>CFBundleName</key><string>TramBar</string>
  <key>CFBundleDisplayName</key><string>TramBar</string>
  <key>CFBundleExecutable</key><string>TramBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocationUsageDescription</key><string>TramBar shows departures from the stops nearest to you.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>TramBar shows departures from the stops nearest to you.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. Built on the Mac that runs it, the app carries no
# quarantine flag, so Gatekeeper never asks — no Developer ID needed.
codesign --force --sign - "$APP"
echo "built $APP ($VERSION)"
