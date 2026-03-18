#!/bin/zsh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FloatRec"
DIST_DIR="$REPO_ROOT/dist"
STAGE_DIR="$REPO_ROOT/.build/dmg-stage"
APP_DIR="$STAGE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BIN_PATH="$(swift build -c release --package-path "$REPO_ROOT" --show-bin-path)"
EXECUTABLE_PATH="$BIN_PATH/$APP_NAME"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
SIGNING_IDENTITY="${FLOATREC_SIGNING_IDENTITY:-FloatRec Local Signer}"
SIGNING_KEYCHAIN_PATH="${FLOATREC_SIGNING_KEYCHAIN_PATH:-$HOME/.floatrec-local-signing/FloatRecLocal.keychain-db}"

rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DIST_DIR"

swift build -c release --package-path "$REPO_ROOT"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
SPARKLE_SRC="$REPO_ROOT/Frameworks/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
cp -R "$SPARKLE_SRC" "$FRAMEWORKS_DIR/"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>FloatRec</string>
  <key>CFBundleExecutable</key>
  <string>FloatRec</string>
  <key>CFBundleIdentifier</key>
  <string>dev.floatrec.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>FloatRec</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>FloatRec uses the microphone when you choose to capture voice narration.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>FloatRec records the selected screen, window, or area to create shareable clips.</string>
  <key>SUFeedURL</key>
  <string>https://kanguk01.github.io/FloatRec/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>FVXsi1mAJvPgsjUCmA9vJxk6A0Pio3uBEKGccH8HyXw=</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
</dict>
</plist>
PLIST

FLOATREC_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
FLOATREC_SIGNING_KEYCHAIN_PATH="$SIGNING_KEYCHAIN_PATH" \
  "$REPO_ROOT/scripts/ensure_local_signing_identity.sh" >/dev/null

codesign --force --deep --keychain "$SIGNING_KEYCHAIN_PATH" --sign "$SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created DMG: $DMG_PATH"
