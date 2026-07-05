#!/bin/bash
# -------------------------------------------------------------------
# OCWS Installer
# Enhanced distribution-aware installer for OCWS ecosystem.
# For comprehensive distro-specific installation, use ./install-distribution.sh
# -------------------------------------------------------------------

set -euo pipefail

# Default installation mode: 'labwc-dms' (labwc + Dank Material Shell)
# Available modes:
#   labwc-dms : Core labwc + OCWS shell (recommended)
#   full      : Includes legacy shells (Noctalia, Crystal Dock)
MODE="labwc-dms"

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --mode=*)
            MODE="${arg#*=}"
            ;;
    esac
done

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "\n${CYAN}==>${NC} $*"; }
pass() { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info "Initializing OCWS Deployment..."

# 1. Check for comprehensive distro-specific installer
if [ -f "${SCRIPT_DIR}/install-distribution.sh" ]; then
    echo -e "\n  ${GREEN}✓${NC} Enhanced distro-specific installer found."
    echo -e "  ${CYAN}=== OCWS Installer ===${NC}"
    echo -e "  ${CYAN}  Quick Mode:${NC} All manual config steps"
    echo -e "  ${CYAN}  Full Mode:${NC}  Automatic package installation"
    echo -e "\n  Choose option:"
    echo -e "    1) Quick Install (manual dependency setup)"
    echo -e "    2) Full Install (automatic distro detection and package installation)"
    echo -e "\n  Default: 1 (Quick Install)"
    echo -n "    Enter choice [1-2]: "
    
    read -r choice
    
    case "${choice:-1}" in
        2)
            echo -e "\n${CYAN}==>${NC} Starting comprehensive distribution installer..."
            bash "${SCRIPT_DIR}/install-distribution.sh" "$@"
            ;;
        *)
            echo -e "\n${CYAN}==>${NC} Starting quick installer..."
            ;;
    esac
fi

# -------------------------------------------------------------------
# Legacy Quick Installer
# Manual dependency installation and configuration deployment
# -------------------------------------------------------------------

# 1. Dependency Check
info "Checking for required dependencies..."
if ! command -v labwc >/dev/null 2>&1 || ! command -v sfwbar >/dev/null 2>&1 || ! command -v fuzzel >/dev/null 2>&1; then
    echo -e "\n${YELLOW}⚠${NC} Core engines (labwc, sfwbar, fuzzel) are missing!"
    echo -e "  ${RED}Options:${NC}"
    echo -e "    1) Install via package manager (${SCRIPT_DIR}/install-distribution.sh)"
    echo -e "    2) Build from source (${SCRIPT_DIR}/build-ocws-core.sh all)"
    echo -e "\n  Press [ENTER] to continue anyway, or Ctrl+C to cancel."
    read -r
fi

if [[ "$MODE" == "labwc-dms" ]] && ! command -v dms >/dev/null 2>&1; then
    echo -e "\n${YELLOW}⚠${NC} Dank Material Shell (dms) is missing!"
    echo -e "  You will need to install it manually for this mode to work correctly."
    echo -e "\n  Press [ENTER] to continue anyway, or Ctrl+C to cancel."
    read -r
fi

# 1.5 Confirmation Prompt
echo -e "\n${YELLOW}⚠ WARNING: This will deploy configurations to ~/.config/ and ~/.local/bin/${NC}"
if [[ "$MODE" == "labwc-dms" ]]; then
    echo -e "  Mode: ${CYAN}labwc + dms (Dank Material Shell)${NC}"
    echo -e "  Affected directories: labwc, ocws, fuzzel, foot, gtk-3.0, gtk-4.0, rofi, mako, qt6ct, zebar"
else
    echo -e "  Mode: ${CYAN}full${NC}"
    echo -e "  Affected directories: labwc, ocws, fuzzel, foot, gtk-3.0, gtk-4.0, rofi, mako, qt6ct, zebar, crystal-dock, noctalia"
