#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Creed — macOS .app bundle packaging script
#
# Usage:
#   ./Scripts/package-app.sh              # Build + package
#   ./Scripts/package-app.sh --dmg        # Build + package + DMG
#   ./Scripts/package-app.sh --sign ID    # Build + package + code sign
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="Creed"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
VERSION=$(grep -A1 'CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist" | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>/\1/')

# Parse arguments
CREATE_DMG=false
SIGN_IDENTITY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg) CREATE_DMG=true; shift ;;
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "╔══════════════════════════════════════╗"
echo "║     Creed App Packager v${VERSION}       ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ─── Step 1: Build release binaries ───
echo "→ Building release binaries..."
cd "$PROJECT_DIR"
swift build -c release --product Creed --product CreedMCPServer 2>&1 | tail -3
echo "  Build complete."
echo ""

# ─── Step 2: Create .app bundle structure ───
echo "→ Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# ─── Step 3: Copy executables ───
echo "→ Copying executables..."
cp "$BUILD_DIR/Creed" "$APP_BUNDLE/Contents/MacOS/Creed"
cp "$BUILD_DIR/CreedMCPServer" "$APP_BUNDLE/Contents/MacOS/CreedMCPServer"

# ─── Step 4: Copy Info.plist ───
echo "→ Installing Info.plist..."
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# ─── Step 5: Create PkgInfo ───
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# ─── Step 6: Copy icon if available ───
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    echo "→ Installing app icon..."
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "→ No AppIcon.icns found — using default macOS icon."
    echo "  Place an AppIcon.icns in Resources/ to add a custom icon."
fi

# ─── Step 7: Strip debug symbols (smaller binary) ───
echo "→ Stripping debug symbols..."
strip -x "$APP_BUNDLE/Contents/MacOS/Creed" 2>/dev/null || true
strip -x "$APP_BUNDLE/Contents/MacOS/CreedMCPServer" 2>/dev/null || true

# ─── Step 8: Code sign (optional) ───
if [ -n "$SIGN_IDENTITY" ]; then
    echo "→ Code signing with identity: $SIGN_IDENTITY"
    codesign --force --deep --options runtime \
        --entitlements "$PROJECT_DIR/Resources/Creed.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
    echo "  Code signing complete."

    echo "→ Verifying signature..."
    codesign --verify --deep --strict "$APP_BUNDLE"
    echo "  Signature verified."
else
    # Ad-hoc sign for local use
    echo "→ Ad-hoc signing for local use..."
    codesign --force --deep -s - "$APP_BUNDLE" 2>/dev/null || true
fi
echo ""

# ─── Step 9: Create DMG (optional) ───
if [ "$CREATE_DMG" = true ]; then
    DMG_NAME="Creed-${VERSION}.dmg"
    DMG_PATH="$DIST_DIR/$DMG_NAME"
    DMG_TEMP="$DIST_DIR/dmg-staging"

    echo "→ Creating DMG..."
    rm -rf "$DMG_TEMP" "$DMG_PATH"
    mkdir -p "$DMG_TEMP"

    # Copy app to staging
    cp -R "$APP_BUNDLE" "$DMG_TEMP/"

    # Create symlink to Applications
    ln -s /Applications "$DMG_TEMP/Applications"

    # Create DMG
    hdiutil create -volname "Creed" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_PATH" 2>/dev/null

    rm -rf "$DMG_TEMP"

    DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
    echo "  DMG created: $DMG_PATH ($DMG_SIZE)"
    echo ""
fi

# ─── Summary ───
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
MAIN_SIZE=$(ls -lh "$APP_BUNDLE/Contents/MacOS/Creed" | awk '{print $5}')
MCP_SIZE=$(ls -lh "$APP_BUNDLE/Contents/MacOS/CreedMCPServer" | awk '{print $5}')

echo "╔══════════════════════════════════════╗"
echo "║           Package Complete           ║"
echo "╠══════════════════════════════════════╣"
echo "║  App:  $APP_BUNDLE"
echo "║  Size: $APP_SIZE total"
echo "║    Creed:          $MAIN_SIZE"
echo "║    CreedMCPServer:  $MCP_SIZE"
echo "║  Version: $VERSION"
if [ -n "$SIGN_IDENTITY" ]; then
echo "║  Signed: $SIGN_IDENTITY"
else
echo "║  Signed: ad-hoc (local only)"
fi
echo "╚══════════════════════════════════════╝"
echo ""
echo "To install:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo ""
echo "To run:"
echo "  open \"$APP_BUNDLE\""
