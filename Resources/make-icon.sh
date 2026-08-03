#!/bin/bash
# Regenerates Resources/AppIcon.icns from docs/assets/icon-v0.1.6.svg.
#
# Not run by build.sh or CI — the .icns is committed, so a release build needs
# no SVG toolchain. Run this by hand when the source artwork changes.
# Needs rsvg-convert (brew install librsvg); sips and iconutil ship with macOS.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/docs/assets/icon-v0.1.6.svg"
out="$root/Resources/AppIcon.icns"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v rsvg-convert >/dev/null || {
  echo "need rsvg-convert: brew install librsvg" >&2
  exit 1
}

# The source art is a full-bleed square. macOS app icons are a rounded rect
# inset in a transparent canvas — at 1024 that is an 824pt box at (100,100)
# with a 185pt corner radius. Skipping this makes the icon sit visibly larger
# and squarer than every other icon in the Dock and Finder.
rsvg-convert -w 824 -h 824 "$src" -o "$work/base.png"
base64 -i "$work/base.png" | tr -d '\n' >"$work/base.b64"

{
  printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="1024" viewBox="0 0 1024 1024">'
  printf '%s' '<defs><clipPath id="squircle"><rect x="100" y="100" width="824" height="824" rx="185" ry="185"/></clipPath></defs>'
  printf '%s' '<g clip-path="url(#squircle)"><image x="100" y="100" width="824" height="824" xlink:href="data:image/png;base64,'
  cat "$work/base.b64"
  printf '%s' '"/></g></svg>'
} >"$work/masked.svg"

iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
rsvg-convert -w 1024 -h 1024 "$work/masked.svg" -o "$work/icon_1024.png"

# The sizes Finder, the Dock, alerts and Get Info actually look for.
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  px="${spec%% *}"
  name="${spec##* }"
  sips -z "$px" "$px" "$work/icon_1024.png" --out "$iconset/icon_$name.png" >/dev/null
done

iconutil -c icns "$iconset" -o "$out"
echo "wrote: $out"
