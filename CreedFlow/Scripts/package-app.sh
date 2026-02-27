#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# CreedFlow — macOS .app bundle packaging script
#
# Usage:
#   ./Scripts/package-app.sh                       # Build + package (native arch)
#   ./Scripts/package-app.sh --dmg                 # Build + package + DMG
#   ./Scripts/package-app.sh --arch arm64          # Build for Apple Silicon
#   ./Scripts/package-app.sh --arch x86_64         # Build for Intel
#   ./Scripts/package-app.sh --arch arm64 --dmg    # Apple Silicon DMG
#   ./Scripts/package-app.sh --sign ID             # Build + code sign
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="CreedFlow"
VERSION=$(grep -A1 'CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist" | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>/\1/')

# Parse arguments
CREATE_DMG=false
SIGN_IDENTITY=""
TARGET_ARCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg) CREATE_DMG=true; shift ;;
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        --arch) TARGET_ARCH="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Determine arch label and build flags
if [ -n "$TARGET_ARCH" ]; then
    ARCH_FLAG="--triple ${TARGET_ARCH}-apple-macosx"
    ARCH_LABEL="$TARGET_ARCH"
else
    ARCH_FLAG=""
    ARCH_LABEL=$(uname -m)
fi

APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_ARCH_SUFFIX="-${ARCH_LABEL}"

echo "╔══════════════════════════════════════════╗"
echo "║   CreedFlow App Packager v${VERSION}         ║"
echo "║   Architecture: ${ARCH_LABEL}                      ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── Step 1: Build release binaries ───
echo "→ Building release binaries (${ARCH_LABEL})..."
cd "$PROJECT_DIR"
# Build each product separately to ensure both are compiled
# shellcheck disable=SC2086
set +e
echo "  Building CreedFlow..."
swift build -c release --product CreedFlow $ARCH_FLAG 2>&1
BUILD_EXIT=$?
if [ $BUILD_EXIT -ne 0 ]; then
    set -e
    echo ""
    echo "ERROR: CreedFlow build failed (exit code $BUILD_EXIT)"
    exit $BUILD_EXIT
fi
echo "  Building CreedFlowMCPServer..."
swift build -c release --product CreedFlowMCPServer $ARCH_FLAG 2>&1
BUILD_EXIT=$?
set -e
if [ $BUILD_EXIT -ne 0 ]; then
    echo ""
    echo "ERROR: CreedFlowMCPServer build failed (exit code $BUILD_EXIT)"
    exit $BUILD_EXIT
fi
echo "  Build complete."
echo ""

# ─── Locate binaries ───
echo "→ Locating binaries..."
# Try known paths first, then fall back to find
if [ -n "$TARGET_ARCH" ]; then
    CANDIDATE_DIRS=(
        "$PROJECT_DIR/.build/${TARGET_ARCH}-apple-macosx/release"
        "$PROJECT_DIR/.build/release"
        "$PROJECT_DIR/.build/apple/Products/Release"
    )
else
    CANDIDATE_DIRS=(
        "$PROJECT_DIR/.build/release"
        "$PROJECT_DIR/.build/$(uname -m)-apple-macosx/release"
    )
fi

CREEDFLOW_BIN=""
MCP_BIN=""
for dir in "${CANDIDATE_DIRS[@]}"; do
    if [ -x "$dir/CreedFlow" ] && [ -x "$dir/CreedFlowMCPServer" ]; then
        CREEDFLOW_BIN="$dir/CreedFlow"
        MCP_BIN="$dir/CreedFlowMCPServer"
        break
    fi
done

# Fallback: find by architecture
if [ -z "$CREEDFLOW_BIN" ]; then
    while IFS= read -r bin; do
        if [ -n "$TARGET_ARCH" ]; then
            if file "$bin" | grep -q "$TARGET_ARCH"; then
                CREEDFLOW_BIN="$bin"
                break
            fi
        else
            CREEDFLOW_BIN="$bin"
            break
        fi
    done < <(find "$PROJECT_DIR/.build" -name "CreedFlow" -type f -perm +111 \
        -not -path "*/CreedFlow.build/*" -not -path "*/CreedFlow.product/*" \
        -not -path "*/.build/checkouts/*" -not -path "*/dSYM/*" \
        -not -path "*/debug/*" 2>/dev/null)
    if [ -n "$CREEDFLOW_BIN" ]; then
        MCP_BIN="$(dirname "$CREEDFLOW_BIN")/CreedFlowMCPServer"
    fi
