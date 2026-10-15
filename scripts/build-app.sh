#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ge 1 ]]; then
  OUTPUT_PATH="$1"
else
  OUTPUT_PATH="$PROJECT_DIR/../Cloner.app"
fi
SCRATCH_PATH="$PROJECT_DIR/../../work/cloner-swift-build"

swift build --package-path "$PROJECT_DIR" --scratch-path "$SCRATCH_PATH" --configuration release
BUILD_BIN_PATH="$(swift build --package-path "$PROJECT_DIR" --scratch-path "$SCRATCH_PATH" --configuration release --show-bin-path)"
APP_EXECUTABLE="$BUILD_BIN_PATH/Cloner"

if [[ -e "$OUTPUT_PATH" ]]; then
  echo "Refusing to replace existing path: $OUTPUT_PATH" >&2
  exit 2
fi

mkdir -p "$OUTPUT_PATH/Contents/MacOS"
cp "$APP_EXECUTABLE" "$OUTPUT_PATH/Contents/MacOS/Cloner"

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
