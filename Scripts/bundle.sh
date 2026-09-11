#!/bin/sh
# Builds Foldy and wraps it in Foldy.app at build/Foldy.app, with Sparkle.framework embedded.
#
#   Scripts/bundle.sh            release build
#   Scripts/bundle.sh debug      debug build
#
# Signing: with CODESIGN_IDENTITY set (e.g. "Developer ID Application: Name (TEAMID)")
# everything is signed with that identity, hardened runtime and a timestamp; otherwise
# ad-hoc. Sparkle's nested pieces are re-signed first so library validation under the
# hardened runtime accepts them. Screen Recording permission is granted per bundle
# identifier, which is why the bare `swift run` binary is not enough for the live desktop.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Foldy.app"

swift build -c "$CONFIG" --product Foldy
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Foldy"
SPARKLE="$(find .build/artifacts -path '*macos-arm64_x86_64/Sparkle.framework' -maxdepth 8 -type d | head -1)"
test -d "$SPARKLE" || { echo "Sparkle.framework not found under .build/artifacts; run swift package resolve" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Foldy"
cp Support/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f Support/Foldy.icns ]; then
  cp Support/Foldy.icns "$APP/Contents/Resources/Foldy.icns"
fi
cp -R "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

# One signer for every piece; the identity carries spaces, so it stays quoted here.
sign() {
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$@"
  else
    codesign --force --sign - "$@"
  fi
}
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$FW/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
sign "$FW/Autoupdate"
sign "$FW/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  sign --entitlements Support/Foldy.entitlements "$APP"
  echo "signed $APP as $CODESIGN_IDENTITY"
else
  sign --identifier dev.alexey1312.Foldy "$APP"
  echo "built $APP (ad-hoc signed)"
fi
