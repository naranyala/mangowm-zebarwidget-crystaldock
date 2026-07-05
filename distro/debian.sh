#!/bin/bash
set -euo pipefail

echo "Installing OCWS dependencies for Debian/Ubuntu..."

sudo apt update

PKGS=(
    labwc fuzzel foot rofi mako-notifier qt6ct
    swaybg swayidle swaylock gammastep dunst
    playerctl wl-clipboard grim slurp flameshot
    jq crudini libxml2-utils brightnessctl wlr-randr nautilus gnome-keyring xdotool inotify-tools imagemagick wireplumber
)

# sfwbar is usually not in standard Debian repos, we may need a warning
if ! apt-cache show sfwbar >/dev/null 2>&1; then
    echo "Warning: sfwbar is not in the default apt repos. You may need to compile it from source."
else
    PKGS+=(sfwbar)
fi

# cliphist is often missing in older Ubuntu
if apt-cache show cliphist >/dev/null 2>&1; then
    PKGS+=(cliphist)
fi

sudo apt install -y "${PKGS[@]}"

echo "Dependencies successfully installed."
