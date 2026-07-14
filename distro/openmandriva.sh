#!/bin/bash
# -------------------------------------------------------------------
# OCWS OpenMandriva Dependency Installer
# -------------------------------------------------------------------

set -euo pipefail

echo "Installing OCWS dependencies for OpenMandriva Lx..."

PKGS=(
    labwc
    sfwbar
    fuzzel
    foot
    playerctl
    grim
    slurp
    wl-clipboard
    brightnessctl
    jq
    inotify-tools
    swaybg
    swayidle
    swaylock
    mako
    cliphist
    qt6ct
    lib64Qt6Svg
    lib64Qt6Svg-devel
    xdotool
    imagemagick
    wireplumber
    bluez
    libnotify
    rsync
    flameshot
    fonts-ttf-dejavu
    adobe-source-code-pro-fonts
)

# Build tools for compiling optional plugins / dms / etc.
PKGS+=(
    git
    meson
    ninja
    pkgconf
    gcc
    gcc-c++
    make
    cmake
    lib64glib2.0-devel
    lib64gtk+3.0-devel
)

# Privilege escalation: try pkexec, fall back to sudo
elevate() {
    if command -v pkexec &>/dev/null; then
        pkexec "$@"
    elif command -v sudo &>/dev/null; then
        sudo "$@"
    else
        echo "Error: Neither pkexec nor sudo available." >&2
        exit 1
    fi
}

echo "Installing packages..."
elevate dnf install -y "${PKGS[@]}"

echo ""
echo "Dependencies successfully installed for OpenMandriva Lx."
