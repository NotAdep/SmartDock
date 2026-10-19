#!/bin/bash
# Builds SmartDock.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/SmartDock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/SmartDock" "$APP/Contents/MacOS/SmartDock"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# A stable signing identity keeps the Accessibility grant across rebuilds;
# ad-hoc signing ("-") makes macOS ask again after every build.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SmartDock 2>/dev/null && sleep 0.5 || true
    rm -rf /Applications/SmartDock.app
    cp -R "$APP" /Applications/
    open /Applications/SmartDock.app
    echo "Installed and launched /Applications/SmartDock.app"
fi
