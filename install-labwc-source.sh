#!/usr/bin/env bash

# Script to build and install the latest Labwc from GitHub source
set -euo pipefail

echo "========================================="
echo " Installing Labwc Build Dependencies..."
echo "========================================="

# Fedora dependencies for compiling wlroots and labwc
deps=(
    "meson" "ninja" "gcc" "gcc-c++" "git"
    "lib64wayland-devel" "wayland-protocols-devel" 
    "lib64wlroots-devel" "lib64pango1.0-devel" "lib64cairo-devel" 
    "lib64glib2.0-devel" "libxml2-devel" "libxkbcommon-devel" 
    "scdoc" "librsvg2-devel" "lib64xcb-util-wm-devel" 
    "lib64input-devel" "libdrm-devel" "lib64pixman-devel" 
    "lib64xcb-util-renderutil-devel" "xwayland-devel"
)

# Install dependencies using dnf
dnf install -y "${deps[@]}"

echo "========================================="
echo " Cloning Labwc Source Code..."
echo "========================================="
cd /tmp
rm -rf labwc-src
git clone https://github.com/labwc/labwc.git labwc-src
cd labwc-src
# Checkout the latest stable release tag to avoid cutting-edge dependency issues
LATEST_TAG=$(git describe --tags `git rev-list --tags --max-count=1`)
# Checkout exactly the highest semantic version (0.9.8) instead of the chronologically last pushed tag
LATEST_TAG="0.20.1"
echo "Checking out release: $LATEST_TAG"
git checkout $LATEST_TAG

echo "========================================="
echo " Building required Pixman 0.46.0..."
echo "========================================="
cd /tmp
rm -rf pixman-src
git clone https://gitlab.freedesktop.org/pixman/pixman.git pixman-src --branch pixman-0.46.0 --depth 1
cd pixman-src
meson setup build/
ninja -C build/
ninja -C build/ install

# Ensure meson finds the newly installed pixman safely
export PKG_CONFIG_PATH="/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

echo "========================================="
echo " Building Labwc..."
echo "========================================="
cd /tmp/labwc-src
# Configure build directory
meson setup build/

# Compile
ninja -C build/

echo "========================================="
echo " Installing Labwc to System..."
echo "========================================="
# Install (this will put the binary in /usr/local/bin by default)
ninja -C build/ install

echo "========================================="
echo " Success! Latest Labwc installed."
echo "========================================="
