#!/usr/bin/env bash
# Packages the `flutter build linux --release` output into a single
# portable AppImage via linuxdeploy + appimagetool. Runnable identically
# in CI (aion/.github/workflows/release.yml) or locally on any Linux dev
# machine. Usage: linux/packaging/build_appimage.sh <version>
set -euo pipefail

VERSION="${1:?usage: build_appimage.sh <version>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/build/linux/x64/release/bundle"
WORK_DIR="$REPO_ROOT/build/appimage"
APPDIR="$WORK_DIR/AppDir"
TOOLS_DIR="$WORK_DIR/tools"

LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20250213-2/linuxdeploy-x86_64.AppImage"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "error: $BUNDLE_DIR not found — run 'flutter build linux --release' first" >&2
  exit 1
fi

mkdir -p "$TOOLS_DIR"
rm -rf "$APPDIR"
mkdir -p "$APPDIR"

fetch_tool() {
  local url="$1" dest="$2"
  if [ ! -x "$dest" ]; then
    curl -fL "$url" -o "$dest"
    chmod +x "$dest"
  fi
}

fetch_tool "$LINUXDEPLOY_URL" "$TOOLS_DIR/linuxdeploy.AppImage"
fetch_tool "$APPIMAGETOOL_URL" "$TOOLS_DIR/appimagetool.AppImage"

# linuxdeploy expects the icon file's basename (minus extension) to match
# the .desktop file's Icon= key ("aion") — the closest existing app icon
# in this repo is the macOS 1024x1024 PNG, since no dedicated Linux/AppImage
# icon asset exists yet.
ICON_SRC="$REPO_ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
ICON_STAGED="$WORK_DIR/aion.png"
cp "$ICON_SRC" "$ICON_STAGED"

"$TOOLS_DIR/linuxdeploy.AppImage" \
  --appdir "$APPDIR" \
  --executable "$BUNDLE_DIR/aion" \
  --desktop-file "$REPO_ROOT/linux/packaging/aion.desktop" \
  --icon-file "$ICON_STAGED"

# linuxdeploy only stages the executable itself — copy the rest of the
# Flutter bundle (engine lib, ICU data, plugin .so files) alongside it so
# the packaged binary can find them at runtime.
cp -r "$BUNDLE_DIR/data" "$APPDIR/usr/bin/"
cp -r "$BUNDLE_DIR/lib/." "$APPDIR/usr/lib/"

OUTPUT="$REPO_ROOT/Aion-${VERSION}-x86_64.AppImage"
"$TOOLS_DIR/appimagetool.AppImage" "$APPDIR" "$OUTPUT"

echo "built $OUTPUT"
