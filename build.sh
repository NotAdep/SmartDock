#!/bin/bash
# Builds SmartDock.app into ./build. Pass --install to copy it to /Applications and launch it.
#
# Environment overrides:
#   CODESIGN_IDENTITY  signing identity; "-" for ad-hoc (default: your Apple Development cert)
#   ARCHS              e.g. "arm64 x86_64" for a universal build (default: this Mac's arch)
#   OUT_DIR            where to put SmartDock.app (default: build)
#   STRIP=1            strip debug symbols, which contain this Mac's folder paths
set -euo pipefail
cd "$(dirname "$0")"

ARCH_FLAGS=()
for arch in ${ARCHS:-}; do ARCH_FLAGS+=(--arch "$arch"); done

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

APP="${OUT_DIR:-build}/SmartDock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/SmartDock" "$APP/Contents/MacOS/SmartDock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ "${STRIP:-}" == "1" ]]; then strip -S -x "$APP/Contents/MacOS/SmartDock"; fi

# A stable signing identity keeps the Accessibility grant across rebuilds;
# ad-hoc signing ("-") makes macOS ask again after every build.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/SmartDock"), signed with: $([[ "$IDENTITY" == "-" ]] && echo ad-hoc || echo "$IDENTITY"))"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SmartDock 2>/dev/null && sleep 0.5 || true
    rm -rf /Applications/SmartDock.app
    cp -R "$APP" /Applications/
    open /Applications/SmartDock.app
    echo "Installed and launched /Applications/SmartDock.app"
fi
