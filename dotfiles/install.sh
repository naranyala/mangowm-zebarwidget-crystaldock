#!/bin/bash
#
# install.sh — Fresh system installer for labwc dotfiles
#
# Usage:
#   ./install.sh              Interactive install (with backup)
#   ./install.sh --help       Show help
#   ./install.sh --check      Validate only (no changes)
#   ./install.sh --no-backup  Skip backup
#   ./install.sh --force      Overwrite without prompts
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================================
# Colors & helpers
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
section() { echo -e "\n${BOLD}[$1]${NC}"; }

# ============================================================
# Parse arguments
# ============================================================

MODE="install"
SKIP_BACKUP=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo -e "${BOLD}labwc Dotfiles Installer${NC}"
      echo ""
      echo "Usage: ./install.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --help        Show this help"
      echo "  --check       Validate only (no changes)"
      echo "  --no-backup   Skip backup of existing configs"
      echo "  --force       Overwrite without prompts"
      echo ""
      echo "This installer sets up:"
      echo "  • labwc compositor config"
      echo "  • sfwbar statusbar + widgets"
      echo "  • GTK3/GTK4 theme"
      echo "  • Fuzzel app launcher"
      echo "  • Fontconfig + fonts"
      echo "  • Theme engine (11 themes)"
      echo "  • Screenshot tools"
      echo "  • All scripts to ~/.local/bin/"
      exit 0
      ;;
    --check)
      MODE="check"
      ;;
    --no-backup)
      SKIP_BACKUP=1
      ;;
    --force)
      FORCE=1
      ;;
    *)
      echo -e "${RED}Unknown option: $arg${NC}"
      echo "Run './install.sh --help' for usage"
      exit 1
      ;;
  esac
done

# ============================================================
# Directories
# ============================================================

LABWC_DST="$HOME/.config/labwc"
SFWBAR_DST="$HOME/.config/sfwbar"
GTK3_DIR="$HOME/.config/gtk-3.0"
GTK4_DIR="$HOME/.config/gtk-4.0"
FUZZEL_DST="$HOME/.config/fuzzel"
FONTCONFIG_DST="$HOME/.config/fontconfig"
SCRIPTS_DST="$HOME/.local/bin"
BACKUP_DIR="$HOME/.config/labwc-backups/$(date +%Y%m%d-%H%M%S)"

# ============================================================
# Banner
# ============================================================

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  labwc Dotfiles Installer${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo ""
if [[ "$MODE" == "check" ]]; then
  echo -e "  Mode: ${CYAN}validate only${NC} (no changes)"
elif [[ "$SKIP_BACKUP" -eq 1 ]]; then
  echo -e "  Mode: ${YELLOW}install (no backup)${NC}"
else
  echo -e "  Mode: ${GREEN}install (with backup)${NC}"
fi
echo ""

# ============================================================
# Pre-flight checks
# ============================================================

section "1. Pre-flight Checks"

ERRORS=0

# labwc
LABWC_BIN="$(command -v labwc 2>/dev/null || true)"
if [[ -n "$LABWC_BIN" ]]; then
  pass "labwc: $LABWC_BIN"
else
  warn "labwc not found"
  echo -e "    ${DIM}Install: sudo apt install labwc${NC}"
  echo -e "    ${DIM}Or build: ./download-labwc.sh --install${NC}"
  ((ERRORS++))
fi

# sfwbar
if command -v sfwbar &>/dev/null; then
  pass "sfwbar: $(command -v sfwbar)"
else
  warn "sfwbar not found (statusbar will need manual launch)"
fi

# Required tools
for tool in grim slurp wl-copy; do
  if command -v "$tool" &>/dev/null; then
    pass "$tool: $(command -v $tool)"
  else
    warn "$tool not found (screenshot/clipboard may not work)"
  fi
done

# Bash version check
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  fail "Bash 4+ required (current: ${BASH_VERSION})"
fi

if [[ "$MODE" == "check" ]]; then
  echo ""
  if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}All checks passed!${NC}"
  else
    echo -e "${YELLOW}${BOLD}$ERRORS issue(s) found${NC}"
  fi
  exit "$ERRORS"
fi

# ============================================================
# Backup existing configs
# ============================================================

