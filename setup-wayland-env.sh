#!/usr/bin/env bash

# Wayland-First Environment Setup Script
# This creates a systemd environment.d configuration file to ensure
# all apps (Firefox, Qt, GTK, Electron) default to Wayland native mode.

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==>${NC} Setting up Wayland-First Environment Variables..."

ENV_DIR="${HOME}/.config/environment.d"
ENV_FILE="${ENV_DIR}/10-wayland.conf"

mkdir -p "$ENV_DIR"

cat << 'EOF' > "$ENV_FILE"
# Wayland-First Environment Configuration
# Loaded automatically by systemd at user login

# Core Wayland Session
XDG_SESSION_TYPE=wayland

# Qt (KDE apps, OBS, etc) - Prefer Wayland, fallback to X11
QT_QPA_PLATFORM="wayland;xcb"
QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# GTK (GNOME apps) - Prefer Wayland, fallback to X11
GDK_BACKEND="wayland,x11"
CLUTTER_BACKEND=wayland

# Firefox / Mozilla Apps
MOZ_ENABLE_WAYLAND=1

# Electron / Chromium Apps (VSCode, Discord, Chrome, Brave)
OZONE_PLATFORM=wayland
ELECTRON_OZONE_PLATFORM_HINT=wayland

# SDL2 (Games)
SDL_VIDEODRIVER="wayland,x11"

# Java Apps (AWT) - Fix blank windows in some Java apps under Wayland/Xwayland
_JAVA_AWT_WM_NONREPARENTING=1
EOF

echo -e "  ${GREEN}✓${NC} Created ${ENV_FILE}"
echo -e "  ${GREEN}✓${NC} Apps like Firefox, Electron, and Qt will now default to Wayland natively."
echo ""
echo "Note: For these variables to take effect, you must log completely out"
echo "and log back into your Wayland session (e.g. Labwc)."
