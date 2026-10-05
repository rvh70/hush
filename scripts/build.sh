#!/usr/bin/env bash
# Builds Hush.app into ./build. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/Hush.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Hush "$APP/Contents/MacOS/Hush"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Hush || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Hush.app
    cp -R "$APP" ~/Applications/Hush.app
    open ~/Applications/Hush.app
    echo "Installed to ~/Applications/Hush.app"
fi
