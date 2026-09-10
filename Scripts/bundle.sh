#!/bin/sh
# Builds Foldy and wraps it in Foldy.app, ad-hoc signed, at build/Foldy.app.
#
#   Scripts/bundle.sh            release build
#   Scripts/bundle.sh debug      debug build
#
# Screen Recording permission is granted per bundle identifier, which is why the
# bare `swift run` binary is not enough for the live desktop.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Foldy.app"

swift build -c "$CONFIG" --product Foldy
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Foldy"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Foldy"
cp Support/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f Support/Foldy.icns ]; then
  cp Support/Foldy.icns "$APP/Contents/Resources/Foldy.icns"
fi

codesign --force --sign - --identifier dev.alexey1312.Foldy "$APP" >/dev/null
echo "built $APP"
