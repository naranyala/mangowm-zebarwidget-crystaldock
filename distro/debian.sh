#!/bin/bash
set -euo pipefail
echo "Installing OCWS dependencies for Debian/Ubuntu..."
apt update
PKGS=(
    labwc rofi foot mako-notifier qt6ct libqt6svg6-dev
    swaybg swayidle swaylock gammastep
    playerctl wl-clipboard grim slurp flameshot
    jq crudini libxml2-utils brightnessctl wlr-randr
    nautilus gnome-keyring xdotool inotify-tools imagemagick wireplumber
    network-manager bluez libnotify-bin fonts-noto fonts-dejavu-core
    rsync fuzzel cliphist fonts-firacode libgtk-3-dev
)
# sfwbar — not in Ubuntu repos, will be handled separately
if apt-cache show sfwbar >/dev/null 2>&1; then
    PKGS+=(sfwbar)
fi
apt install -y "${PKGS[@]}"
echo ""
echo "APT dependencies successfully installed."
