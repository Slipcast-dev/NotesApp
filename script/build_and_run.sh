#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="NotesApp"
BUNDLE_ID="dev.slipcast.NotesApp"
MIN_SYSTEM_VERSION="13.0"
APP_VERSION="${NOTESAPP_VERSION:-2.0.0}"
PACKAGE_VERSION="${NOTESAPP_PACKAGE_VERSION:-$APP_VERSION}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="NotebookPurple.png"

if [[ "$MODE" != "--bundle" && "$MODE" != "bundle" && "$MODE" != "--package" && "$MODE" != "package" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

BUILD_CONFIGURATION_ARGS=()
if [[ "$MODE" == "--bundle" || "$MODE" == "bundle" || "$MODE" == "--package" || "$MODE" == "package" ]]; then
  BUILD_CONFIGURATION_ARGS=(-c release)
fi

if swift build "${BUILD_CONFIGURATION_ARGS[@]}"; then
  BUILD_BINARY="$(swift build "${BUILD_CONFIGURATION_ARGS[@]}" --show-bin-path)/$APP_NAME"
else
  echo "SwiftPM is unavailable with the active Command Line Tools; using the Ventura-compatible fallback build." >&2
  if [[ ${#BUILD_CONFIGURATION_ARGS[@]} -gt 0 ]]; then
    NOTESAPP_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_with_command_line_tools.sh"
  else
    "$ROOT_DIR/script/build_with_command_line_tools.sh"
  fi
  BUILD_BINARY="$ROOT_DIR/.build/command-line-tools/$APP_NAME"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ROOT_DIR/NotesApp/NotesApp/Assets/NotebookPurple.png" ]]; then
  ICON_SOURCE="$ROOT_DIR/NotesApp/NotesApp/Assets/NotebookPurple.png"
  ICONSET="$ROOT_DIR/.build/NotesApp.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

  if iconutil -c icns "$ICONSET" -o "$APP_RESOURCES/NotesApp.icns"; then
    ICON_FILE="NotesApp.icns"
  else
    cp "$ICON_SOURCE" "$APP_RESOURCES/NotebookPurple.png"
  fi
fi

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_FILE</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>ru</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null
codesign --force --deep --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --bundle|bundle)
    echo "App bundle created: $APP_BUNDLE"
    ;;
  --package|package)
    ARCHITECTURE="${NOTESAPP_ARCHITECTURE:-$(uname -m)}"
    PACKAGE_PATH="$DIST_DIR/$APP_NAME-v$PACKAGE_VERSION-macOS-$ARCHITECTURE.zip"
    rm -f "$PACKAGE_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$PACKAGE_PATH"
    echo "Release package created: $PACKAGE_PATH"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--bundle|--package]" >&2
    exit 2
    ;;
esac
