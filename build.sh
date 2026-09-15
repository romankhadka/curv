#!/bin/sh
# Builds Curv.app into ./build with the daemon bundled inside.
set -e
cd "$(dirname "$0")"
VERSION="${CURV_VERSION:-0.0.0-dev}"
swift build -c release
APP=build/Curv.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Curv "$APP/Contents/MacOS/Curv"
cp .build/release/fancurved "$APP/Contents/Resources/fancurved"
cp Resources/Curv.icns "$APP/Contents/Resources/Curv.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Curv</string>
  <key>CFBundleIdentifier</key><string>com.romn.curv</string>
  <key>CFBundleName</key><string>Curv</string>
  <key>CFBundleDisplayName</key><string>Curv</string>
  <key>CFBundleIconFile</key><string>Curv</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Roman Khadka. MIT License.</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "built $APP"
