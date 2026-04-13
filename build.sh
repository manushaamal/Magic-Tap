#!/bin/bash
# build.sh - Build MagicTap as a .app bundle

APP_NAME="MagicTap"
BUILD_DIR="./build"
APP_DIR="$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
RESOURCES_DIR="$BUILD_DIR/$APP_NAME.app/Contents/Resources"
INFO_PLIST="$BUILD_DIR/$APP_NAME.app/Contents/Info.plist"

mkdir -p "$APP_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Compiling Swift..."
swiftc main.swift AppDelegate.swift TouchHandler.swift \
    -framework Cocoa \
    -framework UserNotifications \
    -framework ApplicationServices \
    -o "$APP_DIR/$APP_NAME" \
    -target arm64-apple-macos12.0

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed"
    exit 1
fi

echo "Writing Info.plist..."
cat > "$INFO_PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MagicTap</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.magictap</string>
    <key>CFBundleName</key>
    <string>MagicTap</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSUIElement</key>
    <string>1</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "Signing..."
codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME.app"

if [ $? -ne 0 ]; then
    echo "❌ Code signing failed"
    exit 1
fi

echo "✅ Built: $BUILD_DIR/$APP_NAME.app"
echo ""
echo "To run:"
echo "  open $BUILD_DIR/$APP_NAME.app"
echo ""
echo "To add to Login Items:"
echo "  System Settings → General → Login Items → add MagicTap.app"