fi
echo -n "  Are you sure you want to proceed? [y/N]: "
read -r confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\n  Installation aborted."
    exit 0
fi

# 2. Setup Directories
info "Setting up configuration directories..."
mkdir -p ~/.config/labwc
mkdir -p ~/.config/ocws/plugins
mkdir -p ~/.config/fuzzel
mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
mkdir -p ~/.local/bin/actions
pass "Directories created."

# 3. Deploy Labwc Core
info "Deploying Compositor Rules (labwc)..."
cp -r "$SCRIPT_DIR/dotfiles/labwc/"* ~/.config/labwc/ 2>/dev/null || fail "Failed to deploy labwc configurations"
pass "labwc configurations synced."

# 4. Deploy OCWS Shell
info "Deploying the OCWS Shell..."
# Exclude user.config — it's the user's personal overlay, never overwritten
rsync -a --exclude='user.config' "$SCRIPT_DIR/dotfiles/ocws/" ~/.config/ocws/ 2>/dev/null || cp -r "$SCRIPT_DIR/dotfiles/ocws/"* ~/.config/ocws/ 2>/dev/null || fail "Failed to deploy OCWS shell"

if [ ! -f ~/.config/ocws/user.config ]; then
    cp "$SCRIPT_DIR/dotfiles/ocws/user.config" ~/.config/ocws/user.config 2>/dev/null || true
fi

# Record the installed mode in system configuration
echo "$MODE" > ~/.config/ocws/mode
pass "OCWS layout, plugins, and mode ($MODE) synced."

# 5. Deploy Fuzzel Launcher
if [ -d "$SCRIPT_DIR/dotfiles/fuzzel" ]; then
    info "Deploying Application Launcher (fuzzel)..."
    cp -r "$SCRIPT_DIR/dotfiles/fuzzel/"* ~/.config/fuzzel/ 2>/dev/null || fail "Failed to deploy fuzzel configuration"
    pass "Fuzzel synced."
fi

# Deploy Foot Terminal
if [ -d "$SCRIPT_DIR/dotfiles/foot" ]; then
    info "Deploying Foot Terminal configuration..."
    mkdir -p ~/.config/foot
    cp -r "$SCRIPT_DIR/dotfiles/foot/"* ~/.config/foot/ 2>/dev/null || true
    pass "Foot synced."
fi

# 6. Deploy GTK Styling
if [ -d "$SCRIPT_DIR/dotfiles/gtk-3.0" ] || [ -d "$SCRIPT_DIR/dotfiles/gtk-4.0" ] || [ -d "$SCRIPT_DIR/dotfiles/gtk" ]; then
    info "Deploying GTK Preferences..."
    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    [ -d "$SCRIPT_DIR/dotfiles/gtk" ] && cp -r "$SCRIPT_DIR/dotfiles/gtk/"* ~/.config/gtk-3.0/ 2>/dev/null || true
    [ -d "$SCRIPT_DIR/dotfiles/gtk" ] && cp -r "$SCRIPT_DIR/dotfiles/gtk/"* ~/.config/gtk-4.0/ 2>/dev/null || true
    [ -d "$SCRIPT_DIR/dotfiles/gtk-3.0" ] && cp -r "$SCRIPT_DIR/dotfiles/gtk-3.0/"* ~/.config/gtk-3.0/ 2>/dev/null || true
    [ -d "$SCRIPT_DIR/dotfiles/gtk-4.0" ] && cp -r "$SCRIPT_DIR/dotfiles/gtk-4.0/"* ~/.config/gtk-4.0/ 2>/dev/null || true
    pass "GTK settings synced."
fi

# Deploy Rofi
if [ -d "$SCRIPT_DIR/dotfiles/rofi" ]; then
    info "Deploying Rofi configuration..."
    mkdir -p ~/.config/rofi
    cp -r "$SCRIPT_DIR/dotfiles/rofi/"* ~/.config/rofi/ 2>/dev/null || true
    pass "Rofi synced."
