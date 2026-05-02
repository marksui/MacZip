#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.1.0"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MarkMacZip.app"
DMG_STAGING_DIR="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/MarkMacZip-v$VERSION.dmg"
EXECUTABLE_NAME="MyArchiveGUI"
EXECUTABLE_PATH="$BUILD_DIR/$EXECUTABLE_NAME"
ICON_PATH="$ROOT_DIR/Resources/MarkMacZip.icns"
ICON_NAME="MarkMacZip.icns"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script must be run on macOS."
  exit 1
fi

mkdir -p "$DIST_DIR"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift toolchain not found. Install Xcode or Xcode Command Line Tools."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode or Xcode Command Line Tools."
  exit 1
fi

if ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
  cat <<'EOF'
Unable to locate a valid macOS SDK via xcrun.
Fix your developer tools setup, then retry:
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  xcodebuild -runFirstLaunch
Or reinstall Command Line Tools:
  xcode-select --install
EOF
  exit 1
fi

# If OpenSSL is installed by Homebrew, surface its pkg-config metadata for swift build.
if command -v brew >/dev/null 2>&1 && brew --prefix openssl@3 >/dev/null 2>&1; then
  OPENSSL_PREFIX="$(brew --prefix openssl@3)"
  export PKG_CONFIG_PATH="$OPENSSL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CPPFLAGS="-I$OPENSSL_PREFIX/include ${CPPFLAGS:-}"
  export LDFLAGS="-L$OPENSSL_PREFIX/lib ${LDFLAGS:-}"
fi

swift build -c release --product "$EXECUTABLE_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$APP_DIR/Contents/Resources/$ICON_NAME"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>MyArchiveGUI</string>
  <key>CFBundleIdentifier</key>
  <string>com.markmaczip.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>5.0</string>
  <key>CFBundleName</key>
  <string>MarkMacZip</string>
  <key>CFBundleDisplayName</key>
  <string>MarkMacZip</string>
  <key>CFBundleIconFile</key>
  <string>MarkMacZip.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Bundle Swift runtime libraries.
if command -v xcrun >/dev/null 2>&1; then
  xcrun swift-stdlib-tool \
    --copy \
    --platform macosx \
    --scan-executable "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" \
    --destination "$APP_DIR/Contents/Frameworks"
fi

# Bundle libcrypto if linked from Homebrew OpenSSL.
if command -v otool >/dev/null 2>&1; then
  LINKED_CRYPTO="$(otool -L "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" | awk '/libcrypto/ {print $1; exit}')"
  if [[ -n "$LINKED_CRYPTO" && -f "$LINKED_CRYPTO" ]]; then
    cp "$LINKED_CRYPTO" "$APP_DIR/Contents/Frameworks/"
    CRYPTO_BASENAME="$(basename "$LINKED_CRYPTO")"
    install_name_tool -id "@executable_path/../Frameworks/$CRYPTO_BASENAME" "$APP_DIR/Contents/Frameworks/$CRYPTO_BASENAME"
    install_name_tool -change "$LINKED_CRYPTO" "@executable_path/../Frameworks/$CRYPTO_BASENAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
  fi
fi

# Ad-hoc sign so Gatekeeper at least sees a valid code signature.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR"
fi

rm -rf "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_DIR" "$DMG_STAGING_DIR/MarkMacZip.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "MarkMacZip" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_STAGING_DIR"

echo "Created $APP_DIR"
echo "Created $DMG_PATH"
