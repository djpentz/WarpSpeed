#!/usr/bin/env bash
# Build WarpSpeed into a self-contained .app bundle without Xcode.
# Requires: Swift 5.9+ (from Command Line Tools or Xcode).

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="WarpSpeed"
CONFIGURATION="${CONFIGURATION:-release}"
APP_BUNDLE="build/${APP_NAME}.app"

echo "[1/4] Building ${APP_NAME} (${CONFIGURATION})..."
swift package resolve

# Strip #Preview blocks from KeyboardShortcuts.
# The #Preview macro requires the PreviewsMacros compiler plugin, which ships
# only with full Xcode — not with the Command Line Tools toolchain. The blocks
# are demo code we never invoke, so we delete them and build cleanly with CLT.
# This is re-applied on every build because `swift package resolve` may restore
# the checkout. Safe to remove once you have Xcode installed.
PREVIEW_FILE=".build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift"
if [[ -f "$PREVIEW_FILE" ]] && grep -q '^#Preview {' "$PREVIEW_FILE"; then
    # Remove only the `#Preview { ... }` blocks, leaving surrounding `#if`/`#endif`
    # intact. The blocks have no nested braces, so [^}]* matches safely.
    perl -0777 -i -pe 's/\n*#Preview \{[^}]*\}\n//g' "$PREVIEW_FILE"
fi

swift build -c "$CONFIGURATION"

BIN_PATH=$(swift build -c "$CONFIGURATION" --show-bin-path)
EXECUTABLE="$BIN_PATH/$APP_NAME"

if [[ ! -f "$EXECUTABLE" ]]; then
    echo "error: build did not produce an executable at $EXECUTABLE" >&2
    exit 1
fi

echo "[2/4] Assembling .app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Prefer a stable self-signed identity so macOS keeps TCC grants (Accessibility)
# across rebuilds. Ad-hoc signatures get a fresh hash every build, which makes
# macOS treat each build as a new app and drop the Accessibility permission.
# Falls back to ad-hoc on machines without the cert (CI, personal laptop).
# Create the identity locally with: scripts/setup-signing.sh
SIGN_IDENTITY="WarpSpeed Self-Signed"
SIGN_KEYCHAIN="$HOME/Library/Keychains/warpspeed-signing.keychain-db"

# Unlock the signing keychain if its password is supplied (optional).
if [[ -n "${WARPSPEED_KEYCHAIN_PW:-}" && -f "$SIGN_KEYCHAIN" ]]; then
    security unlock-keychain -p "$WARPSPEED_KEYCHAIN_PW" "$SIGN_KEYCHAIN" 2>/dev/null || true
fi

if [[ -f "$SIGN_KEYCHAIN" ]] && security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "[3/4] Code signing with stable identity '$SIGN_IDENTITY'..."
    codesign --force --deep --sign "$SIGN_IDENTITY" --keychain "$SIGN_KEYCHAIN" \
        --options runtime \
        --entitlements "Resources/WarpSpeed.entitlements" \
        "$APP_BUNDLE"
else
    echo "[3/4] Ad-hoc code signing (stable identity not found; Accessibility grant will reset each build)..."
    codesign --force --deep --sign - \
        --options runtime \
        --entitlements "Resources/WarpSpeed.entitlements" \
        "$APP_BUNDLE"
fi

echo "[4/4] Done."
echo
echo "    open \"$APP_BUNDLE\""
echo
echo "To install for everyday use:"
echo "    cp -R \"$APP_BUNDLE\" /Applications/"
