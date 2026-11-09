#!/bin/zsh
# Build Keyspace and install it into /Applications, then launch it.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/Keyspace.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Keyspace "$APP/Contents/MacOS/Keyspace"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon (regenerated when make_icon.swift is newer than the .icns)
if [ ! -f Resources/AppIcon.icns ] || [ Resources/make_icon.swift -nt Resources/AppIcon.icns ]; then
  ICONSET=build/AppIcon.iconset; rm -rf $ICONSET; mkdir -p $ICONSET
  swift Resources/make_icon.swift build/icon_1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon_1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $ICONSET -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"

pkill -x Keyspace 2>/dev/null || true   # quitting restores all hidden apps
for _ in $(seq 1 50); do pgrep -x Keyspace >/dev/null || break; sleep 0.1; done   # wait for clean exit
rm -rf "/Applications/Keyspace.app"
cp -R "$APP" "/Applications/"
open "/Applications/Keyspace.app"
echo "Installed + launched: /Applications/Keyspace.app"
