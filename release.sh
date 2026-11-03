#!/bin/bash
# Release: build → DMG (drag to Applications) → sign → notarize → staple → verify.
#   ./release.sh              full release (notarization takes a few minutes)
#   SKIP_NOTARIZE=1 ./release.sh   local test DMG only
# NOTARY_PROFILE defaults to "notary" (xcrun notarytool store-credentials, stored on this Mac).
set -euo pipefail
cd "$(dirname "$0")"
NAME="Jot"
VOLUME="乔木闪记"
VERSION=$(cat VERSION)
APP="build/$NAME.app"
DMG="dist/Jot-$VERSION.dmg"

RELEASE=1 ./build.sh
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/')
[ -n "$IDENTITY" ] || { echo "需要 Developer ID Application 证书"; exit 1; }

# dmgbuild writes the Finder layout without scripting Finder.
if [ ! -x build/.venv/bin/dmgbuild ]; then
  python3 -m venv build/.venv
  build/.venv/bin/pip install --quiet "dmgbuild==1.6.5"
fi
swift scripts/dmg-background.swift build/dmg-background.png build/dmg-background@2x.png
tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png -out build/dmg-background.tiff >/dev/null

mkdir -p dist
rm -f "$DMG"
build/.venv/bin/dmgbuild -s scripts/dmg-settings.py -D app="$APP" -D background=build/dmg-background.tiff "$VOLUME" "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:-notary}" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature -vv "$DMG"
  cp "$DMG" "dist/Jot.dmg"                 # fixed-name copy for "latest" download links
fi
echo "DMG: $DMG"
