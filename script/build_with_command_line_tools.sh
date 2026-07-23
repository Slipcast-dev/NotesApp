#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_LINK="$(xcrun --sdk macosx --show-sdk-path)"
SOURCE_SDK="$(cd "$SDK_LINK" && pwd -P)"
COMPAT_SDK="$ROOT_DIR/.build/compat-sdk"
BUILD_DIR="$ROOT_DIR/.build/command-line-tools"
MODULE_CACHE="$BUILD_DIR/module-cache"
COMPILER_VERSION="$(swiftc --version | sed -n '1p')"
VERSION_MARKER="$COMPAT_SDK/.notesapp-compiler-version"
ARCHITECTURE="$(uname -m)"
TARGET="$ARCHITECTURE-apple-macosx13.0"

mkdir -p "$ROOT_DIR/.build" "$BUILD_DIR" "$MODULE_CACHE"

# Some older Ventura Command Line Tools installations contain an SDK whose
# textual Swift modules were produced by a slightly different patch release.
# A copy-on-write SDK copy keeps the system installation untouched while the
# version header is normalized for the installed compiler.
if [[ ! -f "$VERSION_MARKER" ]] || [[ "$(<"$VERSION_MARKER")" != "$COMPILER_VERSION" ]]; then
  rm -rf "$COMPAT_SDK"
  cp -cR "$SOURCE_SDK" "$COMPAT_SDK"
  find "$COMPAT_SDK" -type f -name '*.swiftinterface' \
    -exec sed -i '' -e "s|^// swift-compiler-version:.*$|// swift-compiler-version: $COMPILER_VERSION|" {} +
  printf '%s\n' "$COMPILER_VERSION" > "$VERSION_MARKER"
fi

COMMON_FLAGS=(
  -module-cache-path "$MODULE_CACHE"
  -sdk "$COMPAT_SDK"
  -target "$TARGET"
)

if [[ "${NOTESAPP_BUILD_CONFIGURATION:-debug}" == "release" ]]; then
  COMMON_FLAGS+=(-O)
fi

CORE_SOURCES=(
  "$ROOT_DIR"/Sources/NotesCore/Models/*.swift
  "$ROOT_DIR"/Sources/NotesCore/Markdown/*.swift
  "$ROOT_DIR"/Sources/NotesCore/Index/*.swift
  "$ROOT_DIR"/Sources/NotesCore/Links/*.swift
  "$ROOT_DIR"/Sources/NotesCore/Attachments/*.swift
  "$ROOT_DIR"/Sources/NotesCore/Services/*.swift
  "$ROOT_DIR"/Sources/NotesCore/Support/*.swift
)

APP_SOURCES=(
  "$ROOT_DIR"/Sources/NotesApp/App/*.swift
  "$ROOT_DIR"/Sources/NotesApp/Stores/*.swift
  "$ROOT_DIR"/Sources/NotesApp/Support/*.swift
  "$ROOT_DIR"/Sources/NotesApp/Views/*.swift
)

swiftc -parse-as-library -emit-module -emit-library -static \
  -module-name NotesCore \
  "${COMMON_FLAGS[@]}" \
  -I "$ROOT_DIR/Sources/CSQLite" \
  "${CORE_SOURCES[@]}" \
  -lsqlite3 \
  -emit-module-path "$BUILD_DIR/NotesCore.swiftmodule" \
  -o "$BUILD_DIR/libNotesCore.a"

swiftc -parse-as-library \
  -module-name NotesApp \
  "${COMMON_FLAGS[@]}" \
  -I "$ROOT_DIR/Sources/CSQLite" \
  -I "$BUILD_DIR" \
  "$BUILD_DIR/libNotesCore.a" \
  -lsqlite3 \
  "${APP_SOURCES[@]}" \
  -o "$BUILD_DIR/NotesApp"
