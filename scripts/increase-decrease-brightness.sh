#!/bin/bash

STEP="10%"

# Function to safely download and install brightnessctl from GitHub
install_brightnessctl() {
    echo "[!] brightnessctl not found. Fetching from GitHub..."
    
    # Detect package manager and install build dependencies
    if [ -x "$(command -v apt)" ]; then
        sudo apt update && sudo apt install -y git build-essential
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf groupinstall -y "Development Tools" && sudo dnf install -y git
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -Sy --needed --noconfirm base-devel git
    else
        echo "[-] Error: Could not determine your package manager to install build tools."
        exit 1
    fi

    # Clone and build from source
    local TEMP_DIR=$(mktemp -d)
    git clone https://github.com/Hummer12007/brightnessctl.git "$TEMP_DIR"
    
    cd "$TEMP_DIR" || exit 1
    make
    sudo make install
    
    # Clean up temp folder
    cd - > /dev/null || exit
    rm -rf "$TEMP_DIR"
    echo "[+] Build complete!"
}

# --- Main Logic ---

# 1. If completely missing from the system, install it
if ! [ -x "$(command -v brightnessctl)" ] && ! [ -x "/usr/bin/brightnessctl" ] && ! [ -x "/usr/local/bin/brightnessctl" ]; then
    install_brightnessctl
fi

# 2. Dynamically locate the binary path
if [ -x "$(command -v brightnessctl)" ]; then
    BIN_PATH=$(command -v brightnessctl)
elif [ -x "/usr/bin/brightnessctl" ]; then
    BIN_PATH="/usr/bin/brightnessctl"
elif [ -x "/usr/local/bin/brightnessctl" ]; then
    BIN_PATH="/usr/local/bin/brightnessctl"
else
    echo "[-] Error: brightnessctl installation failed or cannot be found."
    exit 1
fi

# 3. Ensure proper execution permissions on the discovered path
if [ ! -u "$BIN_PATH" ]; then
    sudo chmod +s "$BIN_PATH"
fi

# Helper function using the exact absolute path found
run_brightnessctl() {
    "$BIN_PATH" "$@"
}

# 4. Execute brightness control commands
case "$1" in
    up)
        run_brightnessctl set +$STEP
        ;;
    down)
        CURRENT=$(run_brightnessctl get)
        MAX=$(run_brightnessctl max)
        
        # Fallback safeguard if data fetching fails
        if [ -z "$CURRENT" ] || [ -z "$MAX" ] || [ "$MAX" -eq 0 ]; then
            run_brightnessctl set 10%-
        else
            PERCENT=$(( 100 * CURRENT / MAX ))
            # Don't let the screen go completely black (min 1%)
            if [ "$PERCENT" -le 10 ]; then
                run_brightnessctl set 1%
            else
                # Fixed: Appending the minus sign to the end (${STEP}-) 
                # avoids the "invalid option" flag parser error
                run_brightnessctl set ${STEP}-
            fi
        fi
        ;;
    *)
        echo "Usage: $0 {up|down}"
        exit 1
        ;;
esac
