#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/build/Yacht.app"
# Release tags must agree with VERSION; an explicit argument also supports previews.
version="${1:-$(cat "$root/VERSION")}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
  echo "Invalid version: $version" >&2
  exit 1
fi

# Build each slice separately so Command Line Tools are sufficient (SwiftPM's
# multi-architecture build backend requires the full Xcode installation).
binaries=()
for architecture in arm64 x86_64; do
  swift build -c release --product Yacht --arch "$architecture" --package-path "$root"
  bin_dir="$(swift build -c release --arch "$architecture" --package-path "$root" --show-bin-path)"
  binaries+=("$bin_dir/Yacht")
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Yacht"
# Prebuilt so a release build needs no SVG toolchain; see Resources/make-icon.sh.
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$root/Sources/Yacht/Resources/"*.pdf "$app/Contents/Resources/"
cp "$root/Sources/Yacht/Resources/Lobe-LICENSE.txt" "$app/Contents/Resources/"

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
  <!-- LSUIElement hides the Dock icon, but Finder, the DMG, Get Info and any
       app-modal alert still ask for this one. -->
  <key>CFBundleIconFile</key>        <string>AppIcon</string>
  <key>CFBundleIconName</key>        <string>AppIcon</string>
  <key>CFBundleShortVersionString</key> <string>$version</string>
  <key>CFBundleVersion</key>        <string>$version</string>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <!-- Menu bar only: no Dock icon, no app switcher entry. -->
  <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# Seal the bundle: the launch-at-login ticket needs a properly signed bundle,
# and an unsealed ad-hoc one is exactly what SMAppService tends to reject.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"

echo "built: $app"
