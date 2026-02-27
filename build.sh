#!/bin/bash
# build.sh — Build SimpleProxyMenuBar and install to /Applications
set -e

APP_NAME="SimpleProxyMenuBar"
SCHEME="SimpleProxyMenuBar"
PROJECT="SimpleProxyMenuBar.xcodeproj"
INSTALL_PATH="/Applications/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."

# Build with xcodebuild
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath build \
    build

# Find the built .app
APP_PATH=$(find build -name "$APP_NAME.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Build failed — .app not found"
    exit 1
fi

echo "📲 Installing to /Applications..."
sudo ditto "$APP_PATH" "$INSTALL_PATH"

echo ""
echo "✅ Installed: $INSTALL_PATH"
echo ""
echo "▶️  Launching..."
open "$INSTALL_PATH"
