#!/bin/bash
# Build, sign, and launch Teleprompter.
# Run from anywhere — does not change your working directory.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/xcode"
APP_BUNDLE="$BUILD_DIR/Build/Products/Debug/Teleprompter.app"

# Use the Apple Development certificate if available (stable identity = permissions persist).
# Falls back to ad-hoc signing if no dev cert found.
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Using signing identity: $SIGN_IDENTITY"
else
    SIGN_IDENTITY="-"
    echo "⚠ No Apple Development cert found, using ad-hoc signing (permissions will reset on rebuild)"
fi

echo "Building..."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild \
    -project "$SCRIPT_DIR/Teleprompter.xcodeproj" \
    -scheme Teleprompter \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$BUILD_DIR" \
    build 2>&1 | tail -3

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Build failed — app bundle not found."
    exit 1
fi

# Kill any running instance
pkill -x Teleprompter 2>/dev/null && sleep 0.5 || true

# Codesign
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE" 2>/dev/null

# Verify and launch
if codesign --verify "$APP_BUNDLE" 2>/dev/null; then
    echo "✓ Signed and launching Teleprompter.app"
    open "$APP_BUNDLE"
else
    echo "✗ Signing failed"
    exit 1
fi