fi

# Deploy Mako
if [ -d "$SCRIPT_DIR/dotfiles/mako" ]; then
    info "Deploying Mako configuration..."
    mkdir -p ~/.config/mako
    cp -r "$SCRIPT_DIR/dotfiles/mako/"* ~/.config/mako/ 2>/dev/null || true
    pass "Mako synced."
fi

# Deploy qt6ct
if [ -d "$SCRIPT_DIR/dotfiles/qt6ct" ]; then
    info "Deploying Qt6ct configuration..."
    mkdir -p ~/.config/qt6ct
    cp -r "$SCRIPT_DIR/dotfiles/qt6ct/"* ~/.config/qt6ct/ 2>/dev/null || true
    pass "Qt6ct synced."
fi

# Deploy crystal-dock
if [[ "$MODE" == "full" ]] && [ -d "$SCRIPT_DIR/dotfiles/crystal-dock" ]; then
    info "Deploying crystal-dock configuration..."
    rsync -a "$SCRIPT_DIR/dotfiles/crystal-dock/" ~/.config/crystal-dock/ 2>/dev/null || true
    pass "crystal-dock config synced."
fi

# Deploy noctalia
if [[ "$MODE" == "full" ]] && [ -d "$SCRIPT_DIR/dotfiles/noctalia" ]; then
    info "Deploying noctalia configuration..."
    mkdir -p ~/.config/noctalia
    rsync -a "$SCRIPT_DIR/dotfiles/noctalia/" ~/.config/noctalia/ 2>/dev/null || true
    pass "noctalia config synced."
fi

# Deploy DankMaterialShell
if [ -d "$SCRIPT_DIR/dotfiles/DankMaterialShell" ]; then
    info "Deploying Dank Material Shell configuration..."
    mkdir -p ~/.config/DankMaterialShell
    rsync -a "$SCRIPT_DIR/dotfiles/DankMaterialShell/" ~/.config/DankMaterialShell/ 2>/dev/null || true
    pass "Dank Material Shell config synced."
fi

# Deploy Zebar
if [ -d "$SCRIPT_DIR/dotfiles/.glzr/zebar" ]; then
    info "Deploying Zebar configuration..."
    mkdir -p ~/.glzr/zebar
    cp -r "$SCRIPT_DIR/dotfiles/.glzr/zebar/"* ~/.glzr/zebar/ 2>/dev/null || true
    pass "Zebar synced."
fi

# 7. Deploy IPC & Core Tools
info "Deploying Event Bus API & System Tools..."
find "$SCRIPT_DIR/scripts" -maxdepth 1 -type f -name "*.sh" -exec cp {} ~/.local/bin/ \; 2>/dev/null || fail "Failed to deploy scripts"
if [ -d "$SCRIPT_DIR/scripts/actions" ]; then
    cp "$SCRIPT_DIR/scripts/actions/"* ~/.local/bin/actions/ 2>/dev/null || true
