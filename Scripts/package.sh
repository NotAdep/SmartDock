#!/bin/bash
# Builds a shareable SmartDock-<version>.dmg in ./build/release.
#
# The app inside is universal (Apple Silicon + Intel) and ad-hoc signed, so it
# carries no personal certificate. It isn't notarised (that needs a paid Apple
# Developer account), so recipients approve it once in System Settings; see
# "Install" in the README.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
OUT="build/release"
STAGE="$OUT/dmg"
DMG="$OUT/SmartDock-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$STAGE"

CODESIGN_IDENTITY=- ARCHS="arm64 x86_64" OUT_DIR="$STAGE" STRIP=1 ./build.sh

# Make sure nothing personal ended up in the signature.
if codesign -dvv "$STAGE/SmartDock.app" 2>&1 | grep -q "^Authority="; then
    echo "error: app is signed with a certificate; expected ad-hoc" >&2
    exit 1
fi
if grep -r -a -q -F "$USER" "$STAGE/SmartDock.app"; then
    echo "error: the app still contains your username ($USER); not packaging it" >&2
    exit 1
fi

ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to Install.txt" <<'EOF'
1. Drag SmartDock into the Applications folder.
2. Open SmartDock from Applications. macOS will say it can't verify the app,
   because it isn't from the App Store or a paid developer. Click Done.
3. Go to System Settings → Privacy & Security, scroll down, and click
   "Open Anyway" next to SmartDock. Confirm with your password.
4. When asked, allow SmartDock in Privacy & Security → Accessibility.
   It needs this to see window sizes.

SmartDock lives in the menu bar. Open its Settings with ⌘, from the menu.
EOF

hdiutil create -quiet -volname "SmartDock" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"

echo "Packaged $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
