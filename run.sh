#!/bin/bash
# Launch the last-built Teleprompter.app without rebuilding.
# Run ./bundle.sh first if you haven't built yet.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/.build/xcode/Build/Products/Debug/Teleprompter.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "No build found — running bundle.sh first..."
    exec "$SCRIPT_DIR/bundle.sh"
fi

pkill -x Teleprompter 2>/dev/null && sleep 0.5 || true
echo "Launching Teleprompter.app"
open "$APP_BUNDLE"
