#!/bin/bash
# -------------------------------------------------------------------
# OCWS Session Registration Validator
# -------------------------------------------------------------------

set -uo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

WAYLAND_SESSIONS_DIR="/usr/share/wayland-sessions"
LABWC_DESKTOP="${WAYLAND_SESSIONS_DIR}/labwc.desktop"

echo -e "\n${CYAN}==> Checking Login Manager Session Configuration...${NC}"

if [ -f "$LABWC_DESKTOP" ]; then
    echo -e "  ${GREEN}✓${NC} labwc session is registered in ${LABWC_DESKTOP}"
    echo "  Content of desktop file:"
    echo "----------------------------------------"
    cat "$LABWC_DESKTOP"
    echo "----------------------------------------"
    echo -e "  ${GREEN}✓ Validation Successful! labwc is available in your login manager session picker.${NC}"
    exit 0
else
    echo -e "  ${RED}✗ labwc session file not found in ${WAYLAND_SESSIONS_DIR}${NC}"
    echo "  Attempting to register labwc as a login manager session option..."
    
    DESKTOP_CONTENT="[Desktop Entry]
Name=labwc
Comment=A wayland stacking compositor
Exec=labwc
Icon=labwc
Type=Application
DesktopNames=labwc;wlroots"

    TEMP_FILE="/tmp/labwc.desktop"
    echo "$DESKTOP_CONTENT" > "$TEMP_FILE"
    
    if command -v pkexec &>/dev/null; then
        echo "Requesting privileges to register session..."
        if pkexec bash -c "mkdir -p '${WAYLAND_SESSIONS_DIR}' && cp '${TEMP_FILE}' '${LABWC_DESKTOP}' && chmod 644 '${LABWC_DESKTOP}'"; then
            echo -e "  ${GREEN}✓ labwc session registered successfully!${NC}"
            rm -f "$TEMP_FILE"
            exit 0
        else
            echo -e "  ${RED}✗ Failed to write session file. Please run manually as root:${NC}"
            echo "    sudo mkdir -p ${WAYLAND_SESSIONS_DIR}"
            echo "    sudo cp ${TEMP_FILE} ${LABWC_DESKTOP}"
            rm -f "$TEMP_FILE"
            exit 1
        fi
    else
        echo -e "  ${RED}✗ pkexec not found. Please register manually as root:${NC}"
        echo "    sudo mkdir -p ${WAYLAND_SESSIONS_DIR}"
        echo "    sudo tee ${LABWC_DESKTOP} <<EOF"
        echo "$DESKTOP_CONTENT"
        echo "EOF"
        rm -f "$TEMP_FILE"
        exit 1
    fi
fi
