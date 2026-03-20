#!/bin/bash
# Build, sign, and launch Teleprompter.
# Run from anywhere — does not change your working directory.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/xcode"
APP_BUNDLE="$BUILD_DIR/Build/Products/Debug/Teleprompter.app"

# Use a stable signing identity so macOS remembers permissions across rebuilds.
# Priority: Apple Development cert > self-signed "Teleprompter Dev" cert > create one.
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | grep -v "REVOKED" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)

if [ -z "$SIGN_IDENTITY" ]; then
    # Try our self-signed cert
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Teleprompter Dev" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
fi

if [ -z "$SIGN_IDENTITY" ]; then
    echo "No signing certificate found. Creating self-signed 'Teleprompter Dev' certificate..."
    echo "You may be prompted for your login password."

    # Create a self-signed code signing certificate with proper EKUs
    cat > /tmp/tp-cs.cnf <<'CSEOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_cs

[dn]
CN = Teleprompter Dev

[v3_cs]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CSEOF

    openssl req -x509 -newkey rsa:2048 -keyout /tmp/tp-key.pem -out /tmp/tp-cert.pem \
        -days 3650 -nodes -config /tmp/tp-cs.cnf 2>/dev/null

    # Convert to p12 with -legacy flag (required for OpenSSL 3.x + macOS Keychain)
    openssl pkcs12 -export -out /tmp/tp.p12 -inkey /tmp/tp-key.pem -in /tmp/tp-cert.pem \
        -passout pass:tp -legacy 2>/dev/null

    # Import into login keychain
    KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
    [ ! -f "$KEYCHAIN" ] && KEYCHAIN="$HOME/Library/Keychains/login.keychain"
    security import /tmp/tp.p12 -k "$KEYCHAIN" -T /usr/bin/codesign -P "tp" 2>/dev/null || true

    # Trust the certificate for code signing
    security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" /tmp/tp-cert.pem 2>/dev/null || true

    # Clean up temp files
    rm -f /tmp/tp-cs.cnf /tmp/tp-key.pem /tmp/tp-cert.pem /tmp/tp.p12

    # Verify
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Teleprompter Dev" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)

    if [ -n "$SIGN_IDENTITY" ]; then
        echo "✓ Created 'Teleprompter Dev' certificate — permissions will persist across rebuilds"
    else
        echo "⚠ Certificate creation failed. Falling back to ad-hoc signing."
        echo "  Permissions will need re-granting after each build."
        SIGN_IDENTITY="-"
    fi
else
    echo "Using signing identity: $SIGN_IDENTITY"
fi

# Ensure Xcode is the active developer directory
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

echo "Building..."
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

# Kill any running instance (try graceful quit first, then force)
pkill -x Teleprompter 2>/dev/null && sleep 0.3 || true
pkill -9 -x Teleprompter 2>/dev/null && sleep 0.2 || true

# Remove quarantine xattr BEFORE signing (prevents Gatekeeper from flagging)
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# Codesign
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE" 2>/dev/null

# Verify and launch
if codesign --verify "$APP_BUNDLE" 2>/dev/null; then
    echo "✓ Signed and launching Teleprompter.app"
    if ! open "$APP_BUNDLE" 2>/dev/null; then
        echo "⚠ open failed (Gatekeeper?), launching binary directly..."
        nohup "$APP_BUNDLE/Contents/MacOS/Teleprompter" >/dev/null 2>&1 &
        disown
        echo "✓ Launched via binary"
    fi
else
    echo "✗ Signing failed"
    exit 1
fi