if [[ "$SKIP_BACKUP" -eq 0 ]]; then
  section "2. Backup Existing Configs"

  BACKUP_ITEMS=(
    "$LABWC_DST"
    "$SFWBAR_DST"
    "$GTK3_DIR"
    "$GTK4_DIR"
    "$FUZZEL_DST"
    "$FONTCONFIG_DST"
  )

  HAS_BACKUP=0
  for item in "${BACKUP_ITEMS[@]}"; do
    if [[ -d "$item" ]]; then
      HAS_BACKUP=1
      break
    fi
  done

  if [[ $HAS_BACKUP -eq 1 ]]; then
    mkdir -p "$BACKUP_DIR"
    for item in "${BACKUP_ITEMS[@]}"; do
      if [[ -d "$item" ]]; then
        name=$(basename "$item")
        cp -r "$item" "$BACKUP_DIR/" 2>/dev/null && \
          pass "backed up $name" || true
      fi
    done
    echo -e "  ${DIM}Backup location: $BACKUP_DIR${NC}"
  else
    pass "No existing configs to backup"
  fi
else
  section "2. Backup (skipped)"
  info "Backup skipped (--no-backup)"
fi

# ============================================================
# Create directories
# ============================================================

section "3. Create Directories"

DIRS=(
  "$LABWC_DST"
  "$HOME/.config/labwc-widgets"
  "$SFWBAR_DST"
  "$GTK3_DIR"
  "$GTK4_DIR"
  "$FUZZEL_DST"
  "$FONTCONFIG_DST"
  "$SCRIPTS_DST"
  "$SCRIPTS_DST/actions"
  "$HOME/Pictures/screenshots"
  "$HOME/.local/share/fonts"
)

for dir in "${DIRS[@]}"; do
  mkdir -p "$dir"
  pass "$(echo "$dir" | sed "s|$HOME|~|")"
done

# ============================================================
# Install labwc config
# ============================================================

section "4. Labwc Config"

LABWC_SRC="$PROJECT_DIR/dotfiles/labwc"

# Validate rc.xml
if [[ -f "$LABWC_SRC/rc.xml" ]]; then
  CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$LABWC_SRC/rc.xml")
  if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
    fail "SOURCE rc.xml has broken Client context (Left Press)"
  fi
  pass "rc.xml validation passed"
fi

for cfg in rc.xml autostart environment menu.xml themerc-override startup-wallpaper.sh; do
  if [[ -f "$LABWC_SRC/$cfg" ]]; then
    cp "$LABWC_SRC/$cfg" "$LABWC_DST/$cfg"
    pass "$cfg"
  fi
done

chmod +x "$LABWC_DST/autostart" 2>/dev/null || true
chmod +x "$LABWC_DST/startup-wallpaper.sh" 2>/dev/null || true

# Presets
if [[ -d "$LABWC_SRC/presets" ]]; then
  mkdir -p "$LABWC_DST/presets"
  cp "$LABWC_SRC/presets/"* "$LABWC_DST/presets/" 2>/dev/null && \
    pass "presets/" || true
fi

# ============================================================
# Install sfwbar config
# ============================================================

section "5. SFWBar Config"

SFWBAR_SRC="$PROJECT_DIR/dotfiles/sfwbar"

