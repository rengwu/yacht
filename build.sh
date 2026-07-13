#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/build/ClaudeUsage.app"

swift build -c release --package-path "$root"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/ClaudeUsage" "$app/Contents/MacOS/ClaudeUsage"

cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>ClaudeUsage</string>
  <key>CFBundleDisplayName</key>     <string>Claude Usage</string>
  <key>CFBundleIdentifier</key>      <string>local.claude-usage-menubar</string>
  <key>CFBundleExecutable</key>      <string>ClaudeUsage</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
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
