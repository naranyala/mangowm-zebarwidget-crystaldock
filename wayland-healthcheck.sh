#!/usr/bin/env bash

# Wayland Integration Health Check Script
# Focuses on labwc, xdg-desktop-portal, pipewire, and critical environment variables

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}   Wayland Integration Health Check      ${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# 1. Environment Variables
echo -e "${CYAN}[1/6] Checking Wayland Environment Variables...${NC}"
vars=("XDG_SESSION_TYPE" "WAYLAND_DISPLAY" "XDG_CURRENT_DESKTOP" "XDG_RUNTIME_DIR" "QT_QPA_PLATFORM" "MOZ_ENABLE_WAYLAND")
for v in "${vars[@]}"; do
    if [ -z "${!v}" ]; then
        echo -e "  ${YELLOW}[WARN]${NC} $v is NOT set."
    else
        echo -e "  ${GREEN}[OK]${NC}   $v = ${!v}"
    fi
done

# Check if actually running Wayland right now
if [ "$XDG_SESSION_TYPE" != "wayland" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    echo -e "  ${RED}[!]${NC} You do not appear to be running this inside a Wayland session right now."
fi
echo ""

# 2. XDG Desktop Portals (Critical for app integration/screensharing)
echo -e "${CYAN}[2/6] Checking XDG Desktop Portals...${NC}"
portals=("xdg-desktop-portal" "xdg-desktop-portal-wlr" "xdg-desktop-portal-gtk")
for p in "${portals[@]}"; do
    if pgrep -f "$p" > /dev/null; then
        echo -e "  ${GREEN}[OK]${NC}   $p is RUNNING"
    elif command -v "$p" >/dev/null || ls /usr/libexec/$p 1>/dev/null 2>&1; then
        echo -e "  ${YELLOW}[INFO]${NC} $p is installed but NOT running"
    else
        echo -e "  ${RED}[FAIL]${NC} $p is NOT installed (Required for screensharing/file dialogs)"
    fi
done
echo ""

# 3. Audio & Video (PipeWire/WirePlumber)
echo -e "${CYAN}[3/6] Checking PipeWire & WirePlumber...${NC}"
for p in "pipewire" "wireplumber" "pipewire-pulse"; do
    if pgrep -x "$p" > /dev/null; then
        echo -e "  ${GREEN}[OK]${NC}   $p is RUNNING"
    else
        echo -e "  ${RED}[FAIL]${NC} $p is NOT running (Audio/Screensharing may be broken)"
    fi
done
echo ""

# 4. Polkit Authentication Agent
echo -e "${CYAN}[4/6] Checking Polkit Agent...${NC}"
if pgrep -f "polkit" > /dev/null; then
    echo -e "  ${GREEN}[OK]${NC}   A Polkit agent is running"
else
    echo -e "  ${YELLOW}[WARN]${NC} No Polkit agent seems to be running. GUI apps needing sudo will fail to prompt."
fi
echo ""

# 5. Core Utilities (labwc, fuzzel, sfwbar)
echo -e "${CYAN}[5/6] Checking Core Dotfiles Utilities...${NC}"
utils=("labwc" "fuzzel" "sfwbar" "wl-clipboard" "grim" "slurp")
for u in "${utils[@]}"; do
    if command -v "$u" > /dev/null; then
        echo -e "  ${GREEN}[OK]${NC}   $u is installed"
    else
        echo -e "  ${RED}[FAIL]${NC} $u is missing"
    fi
done
echo ""

# 6. Graphics Drivers
echo -e "${CYAN}[6/6] Checking Graphics Drivers loaded...${NC}"
if lsmod | grep -iq nvidia; then
    echo -e "  ${YELLOW}[INFO]${NC} NVIDIA driver detected."
    echo "         Make sure WLR_NO_HARDWARE_CURSORS=1 is set if you have cursor issues."
    echo "         Make sure nvidia-drm.modeset=1 is set in your kernel parameters."
elif lsmod | grep -iq amdgpu; then
    echo -e "  ${GREEN}[INFO]${NC} AMDGPU driver detected."
elif lsmod | grep -iq i915; then
    echo -e "  ${GREEN}[INFO]${NC} Intel (i915) driver detected."
else
    echo -e "  ${YELLOW}[WARN]${NC} No standard AMD/NVIDIA/Intel graphics module detected. Are you in a VM?"
fi
echo ""

echo -e "${CYAN}=========================================${NC}"
echo "Health check complete. Review any [FAIL] or [WARN] messages above."
echo "If your integration is broken, XDG portals or missing environment variables are the most common culprits."
