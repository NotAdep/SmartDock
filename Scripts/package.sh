#!/bin/bash
# Builds a shareable SmartDock-<version>.dmg in ./build/release.
#
# The app inside is universal (Apple Silicon + Intel) and signed with a
# self-signed "NotAdep Code Signing" certificate. Because every release carries
# the same certificate, macOS treats updates as the same app and keeps their
# Accessibility access. Without that certificate it falls back to ad-hoc
# signing, which works but resets the permission on every update.
#
# It isn't notarised (that needs a paid Apple Developer account), so recipients
# approve it once in System Settings; see "Install" in the README.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
OUT="build/release"
STAGE="$OUT/dmg"
DMG="$OUT/SmartDock-$VERSION.dmg"
IDENTITY="${RELEASE_IDENTITY:-NotAdep Code Signing}"

if ! security find-identity -p codesigning | grep -q -F "\"$IDENTITY\""; then
    echo "warning: no \"$IDENTITY\" certificate; signing ad-hoc (Accessibility resets on update)" >&2
    IDENTITY="-"
fi

rm -rf "$OUT"
mkdir -p "$STAGE"

CODESIGN_IDENTITY="$IDENTITY" ARCHS="arm64 x86_64" OUT_DIR="$STAGE" STRIP=1 ./build.sh

# Make sure nothing personal ended up in the signature: the only certificate
# allowed is the release one, and it may not mention you.
AUTHORITIES="$(codesign -dvv "$STAGE/SmartDock.app" 2>&1 | sed -n 's/^Authority=//p')"
if [[ "$IDENTITY" == "-" && -n "$AUTHORITIES" ]] || [[ "$IDENTITY" != "-" && "$AUTHORITIES" != "$IDENTITY" ]]; then
    echo "error: unexpected signing certificate: $AUTHORITIES" >&2
    exit 1
fi
if [[ "$IDENTITY" != "-" ]]; then
    CERT_TEXT="$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -text)"
    if grep -q -i -F "$USER" <<<"$CERT_TEXT" || grep -q -E "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+" <<<"$CERT_TEXT"; then
        echo "error: the signing certificate contains your username or an email address" >&2
        exit 1
    fi
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
