#!/bin/zsh
# Build SideLux.app into ./build
#   ./build.sh           build the app
#   ./build.sh release   build, then package build/SideLux-<version>.zip and .dmg for GitHub Releases
#   ./build.sh dmg       package the existing build/SideLux.app as a .dmg (no rebuild)
#   ./build.sh icon      regenerate Resources/AppIcon.icns from Scripts/make-icon.swift
#
# The app is ad-hoc signed, so macOS asks for Accessibility permission again after each build.
set -e
cd "${0:a:h}"

VERSION=1.0.0
BUILD_NUMBER=1
BUNDLE_ID=io.github.hellocket.sidelux
OUT=build
APP=$OUT/SideLux.app

# Disk image showing the app next to an Applications shortcut, for drag-and-drop install
make_dmg() {
  local DMG=$OUT/SideLux-$VERSION.dmg STAGE=$(mktemp -d)/SideLux
  mkdir -p $STAGE
  ditto $APP $STAGE/SideLux.app
  ln -s /Applications $STAGE/Applications
  rm -f $DMG
  hdiutil create -volname "SideLux $VERSION" -srcfolder $STAGE -fs HFS+ -format UDZO -ov $DMG >/dev/null 2>&1
  rm -rf ${STAGE:h}
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
codesign --force --sign - $APP
echo "Built $APP ($(du -sh $APP | cut -f1))"

if [[ "$1" == "release" ]]; then
  ZIP=$OUT/SideLux-$VERSION.zip
  rm -f $ZIP
  ditto -c -k --keepParent $APP $ZIP
  echo "Packaged $ZIP ($(du -sh $ZIP | cut -f1)) — attach it to a GitHub release tagged v$VERSION"
  echo "SHA-256: $(shasum -a 256 $ZIP | cut -d' ' -f1)  ← put this in Casks/sidelux.rb"
  make_dmg
fi