fi
chmod +x ~/.local/bin/*.sh 2>/dev/null || fail "Failed to set execute permissions on scripts"
chmod +x ~/.local/bin/actions/* 2>/dev/null || true
pass "Scripts and IPC mapped to ~/.local/bin"

# 7b. Deploy dotfiles/wallpaper script
if [ -f "$SCRIPT_DIR/dotfiles/wallpaper" ]; then
    cp "$SCRIPT_DIR/dotfiles/wallpaper" ~/.local/bin/wallpaper
    chmod +x ~/.local/bin/wallpaper
    pass "wallpaper command installed to ~/.local/bin/wallpaper"
fi

# 7c. Deploy wallpaper sources list
if [ -f "$SCRIPT_DIR/dotfiles/wallpaper-sources.txt" ]; then
    cp "$SCRIPT_DIR/dotfiles/wallpaper-sources.txt" ~/.config/ocws/wallpaper-sources.txt
    pass "wallpaper-sources.txt deployed to ~/.config/ocws/"
fi

# 8. Strict Installation Validation
info "Performing strict validation of deployed assets..."

validate_file() {
    local target="$1"
    if [ ! -e "$target" ]; then
        echo -e "  ${RED}✗${NC} Missing deployed asset: $target"
        return 1
    fi
    return 0
}

validate_executable() {
    local target="$1"
    if [ ! -x "$target" ]; then
        echo -e "  ${RED}✗${NC} Missing execute permissions: $target"
        return 1
    fi
    return 0
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $*"
}

validate_file_format() {
    local target="$1"
    local format="$2"
    
    case "$format" in
        xml)
            if ! command -v xmllint >/dev/null 2>&1; then
                warn "xmllint not available for XML validation of $target"
                return 0
            fi
            if ! xmllint --noout "$target" 2>/dev/null; then
                echo -e "  ${RED}✗${NC} Invalid XML format: $target"
                return 1
            fi
            ;;
        ini)
            if ! command -v crudini >/dev/null 2>&1; then
                warn "crudini not available for INI validation of $target"
                return 0
            fi
            crudini --get "$target" >/dev/null 2>&1 || {
                echo -e "  ${RED}✗${NC} Invalid INI format: $target"
                return 1
            }
            ;;
        css)
            if ! command -v csslint >/dev/null 2>&1; then
                warn "csslint not available for CSS validation of $target"
                return 0
            fi
            csslint "$target" >/dev/null 2>&1 || {
                echo -e "  ${RED}✗${NC} Invalid CSS format: $target"
                return 1
            }
            ;;
        shell)
            bash -n "$target" 2>/dev/null || {
                echo -e "  ${RED}✗${NC} Invalid shell syntax: $target"
                return 1
            }
            ;;
    esac
    pass "Valid $format format: $target"
    return 0
}

validate_content() {
    local target="$1"
    local check_type="$2"
    
    case "$check_type" in
        rcxml)
            if ! grep -q "<labwc_config>" "$target"; then
                echo -e "  ${RED}✗${NC} Missing root element in rc.xml"
                return 1
            fi
            if ! grep -q "<keyboard>" "$target" || ! grep -q "</keyboard>" "$target"; then
                echo -e "  ${RED}✗${NC} Missing keyboard section in rc.xml"
                return 1
            fi
            ;;
        menu)
            if ! grep "<menu" "$target" | grep -q "/>"; then
                echo -e "  ${RED}✗${NC} Missing root menu element in menu.xml"
                return 1
            fi
            ;;
        ocwsconfig)
            if ! grep -q "^bar\|widget" "$target"; then
                echo -e "  ${RED}✗${NC} Missing bar definition in ocws.config"
                return 1
            fi
            ;;
        fuzzelini)
            if ! grep -q "^\[main\]" "$target"; then
                echo -e "  ${RED}✗${NC} Missing [main] section in fuzzel.ini"
                return 1
            fi
            ;;
        scripts)
            # Check for essential shebang
            if [[ "$target" == *.sh ]]; then
                if ! head -1 "$target" | grep -q "^#!/bin/bash"; then
                    echo -e "  ${YELLOW}⚠${NC} Missing bash shebang in $target"
                fi
            fi
            ;;
    esac
    pass "Content validation passed: $target ($check_type)"
    return 0
}

validate_required_functions() {
    local script="$1"
    
    if [[ "$script" == *.sh ]]; then
        # Check for essential functions
        if ! grep -q "^info()" "$script" && ! grep -q "^error()" "$script"; then
            echo -e "  ${YELLOW}⚠${NC} Script $script may lack error handling functions"
        fi
        
        # Check for file existence checks
        if ! grep -q "\[ ! -f\]\|\[-d " "$script"; then
            echo -e "  ${YELLOW}⚠${NC} Script $script may lack file validation"
        fi
    fi
    pass "Required functions present in $script"
    return 0
}

validate_keybinding_integrity() {
    local rc_file="$HOME/.config/labwc/rc.xml"
    
    if [ ! -f "$rc_file" ]; then
        echo -e "  ${YELLOW}⚠${NC} rc.xml not found for keybinding validation"
        return 0
    fi
    
    # Check for duplicate keybindings
    local duplicates=$(sed -n 's/.*key="\([^"]*\)".*/\1/p' "$rc_file" | sort | uniq -d)
    if [ -n "$duplicates" ]; then
        echo -e "  ${RED}✗${NC} Duplicate keybindings found: $duplicates"
        return 1
    fi
    
    # Check for essential keybindings
    local essential_keys=(A-Return A-Alt-Tab A-ESC A-S-ESC A-F4 S-F4)
    for key in "${essential_keys[@]}"; do
        if ! grep -q "key=\"$key\"" "$rc_file"; then
            echo -e "  ${YELLOW}⚠${NC} Missing essential keybinding: $key"
        fi
    done
    
    pass "Keybinding integrity validated"
    return 0
}

