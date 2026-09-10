#!/bin/sh
# Renders Support/Foldy.icns from the MacBook preview scene.
set -eu
cd "$(dirname "$0")/.."
swift build --product foldy-snapshot >/dev/null
BIN="$(swift build --show-bin-path)/foldy-snapshot"
TMP="$(mktemp -d)"
"$BIN" --out "$TMP/master.png" --scene macbook --lid 118 --width 1024 --height 1024 --background clear >/dev/null
SET="$TMP/Foldy.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" "$TMP/master.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z "$double" "$double" "$TMP/master.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Support/Foldy.icns
rm -rf "$TMP"
echo "wrote Support/Foldy.icns"