if [[ -d "$SFWBAR_SRC" ]]; then
  # Copy all config, css, widget, and source files
  for f in "$SFWBAR_SRC"/*.config "$SFWBAR_SRC"/*.css "$SFWBAR_SRC"/*.widget "$SFWBAR_SRC"/*.source; do
    if [[ -f "$f" ]]; then
      cp "$f" "$SFWBAR_DST/"
      pass "$(basename "$f")"
    fi
  done
fi

# Copy default system sfwbar widgets if not already present
if [[ -d "$HOME/.local/share/sfwbar" ]]; then
  for f in "$HOME/.local/share/sfwbar"/*.widget "$HOME/.local/share/sfwbar"/*.source; do
    if [[ -f "$f" ]]; then
      name=$(basename "$f")
      if [[ ! -f "$SFWBAR_DST/$name" ]]; then
        cp "$f" "$SFWBAR_DST/$name"
        pass "$name (system default)"
      fi
    fi
  done
fi

# ============================================================
# Install noctalia config
# ============================================================

section "6. Noctalia Config"

NOCTALIA_SRC="$PROJECT_DIR/dotfiles/noctalia"
NOCTALIA_DST="$HOME/.config/noctalia"

if [[ -d "$NOCTALIA_SRC" ]]; then
  mkdir -p "$NOCTALIA_DST"
  for f in "$NOCTALIA_SRC"/*; do
    if [[ -f "$f" ]]; then
      cp "$f" "$NOCTALIA_DST/"
      pass "noctalia/$(basename "$f")"
    fi
  done
else
  info "No noctalia config found (skipped)"
fi

# ============================================================
# Install crystal-dock config
# ============================================================

section "7. Crystal Dock Config"

CRYSTAL_SRC="$PROJECT_DIR/dotfiles/crystal-dock"
CRYSTAL_DST="$HOME/.config/crystal-dock"

if [[ -d "$CRYSTAL_SRC/labwc" ]]; then
  mkdir -p "$CRYSTAL_DST"
  for cfg in panel_1.conf appearance.conf; do
    if [[ -f "$CRYSTAL_SRC/labwc/$cfg" ]]; then
      cp "$CRYSTAL_SRC/labwc/$cfg" "$CRYSTAL_DST/$cfg"
      pass "crystal-dock/$cfg"
    fi
  done
else
  info "No crystal-dock config found (skipped)"
fi

# ============================================================
# Install GTK theme
# ============================================================

section "8. GTK Theme"

GTK_SRC="$PROJECT_DIR/dotfiles/gtk"

for f in gtk3-settings.ini gtk4-settings.ini; do
  src="$GTK_SRC/$f"
  if [[ -f "$src" ]]; then
    if [[ "$f" == "gtk3-settings.ini" ]]; then
      cp "$src" "$GTK3_DIR/settings.ini"
      pass "GTK3 settings.ini"
    else
      cp "$src" "$GTK4_DIR/settings.ini"
      pass "GTK4 settings.ini"
    fi
  fi
done

if [[ -f "$GTK_SRC/gtk.css" ]]; then
  cp "$GTK_SRC/gtk.css" "$GTK3_DIR/gtk.css"
  cp "$GTK_SRC/gtk.css" "$GTK4_DIR/gtk.css"
  pass "gtk.css (GTK3 + GTK4)"
fi

# ============================================================
# Install fuzzel config
# ============================================================

section "9. Fuzzel Launcher"

FUZZEL_SRC="$PROJECT_DIR/dotfiles/fuzzel"

if [[ -d "$FUZZEL_SRC" ]]; then
  for f in "$FUZZEL_SRC"/*; do
    if [[ -f "$f" ]]; then
      cp "$f" "$FUZZEL_DST/"
      pass "fuzzel/$(basename "$f")"
    fi
  done
else
  info "No fuzzel config found (skipped)"
fi

# ============================================================
# Install fontconfig + fonts
# ============================================================

section "10. Fontconfig & Fonts"

FONTCONFIG_SRC="$PROJECT_DIR/dotfiles/fontconfig"

if [[ -d "$FONTCONFIG_SRC" ]]; then
  for f in "$FONTCONFIG_SRC"/*; do
    if [[ -f "$f" ]]; then
      cp "$f" "$FONTCONFIG_DST/"
      pass "fontconfig/$(basename "$f")"
    fi
  done
fi

# Install fonts
FONTS_SCRIPT="$PROJECT_DIR/scripts/install-fonts.sh"
if [[ -x "$FONTS_SCRIPT" ]]; then
  info "Installing fonts..."
  bash "$FONTS_SCRIPT" 2>&1 | sed 's/^/    /' || warn "Font installation had issues"
else
  warn "install-fonts.sh not found"
fi

# ============================================================
# Install scripts
# ============================================================

section "11. Scripts"

# Install main scripts
SCRIPTS_SRC="$PROJECT_DIR/scripts"
for f in "$SCRIPTS_SRC"/*.sh; do
  if [[ -f "$f" ]]; then
    name=$(basename "$f")
    cp "$f" "$SCRIPTS_DST/$name"
    chmod +x "$SCRIPTS_DST/$name"
    pass "$name"
  fi
done

# Install action scripts
if [[ -d "$SCRIPTS_SRC/actions" ]]; then
  for f in "$SCRIPTS_SRC/actions"/*.sh; do
    if [[ -f "$f" ]]; then
      name=$(basename "$f")
      cp "$f" "$SCRIPTS_DST/actions/$name"
      chmod +x "$SCRIPTS_DST/actions/$name"
      pass "actions/$name"
    fi
  done
fi

# Install wallpaper script
WALLPAPER_SRC="$PROJECT_DIR/dotfiles/wallpaper"
if [[ -f "$WALLPAPER_SRC" ]]; then
  cp "$WALLPAPER_SRC" "$SCRIPTS_DST/wallpaper"
  chmod +x "$SCRIPTS_DST/wallpaper"
  pass "wallpaper"
fi

# Install wallpaper sources
if [[ -f "$PROJECT_DIR/dotfiles/wallpaper-sources.txt" ]]; then
  cp "$PROJECT_DIR/dotfiles/wallpaper-sources.txt" "$SCRIPTS_DST/wallpaper-sources.txt"
  pass "wallpaper-sources.txt"
fi

# ============================================================
# Update PATH
# ============================================================

section "12. PATH"

PROFILE=""
for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
  if [[ -f "$f" ]]; then
    PROFILE="$f"
    break
  fi
done

if [[ -n "$PROFILE" ]]; then
  if ! grep -q '\.local/bin' "$PROFILE" 2>/dev/null; then
    echo '' >> "$PROFILE"
    echo '# labwc - add local bin to PATH' >> "$PROFILE"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE"
    pass "PATH updated in $(basename "$PROFILE")"
  else
    pass "PATH already configured"
  fi
fi

# ============================================================
# Create session file
# ============================================================

section "13. Session File"

SESSION_DIR="/usr/share/wayland-sessions"
if [[ -d "$SESSION_DIR" ]]; then
  cat > /tmp/labwc.desktop << 'EOF'
[Desktop Entry]
Name=labwc
Comment=Lab Wayland Compositor
Exec=labwc
TryExec=labwc
Type=Application
DesktopNames=labwc;
Keywords=wayland;compositor;labwc;
X-GDM-SessionRegisters=true
X-GDM-CanRunHeadless=true
EOF
  sudo cp /tmp/labwc.desktop "$SESSION_DIR/labwc.desktop" 2>/dev/null && \
    sudo chmod 644 "$SESSION_DIR/labwc.desktop" && \
    pass "labwc.desktop" || warn "Could not create session file (need sudo)"
  rm -f /tmp/labwc.desktop
else
  info "Session directory not found (skipped)"
fi

# ============================================================
# Apply default theme
# ============================================================

section "14. Apply Theme"

THEME_SCRIPT="$SCRIPTS_DST/theme"
if [[ -x "$THEME_SCRIPT" ]]; then
  info "Applying catppuccin-mocha theme..."
  bash "$THEME_SCRIPT" catppuccin-mocha 2>&1 | sed 's/^/    /' || warn "Theme application had issues"
else
  warn "theme script not found — run manually: theme catppuccin-mocha"
fi

# ============================================================
# Validation
# ============================================================

section "15. Validation"

ERRORS=0

# Check critical files
CHECKS=(
  "$LABWC_DST/rc.xml:labwc rc.xml"
  "$LABWC_DST/autostart:labwc autostart"
  "$LABWC_DST/environment:labwc environment"
  "$SFWBAR_DST/sfwbar.config:sfwbar config"
  "$GTK3_DIR/settings.ini:GTK3 settings"
  "$GTK4_DIR/settings.ini:GTK4 settings"
  "$GTK3_DIR/gtk.css:GTK3 CSS"
  "$FUZZEL_DST/fuzzel.ini:fuzzel config"
  "$FONTCONFIG_DST/fonts.conf:fontconfig"
)

for check in "${CHECKS[@]}"; do
  file="${check%%:*}"
  label="${check##*:}"
  if [[ -f "$file" ]]; then
    pass "$label"
  else
    warn "$label: missing"
    ((ERRORS++))
  fi
done

# Check scripts
for script in theme.sh validate.sh fix.sh start-labwc.sh font-scale.sh; do
  if [[ -f "$SCRIPTS_DST/$script" ]]; then
    pass "script: $script"
  else
    warn "missing: $script"
    ((ERRORS++))
  fi
done

# Check fonts
if fc-list 2>/dev/null | grep -qi "noto sans"; then
  pass "fonts: Noto Sans"
else
  warn "fonts: Noto Sans not found"
fi

# ============================================================
# Summary
# ============================================================

section "Done"

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}Installation complete!${NC}"
else
  echo -e "${YELLOW}${BOLD}Installation complete with $ERRORS warning(s)${NC}"
fi

echo ""
echo -e "${BOLD}Installed:${NC}"
echo "  labwc config     → ~/.config/labwc/"
echo "  sfwbar config    → ~/.config/sfwbar/"
echo "  GTK3/GTK4        → ~/.config/gtk-{3,4}.0/"
echo "  fuzzel           → ~/.config/fuzzel/"
echo "  fontconfig       → ~/.config/fontconfig/"
echo "  scripts          → ~/.local/bin/"
echo "  actions          → ~/.local/bin/actions/"
echo ""

if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
  echo -e "${BOLD}Backup:${NC} $BACKUP_DIR"
  echo ""
fi

echo -e "${BOLD}Quick start:${NC}"
echo "  theme                   # List themes"
echo "  theme nord              # Switch theme"
echo "  theme next              # Cycle themes"
echo "  relaunch-status-bars    # Restart bar + dock"
echo "  validate                # Check setup"
echo "  fix                     # Auto-fix issues"
echo ""
echo -e "${BOLD}Launch labwc:${NC}"
echo "  From TTY:  start-labwc"
echo "  From DM:   Select 'labwc' session"
echo ""
