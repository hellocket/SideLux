#!/bin/zsh
# Build SideLux.app into ./build
#   ./build.sh           build the app
#   ./build.sh release   build, then package build/SideLux-<version>.zip and .dmg for GitHub Releases
#   ./build.sh dmg       package the existing build/SideLux.app as a .dmg (no rebuild)
#   ./build.sh icon      regenerate Resources/AppIcon.icns from Scripts/make-icon.swift
#
# Signing: uses the "SideLux Code Signing" certificate from the login keychain when present, so every
# build keeps the same identity and macOS keeps the Accessibility permission across updates.
# Without it the app is ad-hoc signed, and each build needs the permission granted again.
set -e
cd "${0:a:h}"

VERSION=1.0.2
BUILD_NUMBER=3
BUNDLE_ID=io.github.hellocket.sidelux
SIGN_NAME="SideLux Code Signing"
OUT=build
APP=$OUT/SideLux.app

# Disk image: the app next to an Applications shortcut, on a background that also explains
# how to get past the "can't verify" warning on first launch (Scripts/make-dmg-background.swift)
make_dmg() {
  local DMG=$OUT/SideLux-$VERSION.dmg VOL="SideLux $VERSION"
  local WORK=$(mktemp -d) STAGE RW MNT
  STAGE=$WORK/stage; RW=$WORK/rw.dmg
  mkdir -p $STAGE/.background
  ditto $APP $STAGE/SideLux.app
  ln -s /Applications $STAGE/Applications
  swift Scripts/make-dmg-background.swift $WORK >/dev/null
  tiffutil -cathidpicheck $WORK/background.png $WORK/background@2x.png -out $STAGE/.background/background.tiff >/dev/null 2>&1
  chflags hidden $STAGE/.background   # stays hidden even with "show hidden files" on

  # A previous image with the same name may still be mounted
  [[ -d "/Volumes/$VOL" ]] && hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1

  hdiutil create -volname "$VOL" -srcfolder $STAGE -fs HFS+ -format UDRW -ov $RW >/dev/null 2>&1
  MNT=$(hdiutil attach -readwrite -noverify -noautoopen $RW 2>/dev/null | grep -o '/Volumes/.*$')
  # Window layout (needs permission for the terminal to control Finder; falls back to a plain window)
  osascript >/dev/null 2>&1 <<OSA || echo "Note: couldn't style the DMG window (Finder automation not allowed)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set pathbar visible of container window to false
    end try
    set bounds of container window to {200, 120, 800, 588}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 100
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    -- Finder draws icons ~30pt below the given y, so 120 lands on the background's arrow at 150
    set position of item "SideLux.app" of container window to {160, 120}
    set position of item "Applications" of container window to {440, 120}
    try
      set position of item ".background" of container window to {900, 900}
    end try
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
  rm -rf "$MNT/.fseventsd"
  sync
  hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach "$MNT" -force >/dev/null 2>&1
  rm -f $DMG
  hdiutil convert $RW -format UDZO -imagekey zlib-level=9 -o $DMG >/dev/null 2>&1
  rm -rf $WORK
  echo "Packaged $DMG ($(du -sh $DMG | cut -f1))"
}

if [[ "$1" == "dmg" ]]; then
  [[ -d $APP ]] || { echo "Run ./build.sh first"; exit 1; }
  make_dmg
  exit 0
fi

if [[ "$1" == "icon" ]]; then
  swift Scripts/make-icon.swift docs/icon.png >/dev/null
  rm -rf $OUT/AppIcon.iconset && mkdir -p $OUT/AppIcon.iconset
  for s in 16 32 128 256 512; do
    sips -z $s $s docs/icon.png --out $OUT/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) docs/icon.png --out $OUT/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $OUT/AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf $OUT/AppIcon.iconset
  echo "Updated Resources/AppIcon.icns"
  exit 0
fi

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Sources/main.swift -o $APP/Contents/MacOS/SideLux
cp Resources/AppIcon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>SideLux</string>
  <key>CFBundleDisplayName</key><string>SideLux</string>
  <key>CFBundleExecutable</key><string>SideLux</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
EOF
SIGN_ID=$(security find-identity -p codesigning 2>/dev/null | grep "\"$SIGN_NAME\"" | head -1 | awk '{print $2}')
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --sign "$SIGN_ID" $APP
else
  echo "Warning: \"$SIGN_NAME\" certificate not found; signing ad-hoc (Accessibility permission won't survive updates)"
  codesign --force --sign - $APP
fi
echo "Built $APP ($(du -sh $APP | cut -f1))"

if [[ "$1" == "release" ]]; then
  ZIP=$OUT/SideLux-$VERSION.zip
  rm -f $ZIP
  ditto -c -k --keepParent $APP $ZIP
  echo "Packaged $ZIP ($(du -sh $ZIP | cut -f1)) — attach it to a GitHub release tagged v$VERSION"
  echo "SHA-256: $(shasum -a 256 $ZIP | cut -d' ' -f1)  ← put this in Casks/sidelux.rb"
  make_dmg
fi
