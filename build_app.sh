#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="RustDeskScreenOff"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "Compiling $APP_NAME (Universal Binary)..."
swiftc "$SCRIPT_DIR/$APP_NAME.swift" \
    -o "$SCRIPT_DIR/${APP_NAME}_arm64" \
    -target arm64-apple-macosx14.0 \
    -framework AppKit \
    -framework CoreGraphics
swiftc "$SCRIPT_DIR/$APP_NAME.swift" \
    -o "$SCRIPT_DIR/${APP_NAME}_x86_64" \
    -target x86_64-apple-macosx14.0 \
    -framework AppKit \
    -framework CoreGraphics
lipo -create \
    "$SCRIPT_DIR/${APP_NAME}_arm64" \
    "$SCRIPT_DIR/${APP_NAME}_x86_64" \
    -output "$SCRIPT_DIR/$APP_NAME"
rm "$SCRIPT_DIR/${APP_NAME}_arm64" "$SCRIPT_DIR/${APP_NAME}_x86_64"

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

mv "$SCRIPT_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.rustdesk.screen-off</string>
    <key>CFBundleName</key>
    <string>RustDeskScreenOff</string>
    <key>CFBundleExecutable</key>
    <string>RustDeskScreenOff</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "Done: $APP_BUNDLE"
echo "Run: open $APP_BUNDLE"
