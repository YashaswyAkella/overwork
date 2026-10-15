#!/bin/zsh
# Builds Overwork.app and Overwork.dmg into ./dist
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release 2>&1 | grep -v "^\[" || true
test -x .build/release/Overwork

APP=dist/Overwork.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist/iconset.iconset
cp .build/release/Overwork "$APP/Contents/MacOS/Overwork"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Icon
swift Tools/MakeIcon.swift dist/icon1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s dist/icon1024.png --out "dist/iconset.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d dist/icon1024.png --out "dist/iconset.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns dist/iconset.iconset -o "$APP/Contents/Resources/Overwork.icns"
rm -rf dist/iconset.iconset dist/icon1024.png

# Sign with the Apple Development identity when there is one, so macOS keeps the
# Screen Recording permission across rebuilds. Falls back to an ad-hoc signature.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc}"

# DMG with an Applications shortcut
mkdir -p dist/dmgroot
cp -R "$APP" dist/dmgroot/
ln -s /Applications dist/dmgroot/Applications
hdiutil create -volname Overwork -srcfolder dist/dmgroot -ov -format UDZO dist/Overwork.dmg >/dev/null
rm -rf dist/dmgroot
echo "Built $APP and dist/Overwork.dmg"
