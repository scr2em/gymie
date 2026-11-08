#!/usr/bin/env bash
# Builds build/Gymie.app from the Swift package.
#   CONFIG=debug|release (default release)
#   SIGN_IDENTITY="Apple Development: ..." keeps camera/calendar permissions across rebuilds;
#   the default "-" (ad-hoc) works but macOS may ask for permissions again after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Gymie.app"

swift build -c "$CONFIG" --product Gymie
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Gymie"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Gymie"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The local pose engine (Python sources + model) and its one-time setup script.
rsync -a --exclude '__pycache__' --exclude 'tests' --exclude 'pytest.ini' --exclude '.venv' PoseServer "$APP/Contents/Resources/"
cp scripts/setup-pose-server.sh "$APP/Contents/Resources/setup-pose-server.sh"

codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed with: $SIGN_IDENTITY)"
