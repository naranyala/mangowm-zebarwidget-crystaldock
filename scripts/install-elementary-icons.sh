#!/usr/bin/env bash
set -euo pipefail
# install-elementary-icons.sh
# Downloads and installs the elementary icon theme
# https://github.com/elementary/icons

REPO="https://github.com/elementary/icons.git"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/icons/elementary"
TMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Downloading elementary icons..."

if ! git clone --depth 1 "$REPO" "$TMP_DIR/elementary" 2>/dev/null; then
    echo "Error: git clone failed. Install git and try again."
    exit 1
fi

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
mv "$TMP_DIR/elementary" "$DEST"

gtk-update-icon-cache -f "$DEST" 2>/dev/null || true

echo "Installed to $DEST"
echo "Run 'theme-engine.sh apply' to regenerate configs with elementary as default,"
echo "or use icon-theme-picker.sh to switch at runtime."
