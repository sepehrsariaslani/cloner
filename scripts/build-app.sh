#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ge 1 ]]; then
  OUTPUT_PATH="$1"
else
  OUTPUT_PATH="$PROJECT_DIR/../Cloner.app"
fi
SCRATCH_PATH="$PROJECT_DIR/../../work/cloner-swift-build"
ICONSET_PATH="$SCRATCH_PATH/AppIcon.iconset"
ICON_PATH="$SCRATCH_PATH/AppIcon.icns"
ICON_SOURCE="$PROJECT_DIR/Resources/AppIcon.png"
if [[ ! -f "$ICON_SOURCE" ]]; then
  ICON_SOURCE="$PROJECT_DIR/Resources/AppIcon.jpg"
fi

swift build --package-path "$PROJECT_DIR" --scratch-path "$SCRATCH_PATH" --configuration release
BUILD_BIN_PATH="$(swift build --package-path "$PROJECT_DIR" --scratch-path "$SCRATCH_PATH" --configuration release --show-bin-path)"
APP_EXECUTABLE="$BUILD_BIN_PATH/Cloner"

ICON_INPUT="$ICON_SOURCE"
if [[ "$ICON_SOURCE" == *.jpg ]]; then
  ICON_INPUT="$SCRATCH_PATH/AppIcon-source.png"
  sips -s format png "$ICON_SOURCE" --out "$ICON_INPUT" >/dev/null
fi

mkdir -p "$ICONSET_PATH"
while read -r pixels name; do
  sips -z "$pixels" "$pixels" "$ICON_INPUT" --out "$ICONSET_PATH/$name" >/dev/null
done <<'ICONS'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
ICONS
iconutil -c icns "$ICONSET_PATH" -o "$ICON_PATH"

if [[ -e "$OUTPUT_PATH" ]]; then
  echo "Refusing to replace existing path: $OUTPUT_PATH" >&2
  exit 2
fi

mkdir -p "$OUTPUT_PATH/Contents/MacOS" "$OUTPUT_PATH/Contents/Resources"
cp "$APP_EXECUTABLE" "$OUTPUT_PATH/Contents/MacOS/Cloner"
cp "$ICON_PATH" "$OUTPUT_PATH/Contents/Resources/AppIcon.icns"

cat > "$OUTPUT_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>fa</string>
  <key>CFBundleExecutable</key><string>Cloner</string>
  <key>CFBundleIdentifier</key><string>com.cloner.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Cloner</string>
  <key>CFBundleDisplayName</key><string>Cloner</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - --identifier com.cloner.app "$OUTPUT_PATH"
echo "Built: $OUTPUT_PATH"
