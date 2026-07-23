#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/script/build_with_command_line_tools.sh"

BUILD_DIR="$ROOT_DIR/.build/command-line-tools"
SDK_PATH="$ROOT_DIR/.build/compat-sdk"
MODULE_CACHE="$BUILD_DIR/module-cache"
ARCHITECTURE="$(uname -m)"

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  -sdk "$SDK_PATH" \
  -target "$ARCHITECTURE-apple-macosx13.0" \
  -I "$ROOT_DIR/Sources/CSQLite" \
  -I "$BUILD_DIR" \
  "$BUILD_DIR/libNotesCore.a" \
  -lsqlite3 \
  -framework AppKit \
  "$ROOT_DIR/Tests/NotesCoreSmoke/main.swift" \
  -o "$BUILD_DIR/NotesCoreSmoke"

"$BUILD_DIR/NotesCoreSmoke"

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  -sdk "$SDK_PATH" \
  -target "$ARCHITECTURE-apple-macosx13.0" \
  -parse-as-library \
  -I "$ROOT_DIR/Sources/CSQLite" \
  -I "$BUILD_DIR" \
  "$BUILD_DIR/libNotesCore.a" \
  -lsqlite3 \
  -framework AppKit \
  "$ROOT_DIR/Tests/NotesCoreIndexSmoke/main.swift" \
  -o "$BUILD_DIR/NotesCoreIndexSmoke"

"$BUILD_DIR/NotesCoreIndexSmoke"
