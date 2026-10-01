#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "==> Preparing RecLite DMG Package Builder..."

APP_NAME="RecLite.app"
APP_PATH="$DIR/$APP_NAME"
DMG_NAME="RecLite-Installer.dmg"
FINAL_DMG="$DIR/$DMG_NAME"
BUILD_DIR="$DIR/.build"
STAGE_DIR="$BUILD_DIR/dmg_stage"
TEMP_DMG="$BUILD_DIR/temp.dmg"

# 1. Ensure App Bundle is built
if [ ! -d "$APP_PATH" ]; then
    echo "==> App bundle not found at $APP_PATH. Running build_app.sh first..."
    ./build_app.sh
fi

# 2. Cleanup old staging & previous dmg
echo "==> Cleaning up previous build artifacts..."
rm -rf "$STAGE_DIR" "$TEMP_DMG" "$FINAL_DMG"
mkdir -p "$STAGE_DIR"

# 3. Copy App to Staging directory
echo "==> Copying $APP_NAME to DMG staging..."
cp -R "$APP_PATH" "$STAGE_DIR/$APP_NAME"

# 4. Create /Applications symlink for Drag-and-Drop installation
echo "==> Creating /Applications symlink..."
ln -s /Applications "$STAGE_DIR/Applications"

# 5. Create temporary writable DMG
echo "==> Creating temporary disk image..."
hdiutil create -srcfolder "$STAGE_DIR" -volname "RecLite Installer" -fs HFS+ -format UDRW "$TEMP_DMG" -quiet

# 6. Mount temporary DMG
echo "==> Mounting DMG for layout styling..."
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG")
MOUNT_DIR=$(echo "$MOUNT_OUTPUT" | grep -E '/Volumes/' | sed -n 's/.*\/Volumes\//\/Volumes\//p')

if [ -z "$MOUNT_DIR" ]; then
    echo "Error: Failed to mount temporary DMG."
    exit 1
fi

echo "==> Mounted at $MOUNT_DIR"

# 7. Apply Finder visual layout using AppleScript
echo "==> Applying Finder window & icon positions layout..."
sleep 2

osascript <<EOF || true
tell application "Finder"
    tell disk "RecLite Installer"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {300, 180, 940, 560}
        
        set iconView to icon view options of container window
        set icon size of iconView to 120
        set text size of iconView to 13
        set arrangement of iconView to not arranged
        
        try
            set position of item "$APP_NAME" of container window to {160, 170}
            set position of item "Applications" of container window to {480, 170}
        end try
        
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# 8. Unmount temporary DMG
echo "==> Detaching temporary DMG..."
hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force

# 9. Compress to final compressed DMG
echo "==> Compressing final DMG image ($DMG_NAME)..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" -quiet

# 10. Clean up temporary files
rm -rf "$STAGE_DIR" "$TEMP_DMG"

echo "=========================================================="
echo " SUCCESS! RecLite DMG Installer generated successfully:"
echo " Path: $FINAL_DMG"
echo " Size: $(du -h "$FINAL_DMG" | cut -f1)"
echo " Users can double click $DMG_NAME and drag $APP_NAME to /Applications"
echo "=========================================================="
