#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/build/Yacht.app"
# Release builds pass the tag (e.g. "1.2.0"); local builds fall back to a
# placeholder rather than a stale hardcoded number.
version="${1:-0.0.0-dev}"

swift build -c release --package-path "$root"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/Yacht" "$app/Contents/MacOS/Yacht"

cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Yacht</string>
  <key>CFBundleDisplayName</key>     <string>Yacht</string>
  <key>CFBundleIdentifier</key>      <string>local.yacht</string>
  <key>CFBundleExecutable</key>      <string>Yacht</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>$version</string>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <!-- Menu bar only: no Dock icon, no app switcher entry. -->
  <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# Seal the bundle: the launch-at-login ticket needs a properly signed bundle,
# and an unsealed ad-hoc one is exactly what SMAppService tends to reject.
codesign --force --deep --sign - "$app"

echo "built: $app"