ERRORS=0

# Verify Labwc
validate_file "$HOME/.config/labwc/rc.xml" || ((ERRORS++))
validate_file "$HOME/.config/labwc/autostart" || ((ERRORS++))
validate_file "$HOME/.config/labwc/menu.xml" || ((ERRORS++))

# Verify OCWS
validate_file "$HOME/.config/ocws/ocws.config" || ((ERRORS++))

# Verify Fuzzel
if [ -d "$SCRIPT_DIR/dotfiles/fuzzel" ]; then
    validate_file "$HOME/.config/fuzzel/fuzzel.ini" || ((ERRORS++))
fi

# Verify Scripts
for script in "$SCRIPT_DIR/scripts/"*.sh; do
    [ -e "$script" ] || continue
    base=$(basename "$script")
    validate_file "$HOME/.local/bin/$base" || ((ERRORS++))
    validate_executable "$HOME/.local/bin/$base" || ((ERRORS++))
    validate_required_functions "$HOME/.local/bin/$base"
    validate_file_format "$HOME/.local/bin/$base" shell
    validate_content "$HOME/.local/bin/$base" scripts
    done

# Verify Dotfile Formats
validate_file_format "$HOME/.config/labwc/rc.xml" xml
validate_file_format "$HOME/.config/labwc/menu.xml" xml

if [ -f "$HOME/.config/ocws/ocws.config" ]; then
    validate_content "$HOME/.config/ocws/ocws.config" ocwsconfig
fi

if [ -f "$HOME/.config/fuzzel/fuzzel.ini" ]; then
    validate_file_format "$HOME/.config/fuzzel/fuzzel.ini" ini
    validate_content "$HOME/.config/fuzzel/fuzzel.ini" fuzzelini
fi

# Validate Labwc content
validate_content "$HOME/.config/labwc/rc.xml" rcxml
validate_content "$HOME/.config/labwc/menu.xml" menu

# Validate keybinding integrity
validate_keybinding_integrity

if [ "$ERRORS" -gt 0 ]; then
    fail "Comprehensive validation failed with $ERRORS errors. Installation is incomplete."
else
    pass "All configuration files strictly validated with format, content, and integrity checks."
fi

# 9. Success
info "OCWS Deployment Complete! 🚀"
echo -e "\n${CYAN}=== Quick Install Complete ===${NC}"
echo -e "  Installed Mode: ${GREEN}$MODE${NC}"
echo -e "${CYAN}  Note:${NC} You must manually install labwc, sfwbar, and fuzzel first."
echo -e "  Use ./install-distribution.sh for automatic distro detection and installation."
echo -e "\n${CYAN}  Next Steps:${NC}"
echo -e "  • Install dependencies using: ./install-distribution.sh (Recommended)"
echo -e "  • Build from source: ./build-ocws-core.sh all"
echo -e "  • Restart and select 'labwc' from display manager"
echo -e "  • Or run: labwc (from a TTY)"
