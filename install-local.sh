#!/bin/bash
# Build, replace the installed app in /Applications and relaunch it (for local testing).
# Same Developer ID signature as releases, so the Accessibility permission carries over.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
APP="build/Jot.app"
DEST="/Applications/Jot.app"
LEGACY="/Applications/Qiaomu OB Shortcut.app"     # name before 1.3.0
pkill -f "$DEST/Contents/MacOS/Jot" || true
pkill -f "$LEGACY/Contents/MacOS/QiaomuOB" || true
sleep 0.5
if [ -d "$LEGACY" ]; then mv "$LEGACY" ~/.Trash/ && echo "Moved old app to Trash: $LEGACY"; fi
rm -rf "$DEST"
ditto "$APP" "$DEST"
codesign --verify --deep --strict "$DEST"
open "$DEST"
echo "Installed and relaunched: $DEST ($(cat VERSION))"
