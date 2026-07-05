#!/bin/bash
set -euo pipefail

echo "Installing OCWS dependencies for Arch Linux..."

PKGS=(
    labwc sfwbar fuzzel foot rofi mako qt6ct
    swaybg swayidle swaylock gammastep dunst
    playerctl wl-clipboard cliphist grim slurp flameshot
    jq crudini libxml2 brightnessctl wlr-randr nautilus gnome-keyring xdotool inotify-tools imagemagick wireplumber
)

# Use paru or yay if available, otherwise fallback to pacman
if command -v paru >/dev/null 2>&1; then
    paru -S --needed "${PKGS[@]}"
elif command -v yay >/dev/null 2>&1; then
    yay -S --needed "${PKGS[@]}"
else
    sudo pacman -S --needed "${PKGS[@]}"
fi

echo "Dependencies successfully installed."
