#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
APP_DIR="$PROJECT_DIR/packaging/AppDir"
OUTPUT="$PROJECT_DIR/dist/PortaGallery-x86_64.AppImage"
APP_NAME="photo_gallery"

export PATH="$HOME/.local/bin:$HOME/flutter/bin:$PATH"

echo "==> Building Flutter Linux release bundle..."
cd "$PROJECT_DIR"
flutter build linux --release

echo "==> Assembling AppDir..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

cp -r "$BUNDLE_DIR/." "$APP_DIR/"

cp "$PROJECT_DIR/packaging/AppRun" "$APP_DIR/AppRun"
chmod +x "$APP_DIR/AppRun"

cp "$PROJECT_DIR/packaging/photo_gallery.desktop" "$APP_DIR/$APP_NAME.desktop"

mkdir -p "$APP_DIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APP_DIR/usr/share/applications"
ICON_SRC="$PROJECT_DIR/packaging/logo.png"
if [ -f "$ICON_SRC" ]; then
  # Center-crop the logo to a square icon (256 and 512 px) using ImageMagick.
  magick "$ICON_SRC" -resize '512x512^' -gravity center -extent 512x512 \
    "$APP_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" \
    || convert "$ICON_SRC" -resize '512x512^' -gravity center -extent 512x512 \
    "$APP_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
  cp "$APP_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" "$APP_DIR/$APP_NAME.png"
else
  echo "WARNING: packaging/logo.png not found, using generated placeholder icon."
  convert -size 256x256 gradient:'#6750A4'-'#3E2B6E' \
    "$APP_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" 2>/dev/null \
    || magick -size 256x256 gradient:'#6750A4'-'#3E2B6E' \
      "$APP_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
  cp "$APP_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" "$APP_DIR/$APP_NAME.png"
fi

cp "$PROJECT_DIR/packaging/photo_gallery.desktop" \
   "$APP_DIR/usr/share/applications/$APP_NAME.desktop"

echo "==> Packaging AppImage..."
mkdir -p "$PROJECT_DIR/dist"
if command -v appimagetool >/dev/null 2>&1; then
  ARCH=x86_64 appimagetool "$APP_DIR" "$OUTPUT"
else
  APPIMAGE_EXTRACT_AND_RUN=1 "$HOME/.local/bin/appimagetool" "$APP_DIR" "$OUTPUT"
fi
chmod +x "$OUTPUT"

echo "==> Done: $OUTPUT"