#!/usr/bin/env bash
# Assemble a distributable Lumora.app from the SwiftPM executable.
# Usage: ./scripts/make_app.sh
set -euo pipefail
cd "$(dirname "$0")/.."          # repo root

APP="Lumora"
BUNDLE_ID="com.lumora.Lumora"
VERSION="1.0"
DIST="dist"
APPDIR="$DIST/$APP.app"
SRCICON="Sources/Lumora/Resources/AppIcon.png"

echo "→ Building release binary…"
swift build -c release

BIN=".build/release/$APP"
RESBUNDLE=".build/release/${APP}_${APP}.bundle"

echo "→ Assembling ${APPDIR} …"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"
cp "$BIN" "$APPDIR/Contents/MacOS/$APP"
# Bundled SwiftPM resources (AppIcon/Splash) live in the generated .bundle.
[ -d "$RESBUNDLE" ] && cp -R "$RESBUNDLE" "$APPDIR/Contents/Resources/"

echo "→ Building AppIcon.icns…"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
gen() { sips -z "$2" "$2" "$SRCICON" --out "$ICONSET/$1" >/dev/null; }
gen icon_16x16.png 16;     gen icon_16x16@2x.png 32
gen icon_32x32.png 32;     gen icon_32x32@2x.png 64
gen icon_128x128.png 128;  gen icon_128x128@2x.png 256
gen icon_256x256.png 256;  gen icon_256x256@2x.png 512
gen icon_512x512.png 512;  gen icon_512x512@2x.png 1024
iconutil -c icns "$ICONSET" -o "$APPDIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "→ Writing Info.plist…"
cat > "$APPDIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleDisplayName</key><string>$APP</string>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "→ Ad-hoc code signing…"
codesign --force --deep --sign - "$APPDIR"

echo "✓ Built $APPDIR"
