#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "==> Building ScreenRecorder Release Binary..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release

APP_NAME="ScreenRecorder.app"
APP_DIR="$DIR/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Creating macOS App Bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy binary
cp "$DIR/.build/release/ScreenRecorder" "$MACOS/ScreenRecorder"
chmod +x "$MACOS/ScreenRecorder"

# Copy resources (AppIcon)
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

# Create Info.plist
cat << 'EOF' > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ScreenRecorder</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.ScreenRecorder</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ScreenRecorder</string>
    <key>CFBundleDisplayName</key>
    <string>RecLite</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 RecLite. All rights reserved.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>ScreenRecorder needs screen recording access to capture displays, windows, and custom crop areas.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>ScreenRecorder needs microphone access to record audio narration alongside screen recordings.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Signing App Bundle..."
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep -E "Apple Development|ScreenRecorder-Dev" | head -n 1 | awk -F '"' '{print $2}')

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "==> Using certificate: $SIGNING_IDENTITY (Permanent TCC permissions across builds)"
    codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier "com.antigravity.ScreenRecorder" "$APP_DIR"
else
    echo "==> Using ad-hoc signature (-)..."
    codesign --force --deep --sign - --identifier "com.antigravity.ScreenRecorder" "$APP_DIR"
fi

echo "==> macOS App Bundle created successfully at: $APP_DIR"
echo "You can launch it by running: open $APP_DIR"
echo "To package into a drag-and-drop installer DMG, run: ./create_dmg.sh"
