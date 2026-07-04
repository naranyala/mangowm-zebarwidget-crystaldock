#!/bin/bash
# ocws-configure.sh — Native configuration utilities for OCWS
# 
# Central configuration management for all OCWS components
# Primary purpose: simplify setup and configuration

set -uo pipefail

OCWS_DIR="${OCWS_DIR:-$HOME/.config/ocws}"
STATE_DIR="$OCWS_DIR/state"
mkdir -p "$STATE_DIR"

# Initialize shell environment and validate setup
init_shell() {
    echo "Initializing OCWS shell environment..."
    
    # Check for essential components
    local essential_commands=("playerctl" "wpctl" "swaylock" "grim" "slurp")
    local missing_commands=()
    
    for cmd in "${essential_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        echo "Warning: Missing recommended commands: ${missing_commands[*]}"
        echo "Install with: paru -S playerctl wayland swaylock grim slurp"
    fi
    
    # Create essential directories
    mkdir -p "$OCWS_DIR/plugins"
    mkdir -p "$OCWS_DIR/dotfiles/ocws"
    mkdir -p "$OCWS_DIR/cover-art"
    
    echo "Shell environment initialized"
}

# Setup essential configuration files
init_config() {
    echo "Setting up OCWS configuration..."
    
    # Create essential config files if they don't exist
    if [[ ! -f "$OCWS_DIR/ocws-daemon.sh" ]]; then
        cp "/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar/dotfiles/ocws/ocws-daemon.sh" "$OCWS_DIR/" 2>/dev/null || true
        chmod +x "$OCWS_DIR/ocws-daemon.sh"
    fi
    
    if [[ ! -f "$OCWS_DIR/ocws-emit.sh" ]]; then
        cp "/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar/scripts/ocws-emit.sh" "$OCWS_DIR/" 2>/dev/null || true
        chmod +x "$OCWS_DIR/ocws-emit.sh"
    fi
    
    if [[ ! -f "$OCWS_DIR/ocws-plugin-loader.sh" ]]; then
        cp "/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar/scripts/ocws-plugin-loader.sh" "$OCWS_DIR/" 2>/dev/null || true
        chmod +x "$OCWS_DIR/ocws-plugin-loader.sh"
    fi
    
    # Create dotfiles/ocws directory
    mkdir -p "$OCWS_DIR/dotfiles/ocws"
    
    # Create essential widget files if they don't exist
    if [[ ! -f "$OCWS_DIR/dotfiles/ocws/ocws.config" ]]; then
        cp "/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar/dotfiles/ocws/ocws.config" "$OCWS_DIR/dotfiles/ocws/" 2>/dev/null || true
    fi
    
    echo "Configuration setup complete"
}

# Setup display environment
init_display() {
    echo "Setting up display environment..."
    
    # Check for Wayland
    if [[ -z "$WAYLAND_DISPLAY" && -z "$DISPLAY" ]]; then
        echo "No Wayland or X11 session detected"
        echo "Start OCWS with: env WAYLAND_DISPLAY=wayland labwc"
    elif [[ -n "$WAYLAND_DISPLAY" ]]; then
        echo "Wayland session detected: $WAYLAND_DISPLAY"
        echo "OCWS should start automatically with your compositor"
    fi
    
    echo "Display environment checked"
}

# Setup theme and appearance
init_theme() {
    echo "Setting up default theme..."
    
    # Apply default theme if theme-engine exists
    if [[ -f "/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar/scripts/theme-engine.sh" ]]; then
        local theme_file="/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar/themes/catppuccin-mocha.ini"
        
        if [[ -f "$theme_file" ]]; then
            # Preview theme without applying
            echo "Theme available: $theme_file"
            echo "Apply with: $OCWS_DIR/scripts/theme-engine.sh apply $theme_file"
        fi
    fi
    
    echo "Theme environment prepared"
}

# Setup audio and multimedia
init_audio() {
    echo "Setting up audio environment..."
    
    # Check PulseAudio/PipeWire
    if command -v wpctl >/dev/null 2>&1; then
        echo "PulseAudio/PipeWire detected"
        
        # Get current volume for reference
        local current_volume
        current_volume=$(wpctl get-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '[\d.]+' || echo "N/A")
        echo "Current volume: $current_volume"
    else
        echo "PulseAudio/PipeWire not available - audio features limited"
    fi
    
    # Check playerctl
    if command -v playerctl >/dev/null 2>&1; then
        echo "Playerctl available for media control"
    else
        echo "playerctl not installed - install with: paru -S playerctl"
    fi
    
    echo "Audio environment checked"
}

# Setup input devices
init_input() {
    echo "Setting up input environment..."
    
    # Check keyboard shortcuts tools
    local input_tools=("swaymsg" "xdotool" "wl-clipboard")
    echo "Available input tools:"
    
    for tool in "${input_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  ✓ $tool"
        else
            echo "  - $tool (optional)"
        fi
    done
    
    echo "Input environment prepared"
}

# Run all initializations
main() {
    local stage="$1"
    
    case "$stage" in
        "init")
            echo "=== OCWS Setup: Initial Environment ==="
            init_shell
            init_config
            init_display
            init_theme
            init_audio
            init_input
            echo ""
            echo "Initialization complete!"
            echo ""
            echo "Next steps:"
            echo "  1. Start labwc: env WAYLAND_DISPLAY=wayland labwc"
            echo "  2. Apply a theme: ./scripts/theme-engine.sh apply ./themes/catppuccin-mocha.ini"
            echo "  3. Configure autostart: sudo systemctl enable labwc"
            ;;
        "minimal")
            echo "=== OCWS Setup: Minimal Environment ==="
            init_shell
            init_config
            echo "Minimal setup complete!"
            ;;
        "theme")
            echo "=== OCWS Setup: Theme Environment ==="
            init_shell
            init_config
            init_theme
            echo "Theme environment prepared!"
            ;;
        *)
            echo "Usage: ${0} [stage]"
            echo ""
            echo "Stages:"
            echo "  init          - Full initialization (recommended)"
            echo "  minimal       - Only essential files"
            echo "  theme         - Only theme configuration"
            echo ""
            echo "This script sets up the OCWS environment with:"
            echo "  ✓ Configuration files and scripts"
            echo "  ✓ Display and audio environment check"
            echo "  ✓ Theme preparation"
            echo "  ✓ Input device validation"
            ;;
    esac
}

main "$@"