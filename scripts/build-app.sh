#!/bin/bash
# Builds build/BudsBar.app (ad-hoc signed). Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/BudsBar"

APP="build/BudsBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BudsBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/BudsBar.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "installed $HOME/Applications/BudsBar.app"
fi
