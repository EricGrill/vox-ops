#!/usr/bin/env bash
set -euo pipefail

# Build a release .app bundle and create a zip for distribution.
# Usage: ./Scripts/build-release.sh [version]
# Example: ./Scripts/build-release.sh 0.1.0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw "$PROJECT_DIR/VoxOpsApp/Info.plist")}"

echo "==> Building VoxOps v${VERSION}"

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Regenerate Xcode project
cd "$PROJECT_DIR"
xcodegen generate

# Build release
xcodebuild \
  -project VoxOps.xcodeproj \
  -scheme VoxOpsApp \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$BUILD_DIR/Release/VoxOpsApp.app"

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Build failed — $APP_PATH not found"
  exit 1
fi

# Update version in built app (in case it wasn't set in Info.plist)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_PATH/Contents/Info.plist"

# Create zip
ZIP_NAME="VoxOps-${VERSION}-macos-arm64.zip"
cd "$BUILD_DIR/Release"
ditto -c -k --sequesterRsrc --keepParent VoxOpsApp.app "$BUILD_DIR/$ZIP_NAME"

echo "==> Built: $BUILD_DIR/$ZIP_NAME"
echo "==> SHA256: $(shasum -a 256 "$BUILD_DIR/$ZIP_NAME" | cut -d' ' -f1)"
