#!/bin/bash
set -euo pipefail

echo "================================================="
echo "Building and Installing Noctalia Shell"
echo "================================================="

# Ensure just is installed
if ! command -v just >/dev/null 2>&1; then
    echo "Error: 'just' command runner is required but not installed."
    echo "Please run ./scripts/install-noctalia-deps.sh first!"
    exit 1
fi

BUILD_DIR="$HOME/build/noctalia-src"
mkdir -p "$HOME/build"

if [ -d "$BUILD_DIR" ]; then
    echo "--> Removing existing source directory..."
    rm -rf "$BUILD_DIR"
fi

echo "--> Cloning Noctalia repository..."
git clone --depth 1 https://github.com/noctalia-dev/noctalia.git "$BUILD_DIR"

cd "$BUILD_DIR"

echo "--> Configuring build..."
just configure release ~/.local

echo "--> Building Noctalia..."
just build release

echo "--> Installing..."
just install release

echo "--> Setting up default config..."
mkdir -p ~/.config/noctalia
if [ ! -f ~/.config/noctalia/config.toml ]; then
    cp example.toml ~/.config/noctalia/config.toml
    echo "--> Created default config at ~/.config/noctalia/config.toml"
else
    echo "--> Config already exists at ~/.config/noctalia/config.toml, skipping copy."
fi

# Explicitly tell labwc autostart to use noctalia over sfwbar
mkdir -p ~/.config/labwc-widgets
echo '{
  "statusbar": "noctalia",
  "dock": "crystal"
}' > ~/.config/labwc-widgets/status.json

echo ""
echo "Noctalia shell installed and configured successfully!"
echo "It will automatically start next time you log into your labwc session."