fi

BUILD_DIR=$(dirname "$CREEDFLOW_BIN")

if [ -z "$CREEDFLOW_BIN" ] || [ -z "$MCP_BIN" ]; then
    echo "ERROR: Could not find release binaries"
    echo "  CreedFlow: $CREEDFLOW_BIN"
    echo "  MCP Server: $MCP_BIN"
    find "$PROJECT_DIR/.build" -name "CreedFlow" -type f 2>/dev/null
    exit 1
fi
echo "  CreedFlow: $CREEDFLOW_BIN"
echo "  MCP Server: $MCP_BIN"
echo "  Build dir: $BUILD_DIR"
echo ""

# ─── Step 2: Create .app bundle structure ───
echo "→ Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# ─── Step 3: Copy executables ───
echo "→ Copying executables..."
cp "$CREEDFLOW_BIN" "$APP_BUNDLE/Contents/MacOS/CreedFlow"
cp "$MCP_BIN" "$APP_BUNDLE/Contents/MacOS/CreedFlowMCPServer"

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
fi

# ─── Step 6b: Copy SPM resource bundles ───
BUNDLE_COUNT=0
for bundle in "$BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        BUNDLE_NAME=$(basename "$bundle")
        echo "→ Copying resource bundle: $BUNDLE_NAME"
        cp -R "$bundle" "$APP_BUNDLE/$BUNDLE_NAME"
        BUNDLE_COUNT=$((BUNDLE_COUNT + 1))
    fi
done
if [ "$BUNDLE_COUNT" -gt 0 ]; then
    echo "  Copied $BUNDLE_COUNT resource bundle(s)."
else
    echo "→ No SPM resource bundles found."
fi

# ─── Step 7: Strip debug symbols ───
echo "→ Stripping debug symbols..."
strip -x "$APP_BUNDLE/Contents/MacOS/CreedFlow" 2>/dev/null || true
strip -x "$APP_BUNDLE/Contents/MacOS/CreedFlowMCPServer" 2>/dev/null || true

# ─── Step 8: Code sign ───
if [ -n "$SIGN_IDENTITY" ]; then
    echo "→ Code signing with identity: $SIGN_IDENTITY"
    codesign --force --deep --options runtime \
        --entitlements "$PROJECT_DIR/Resources/CreedFlow.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
    echo "  Code signing complete."
    codesign --verify --deep --strict "$APP_BUNDLE"
    echo "  Signature verified."
else
    echo "→ Ad-hoc signing for local use..."
    codesign --force --deep -s - "$APP_BUNDLE" 2>/dev/null || true
fi
echo ""

# ─── Step 9: Create DMG ───
if [ "$CREATE_DMG" = true ]; then
    DMG_NAME="CreedFlow-${VERSION}${DMG_ARCH_SUFFIX}.dmg"
    DMG_PATH="$DIST_DIR/$DMG_NAME"
    DMG_TEMP="$DIST_DIR/dmg-staging"

    echo "→ Creating DMG: $DMG_NAME"
    rm -rf "$DMG_TEMP" "$DMG_PATH"
    mkdir -p "$DMG_TEMP"

    cp -R "$APP_BUNDLE" "$DMG_TEMP/"
    ln -s /Applications "$DMG_TEMP/Applications"

    hdiutil create -volname "CreedFlow" \
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
MAIN_SIZE=$(ls -lh "$APP_BUNDLE/Contents/MacOS/CreedFlow" | awk '{print $5}')
MCP_SIZE=$(ls -lh "$APP_BUNDLE/Contents/MacOS/CreedFlowMCPServer" | awk '{print $5}')

echo "╔══════════════════════════════════════════╗"
echo "║           Package Complete               ║"
echo "╠══════════════════════════════════════════╣"
echo "║  App:  $APP_BUNDLE"
echo "║  Arch: $ARCH_LABEL"
echo "║  Size: $APP_SIZE total"
echo "║    CreedFlow:          $MAIN_SIZE"
echo "║    CreedFlowMCPServer: $MCP_SIZE"
echo "║  Version: $VERSION"
if [ -n "$SIGN_IDENTITY" ]; then
echo "║  Signed: $SIGN_IDENTITY"
else
echo "║  Signed: ad-hoc (local only)"
fi
echo "╚══════════════════════════════════════════╝"
echo ""
echo "To install:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo ""
echo "To run:"
echo "  open \"$APP_BUNDLE\""
