#!/bin/sh
# Renders the fold media for the promo video in videos/foldy-promo/assets/ from the real
# shader, through foldy-snapshot, and copies in the system SF Pro that the compositions use.
# Rerun after any change to the fold: the video must show the shader users get.
#
# The lid clips close 135° → 22° on a cosine ease over 90 frames (3 s at 30 fps).
# compositions/frames/04-follows-the-hinge.html drives its slider with the same formula;
# change one and the other must follow.
set -eu
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)" >&2; exit 1; }
swift build --product foldy-snapshot >/dev/null
BIN="$(swift build --show-bin-path)/foldy-snapshot"
OUT=videos/foldy-promo/assets
TMP="$(mktemp -d)"
mkdir -p "$OUT/fonts"

# frames COUNT FROM TO: one "index value" line per frame, eased (1 − cos πt) / 2 from FROM to TO.
frames() {
  awk -v n="$1" -v a="$2" -v b="$3" 'BEGIN {
    pi = atan2(0, -1)
    for (i = 0; i < n; i++) { t = i / (n - 1); printf "%03d %.4f\n", i, a + (b - a) * (1 - cos(pi * t)) / 2 }
  }'
}

for style in silk shade frost; do
  mkdir -p "$TMP/$style"
  frames 90 135 22 | while read -r i lid; do
    "$BIN" --out "$TMP/$style/$i.png" --scene macbook --lid "$lid" --style "$style" --width 1600 --background clear >/dev/null
  done
  ffmpeg -v error -y -framerate 30 -i "$TMP/$style/%03d.png" \
    -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 24 -auto-alt-ref 0 "$OUT/macbook-close-$style.webm"
  command cp -f "$TMP/$style/089.png" "$OUT/macbook-closed-$style.png"
done
ffmpeg -v error -y -framerate 30 -i "$TMP/silk/%03d.png" -vf reverse \
  -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 24 -auto-alt-ref 0 "$OUT/macbook-open-silk.webm"
command cp -f "$TMP/silk/000.png" "$OUT/macbook-open-silk.png"

# The full-bleed desktop falling back into black: fold progress 0 → 1 over 2.5 s.
mkdir -p "$TMP/flat"
frames 75 0 1 | while read -r i progress; do
  "$BIN" --out "$TMP/flat/$i.png" --progress "$progress" --style silk --width 1920 >/dev/null
done
ffmpeg -v error -y -framerate 30 -i "$TMP/flat/%03d.png" -c:v libx264 -pix_fmt yuv420p -crf 16 "$OUT/desktop-fold-silk.mp4"
command cp -f "$TMP/flat/000.png" "$OUT/desktop-flat.png"
command cp -f "$TMP/flat/074.png" "$OUT/desktop-folded-silk.png"

# SF Pro is Apple's and is not committed; every Mac has it.
command cp -f /System/Library/Fonts/SFNS.ttf "$OUT/fonts/SFNS.ttf"

rm -rf "$TMP"
echo "wrote $OUT"
