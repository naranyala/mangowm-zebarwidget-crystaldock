#!/bin/bash
#
# reconfigure.sh — Interactive CLI for dotfiles reinstall/reconfigure
#
# Presents a menu-driven interface to:
#   - Reinstall individual components (with backup)
#   - Manage themes, fonts, downloads
#   - Backup/restore configuration
#   - Validate and fix setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_DIR="${HOME}/.config/labwc"
GTK3_DIR="${HOME}/.config/gtk-3.0"
GTK4_DIR="${HOME}/.config/gtk-4.0"
ZEBAR_V1="${HOME}/.config/zebar"
ZEBAR_V3="${HOME}/.glzr/zebar"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }

# ============================================================
# Status helpers
# ============================================================

running() { pgrep -x "$1" &>/dev/null; }

check_mark() {
  if [[ -f "$1" ]]; then
    echo -e "  ${GREEN}installed${NC}"
  else
    echo -e "  ${DIM}missing${NC}"
  fi
}

# ============================================================
# Backup wrapper
# ============================================================

do_backup() {
  local label="${1:-pre-change}"
  info "Creating backup ($label) ..."
  bash "$SCRIPT_DIR/backup.sh" && pass "Backup created" || warn "Backup failed"
}

# ============================================================
# Menus
# ============================================================

show_header() {
  clear
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║       labwc Dotfiles — Reconfigure CLI       ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo
}

show_status_bar() {
  local lw="stopped" dk="stopped" zb="stopped"
  running labwc && lw="running"
  running crystal-dock && dk="running"
  running zebar && zb="running"

  local theme
  theme=$(grep -oP '(?<=<name>).*(?=</name>)' "$CONFIG_DIR/rc.xml" 2>/dev/null | head -1)
  [ -z "$theme" ] && theme="default"

  echo -e " ${DIM}labwc:${NC} ${lw}  ${DIM}crystal-dock:${NC} ${dk}  ${DIM}zebar:${NC} ${zb}"
  local backup_count
  backup_count=$(ls -1 "$HOME/.config/labwc-backups"/*.tar.gz 2>/dev/null | wc -l || echo 0)
  echo -e " ${DIM}Theme:${NC} ${theme}  ${DIM}Backups:${NC} ${backup_count}"
  echo
}

menu_main() {
  while true; do
    show_header
    show_status_bar

    echo -e " ${BOLD}Main Menu${NC}"
    echo
    echo "  1)  Full reinstall (with backup)"
    echo "  2)  Reconfigure labwc config"
    echo "  3)  Reconfigure GTK theme config"
    echo "  4)  Reconfigure zebar widgets"
    echo "  5)  Reinstall scripts"
    echo "  6)  Theme management"
    echo "  7)  Font management"
    echo "  8)  Download themes & fonts"
    echo "  9)  Backup & Restore"
    echo "  10) Validate & Fix"
    echo "  0)  Exit"
    echo
    read -rp "  Select [0-10]: " choice

    case "$choice" in
      1) menu_full_reinstall ;;
      2) menu_labwc_config ;;
      3) menu_gtk_config ;;
      4) menu_zebar ;;
      5) menu_scripts ;;
      6) menu_themes ;;
      7) menu_fonts ;;
      8) menu_downloads ;;
      9) menu_backup ;;
      10) menu_validate ;;
      0) echo; pass "Goodbye"; exit 0 ;;
      *) warn "Invalid choice"; sleep 1 ;;
    esac
  done
}

menu_full_reinstall() {
  show_header
  echo -e " ${BOLD}Full Reinstall${NC}"
  echo
  warn "This will reinstall ALL dotfiles components."
  echo "  A backup will be created first."
  echo
  read -rp "  Proceed? [y/N] " ans
  [[ ! "$ans" =~ ^[Yy] ]] && return

  do_backup "full-reinstall"
  bash "$SCRIPT_DIR/../dotfiles/install.sh"
  echo
  read -rp "  Press Enter to continue ... "
}

menu_labwc_config() {
  while true; do
    show_header
    echo -e " ${BOLD}labwc Config${NC}"
    echo
    echo "  Current status:"
    echo "    rc.xml          $(check_mark "$CONFIG_DIR/rc.xml")"
    echo "    autostart       $(check_mark "$CONFIG_DIR/autostart")"
    echo "    environment     $(check_mark "$CONFIG_DIR/environment")"
    echo "    menu.xml        $(check_mark "$CONFIG_DIR/menu.xml")"
    echo "    themerc-override $(check_mark "$CONFIG_DIR/themerc-override")"
    echo
    echo "  1)  Install all labwc config"
    echo "  2)  Install rc.xml (with backup)"
    echo "  3)  Install autostart (with backup)"
    echo "  4)  Install environment"
    echo "  5)  Install menu.xml"
    echo "  6)  Install themerc-override (with backup)"
    echo "  7)  Edit rc.xml"
    echo "  8)  Edit autostart"
    echo "  9)  Reload labwc config"
    echo "  0)  Back to main menu"
    echo
    read -rp "  Select [0-9]: " choice

    case "$choice" in
      1)
        do_backup "labwc-config"
        mkdir -p "$CONFIG_DIR"
        for f in rc.xml autostart environment menu.xml themerc-override; do
          if [[ -f "$PROJECT_DIR/dotfiles/labwc/$f" ]]; then
            cp "$PROJECT_DIR/dotfiles/labwc/$f" "$CONFIG_DIR/$f" && pass "$f"
          else
            warn "source not found: dotfiles/labwc/$f"
          fi
        done
        chmod +x "$CONFIG_DIR/autostart" 2>/dev/null || true
        running labwc && labwc --reconfigure 2>/dev/null && pass "labwc reloaded"
        ;;
      2)
        if [[ -f "$PROJECT_DIR/dotfiles/labwc/rc.xml" ]]; then
          CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$PROJECT_DIR/dotfiles/labwc/rc.xml")
          if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
            warn "Source rc.xml has broken Client context (Left Press) — skipping install"
          else
            do_backup "rc.xml"
            cp "$PROJECT_DIR/dotfiles/labwc/rc.xml" "$CONFIG_DIR/rc.xml"
            pass "rc.xml installed"
            running labwc && labwc --reconfigure 2>/dev/null
          fi
        else
          warn "source not found: dotfiles/labwc/rc.xml"
        fi
        ;;
      3)
        if [[ -f "$PROJECT_DIR/dotfiles/labwc/autostart" ]]; then
          do_backup "autostart"
          cp "$PROJECT_DIR/dotfiles/labwc/autostart" "$CONFIG_DIR/autostart"
          chmod +x "$CONFIG_DIR/autostart"
          pass "autostart installed"
        else
          warn "source not found: dotfiles/labwc/autostart"
        fi
        ;;
      4) [[ -f "$PROJECT_DIR/dotfiles/labwc/environment" ]] && cp "$PROJECT_DIR/dotfiles/labwc/environment" "$CONFIG_DIR/environment" && pass "environment installed" || warn "source not found: dotfiles/labwc/environment" ;;
      5) [[ -f "$PROJECT_DIR/dotfiles/labwc/menu.xml" ]] && cp "$PROJECT_DIR/dotfiles/labwc/menu.xml" "$CONFIG_DIR/menu.xml" && pass "menu.xml installed" || warn "source not found: dotfiles/labwc/menu.xml" ;;
      6)
        if [[ -f "$PROJECT_DIR/dotfiles/labwc/themerc-override" ]]; then
          do_backup "themerc-override"
          cp "$PROJECT_DIR/dotfiles/labwc/themerc-override" "$CONFIG_DIR/themerc-override"
          pass "themerc-override installed"
          running labwc && labwc --reconfigure 2>/dev/null
        else
          warn "source not found: dotfiles/labwc/themerc-override"
        fi
        ;;
      7) ${EDITOR:-nano} "$CONFIG_DIR/rc.xml"; running labwc && labwc --reconfigure 2>/dev/null ;;
      8) ${EDITOR:-nano} "$CONFIG_DIR/autostart" ;;
      9)
        if running labwc; then
          if labwc --reconfigure 2>/dev/null; then
            pass "labwc reloaded"
          else
            warn "labwc reconfigure failed"
          fi
        else
          warn "labwc not running"
        fi
        ;;
      0) return ;;
      *) warn "Invalid choice"; sleep 1 ;;
    esac
    [[ "$choice" != 0 ]] && { echo; read -rp "  Press Enter to continue ... "; }
  done
}

menu_gtk_config() {
  while true; do
    show_header
    echo -e " ${BOLD}GTK Theme Config${NC}"
    echo
    echo "  Current status:"
    echo "    GTK3 settings.ini $(check_mark "$GTK3_DIR/settings.ini")"
    echo "    GTK4 settings.ini $(check_mark "$GTK4_DIR/settings.ini")"
    echo "    GTK3 gtk.css     $(check_mark "$GTK3_DIR/gtk.css")"
    echo "    GTK4 gtk.css     $(check_mark "$GTK4_DIR/gtk.css")"
    echo
    local g3=$(grep -oP '(?<=^gtk-theme-name=).*' "$GTK3_DIR/settings.ini" 2>/dev/null || echo "unset")
    local g4=$(grep -oP '(?<=^gtk-theme-name=).*' "$GTK4_DIR/settings.ini" 2>/dev/null || echo "unset")
    echo "    GTK3 theme: ${g3}"
    echo "    GTK4 theme: ${g4}"
    echo
    echo "  1)  Install all GTK config (with backup)"
    echo "  2)  Install GTK3 settings.ini"
    echo "  3)  Install GTK4 settings.ini"
    echo "  4)  Install gtk.css overrides"
    echo "  5)  Edit gtk.css"
    echo "  6)  Set GTK3 + GTK4 theme"
    echo "  0)  Back to main menu"
    echo
    read -rp "  Select [0-6]: " choice

    case "$choice" in
      1)
        do_backup "gtk-config"
        mkdir -p "$GTK3_DIR" "$GTK4_DIR"
        cp "$PROJECT_DIR/dotfiles/gtk/gtk3-settings.ini" "$GTK3_DIR/settings.ini"
        cp "$PROJECT_DIR/dotfiles/gtk/gtk4-settings.ini" "$GTK4_DIR/settings.ini"
        cp "$PROJECT_DIR/dotfiles/gtk/gtk.css" "$GTK3_DIR/gtk.css"
        cp "$PROJECT_DIR/dotfiles/gtk/gtk.css" "$GTK4_DIR/gtk.css"
        pass "All GTK config installed"
        ;;
      2)
        mkdir -p "$GTK3_DIR"
        cp "$PROJECT_DIR/dotfiles/gtk/gtk3-settings.ini" "$GTK3_DIR/settings.ini"
        pass "GTK3 settings.ini installed"
        ;;
      3)
        mkdir -p "$GTK4_DIR"
        cp "$PROJECT_DIR/dotfiles/gtk/gtk4-settings.ini" "$GTK4_DIR/settings.ini"
        pass "GTK4 settings.ini installed"
        ;;
      4)
        mkdir -p "$GTK3_DIR" "$GTK4_DIR"
        cp "$PROJECT_DIR/dotfiles/gtk/gtk.css" "$GTK3_DIR/gtk.css"
        cp "$PROJECT_DIR/dotfiles/gtk/gtk.css" "$GTK4_DIR/gtk.css"
        pass "gtk.css installed (GTK3 + GTK4)"
        ;;
      5) mkdir -p "$GTK3_DIR" "$GTK4_DIR"; ${EDITOR:-nano} "$GTK3_DIR/gtk.css"; cp "$GTK3_DIR/gtk.css" "$GTK4_DIR/gtk.css" 2>/dev/null || true ;;
      6)
        read -rp "  Enter GTK theme name: " theme_name
        [[ -z "$theme_name" ]] && { warn "No name given"; sleep 1; continue; }
        bash "$SCRIPT_DIR/themes.sh" gtk-set "$theme_name"
        ;;
      0) return ;;
      *) warn "Invalid choice"; sleep 1 ;;
    esac
    [[ "$choice" != 0 ]] && { echo; read -rp "  Press Enter to continue ... "; }
  done
}

menu_zebar() {
  show_header
  echo -e " ${BOLD}Zebar Widgets${NC}"
  echo
  local ZEBAR_PACKS="$ZEBAR_V3/packs/labwc-zebar"
  echo "  Current status:"
  echo "    Pack main:     $(check_mark "$ZEBAR_PACKS/main/index.html")"
  echo "    Pack zpack:    $(check_mark "$ZEBAR_PACKS/zpack.json")"
  echo "    V3 settings:   $(check_mark "$ZEBAR_V3/settings.json")"
  echo "    V1 fallback:   $(check_mark "$ZEBAR_V1/main/index.html")"
  echo
  [[ -d "$ZEBAR_V3/widgets" ]] && echo "    Widgets: $(ls "$ZEBAR_V3/widgets" 2>/dev/null | wc -l) installed"
  echo
  echo "  1)  Reinstall main statusbar (with backup)"
  echo "  2)  Reinstall all widgets"
  echo "  3)  Install settings.json"
  echo "  4)  Edit settings.json"
  echo "  5)  Restart zebar"
  echo "  0)  Back to main menu"
  echo
  read -rp "  Select [0-5]: " choice

  case "$choice" in
    1)
      do_backup "zebar-main"
      rm -rf "$ZEBAR_PACKS/main" "$ZEBAR_V1/main"
      mkdir -p "$ZEBAR_PACKS/main"
      cp "$PROJECT_DIR/dotfiles/zebar/main/index.html" "$ZEBAR_PACKS/main/"
      cp "$PROJECT_DIR/dotfiles/zebar/main/style.css" "$ZEBAR_PACKS/main/"
      cp "$PROJECT_DIR/dotfiles/zebar/main/zpack.json" "$ZEBAR_PACKS/main/" 2>/dev/null || true
      cp -r "$PROJECT_DIR/dotfiles/zebar/main"/* "$ZEBAR_V1/main/"
      pass "Main statusbar reinstalled"
      ;;
    2)
      do_backup "zebar-all"
      rm -rf "$ZEBAR_PACKS/main" "$ZEBAR_V1/main"
      mkdir -p "$ZEBAR_PACKS/main"
      cp "$PROJECT_DIR/dotfiles/zebar/main/index.html" "$ZEBAR_PACKS/main/"
      cp "$PROJECT_DIR/dotfiles/zebar/main/style.css" "$ZEBAR_PACKS/main/"
      cp "$PROJECT_DIR/dotfiles/zebar/main/zpack.json" "$ZEBAR_PACKS/main/" 2>/dev/null || true
      cp -r "$PROJECT_DIR/dotfiles/zebar/main"/* "$ZEBAR_V1/main/"
      for w in "$PROJECT_DIR/dotfiles/zebar/widgets"/*/; do
        [[ -d "$w" ]] && cp -r "$w" "$ZEBAR_V3/widgets/" && cp -r "$w" "$ZEBAR_V1/widgets/" 2>/dev/null || true
      done
      pass "All widgets reinstalled"
      ;;
    3)
      mkdir -p "$ZEBAR_V3" "$ZEBAR_V1"
      cp "$PROJECT_DIR/dotfiles/zebar/settings.json" "$ZEBAR_V3/settings.json"
      cp "$PROJECT_DIR/dotfiles/zebar/settings.json" "$ZEBAR_V1/settings.json"
      pass "settings.json installed"
      ;;
    4) ${EDITOR:-nano} "$ZEBAR_V3/settings.json" ;;
    5)
      pkill -x zebar 2>/dev/null || true
      sleep 1
      zebar startup &
      pass "zebar restarted"
      ;;
    0) return ;;
    *) warn "Invalid choice"; sleep 1 ;;
  esac
  echo; read -rp "  Press Enter to continue ... "
}

menu_scripts() {
  show_header
  echo -e " ${BOLD}Reinstall Scripts${NC}"
  echo
  echo "  This copies all scripts from the project to ~/.local/bin/"
  echo
  read -rp "  Proceed? [y/N] " ans
  [[ ! "$ans" =~ ^[Yy] ]] && return

  local dst="$HOME/.local/bin"
  mkdir -p "$dst/actions"

  for script in "$PROJECT_DIR/scripts"/*.sh; do
    [[ -f "$script" ]] && cp "$script" "$dst/$(basename "$script")" && chmod +x "$dst/$(basename "$script")"
  done
  for script in "$PROJECT_DIR/scripts/actions"/*.sh; do
    [[ -f "$script" ]] && cp "$script" "$dst/actions/$(basename "$script")" && chmod +x "$dst/actions/$(basename "$script")"
  done
  pass "Scripts reinstalled ($(ls "$PROJECT_DIR/scripts"/*.sh 2>/dev/null | wc -l) files)"
  read -rp "  Press Enter to continue ... "
}

menu_themes() {
  while true; do
    show_header
    echo -e " ${BOLD}Theme Management${NC}"
    echo
    local current=$(grep -oP '(?<=<name>).*(?=</name>)' "$CONFIG_DIR/rc.xml" 2>/dev/null | head -1 || echo "default")
    local gtk=$(grep -oP '(?<=^gtk-theme-name=).*' "$GTK3_DIR/settings.ini" 2>/dev/null || echo "unset")
    local icon=$(grep -oP '(?<=^gtk-icon-theme-name=).*' "$GTK3_DIR/settings.ini" 2>/dev/null || echo "unset")
    local cursor=$(grep -oP '(?<=^gtk-cursor-theme-name=).*' "$GTK3_DIR/settings.ini" 2>/dev/null || echo "unset")
    echo "  labwc:  ${current}"
    echo "  GTK:    ${gtk}"
    echo "  Icons:  ${icon}"
    echo "  Cursor: ${cursor}"
    echo
    echo "  1)  Interactive picker (pick profiles, themes, icons, cursors)"
    echo "  2)  Pick a profile (full theme stack)"
    echo "  3)  Pick a labwc theme (window borders)"
    echo "  4)  Pick a GTK theme"
    echo "  5)  Pick an icon theme"
    echo "  6)  Pick a cursor theme"
    echo "  7)  Set font"
    echo "  8)  Edit themerc-override"
    echo "  9)  Edit gtk.css"
    echo "  0)  Back to main menu"
    echo
    read -rp "  Select [0-9]: " choice

    case "$choice" in
      1) bash "$SCRIPT_DIR/themes.sh" pick ;;
      2) bash "$SCRIPT_DIR/themes.sh" profile pick ;;
      3) bash "$SCRIPT_DIR/themes.sh" pick <<< $'2\n0' 2>/dev/null ;;
      4) bash "$SCRIPT_DIR/themes.sh" pick <<< $'3\n0' 2>/dev/null ;;
      5) bash "$SCRIPT_DIR/themes.sh" pick <<< $'4\n0' 2>/dev/null ;;
      6) bash "$SCRIPT_DIR/themes.sh" pick <<< $'5\n0' 2>/dev/null ;;
      7)
        read -rp "  Enter font (e.g. 'Noto Sans, 10'): " font
        [[ -n "$font" ]] && bash "$SCRIPT_DIR/themes.sh" font-set "$font"
        ;;
      8) bash "$SCRIPT_DIR/themes.sh" override ;;
      9) bash "$SCRIPT_DIR/themes.sh" gtk-css ;;
      0) return ;;
      *) warn "Invalid choice"; sleep 1 ;;
    esac
    [[ "$choice" != 0 ]] && { echo; read -rp "  Press Enter to continue ... "; }
  done
}

menu_fonts() {
  while true; do
    show_header
    echo -e " ${BOLD}Font Management${NC}"
    echo
    local fc=$(find "${XDG_DATA_HOME:-$HOME/.local/share}/fonts" -type f \( -name "*.ttf" -o -name "*.otf" \) 2>/dev/null | wc -l)
    echo "  Fonts installed: ${fc} files"
    echo
    echo "  1)  Install UI fonts (Inter, Noto, etc.)"
    echo "  2)  Install monospace fonts (JetBrains, FiraCode, etc.)"
    echo "  3)  Install Nerd Fonts (with icon glyphs)"
    echo "  4)  Install a font profile (dev, minimal, ui, etc.)"
    echo "  5)  Browse system fonts"
    echo "  6)  Preview a font"
    echo "  7)  Set system font"
    echo "  0)  Back to main menu"
    echo
    read -rp "  Select [0-7]: " choice

    case "$choice" in
      1) bash "$SCRIPT_DIR/download-themes.sh" ui ;;
      2) bash "$SCRIPT_DIR/download-themes.sh" mono ;;
      3) bash "$SCRIPT_DIR/download-themes.sh" nerd ;;
      4)
        echo; bash "$SCRIPT_DIR/download-themes.sh" list 2>&1 | grep -A20 "Font Profiles" || bash "$SCRIPT_DIR/download-themes.sh" list
        echo
        read -rp "  Enter font profile name (dev, ui, minimal, etc): " fp
        [[ -n "$fp" ]] && bash "$SCRIPT_DIR/download-themes.sh" font-profile "$fp"
        ;;
      5)
        echo; bash "$SCRIPT_DIR/themes.sh" font-list
        ;;
      6)
        read -rp "  Enter font name to preview: " fn
        [[ -n "$fn" ]] && bash "$SCRIPT_DIR/themes.sh" font-preview "$fn"
        ;;
      7)
        read -rp "  Enter font (e.g. 'Noto Sans, 10'): " font
        [[ -n "$font" ]] && bash "$SCRIPT_DIR/themes.sh" font-set "$font"
        ;;
      0) return ;;
      *) warn "Invalid choice"; sleep 1 ;;
    esac
    [[ "$choice" != 0 ]] && { echo; read -rp "  Press Enter to continue ... "; }
  done
}

menu_downloads() {
  while true; do
    show_header
    echo -e " ${BOLD}Download Themes & Fonts${NC}"
    echo
    echo "  1)  Download all (GTK + icons + cursors + fonts)"
    echo "  2)  Download GTK themes (Nordic, Catppuccin)"
    echo "  3)  Download icon themes (Papirus-Dark)"
    echo "  4)  Download cursor themes (Bibata, Catppuccin)"
    echo "  5)  List available downloads"
    echo "  6)  Clean download cache"
    echo "  0)  Back to main menu"
    echo
    read -rp "  Select [0-6]: " choice

    case "$choice" in
      1) bash "$SCRIPT_DIR/download-themes.sh" all ;;
      2) bash "$SCRIPT_DIR/download-themes.sh" gtk ;;
      3) bash "$SCRIPT_DIR/download-themes.sh" icons ;;
      4) bash "$SCRIPT_DIR/download-themes.sh" cursors ;;
      5) bash "$SCRIPT_DIR/download-themes.sh" list ;;
      6) bash "$SCRIPT_DIR/download-themes.sh" clean ;;
      0) return ;;
      *) warn "Invalid choice"; sleep 1 ;;
    esac
    [[ "$choice" != 0 ]] && { echo; read -rp "  Press Enter to continue ... "; }
  done
}

menu_backup() {
  while true; do
    show_header
    echo -e " ${BOLD}Backup & Restore${NC}"
    echo
    local count=$(ls -1 "$HOME/.config/labwc-backups"/*.tar.gz 2>/dev/null | wc -l)
    echo "  Existing backups: ${count}"
    [[ "$count" -gt 0 ]] && echo "  Latest: $(ls -1t "$HOME/.config/labwc-backups"/*.tar.gz 2>/dev/null | head -1)"
    echo
    echo "  1)  Create a backup now"
    echo "  2)  List available backups"
    echo "  3)  Restore from backup"
    echo "  0)  Back to main menu"
    echo
    read -rp "  Select [0-3]: " choice

    case "$choice" in
      1) bash "$SCRIPT_DIR/backup.sh" ;;
      2)
        echo
        if ls "$HOME/.config/labwc-backups"/*.tar.gz &>/dev/null; then
          ls -1ht "$HOME/.config/labwc-backups"/*.tar.gz | while read -r b; do
            local size=$(du -h "$b" | cut -f1)
            local name=$(basename "$b" .tar.gz | sed 's/-/ /')
            echo "  ${GREEN}●${NC} $name  ${DIM}(${size})${NC}"
          done
        else
          echo "  No backups found."
        fi
        ;;
      3) bash "$SCRIPT_DIR/restore.sh" ;;
      0) return ;;
      *) warn "Invalid choice"; sleep 1 ;;
    esac
    [[ "$choice" != 0 ]] && { echo; read -rp "  Press Enter to continue ... "; }
  done
}

menu_validate() {
  show_header
  echo -e " ${BOLD}Validate & Fix${NC}"
  echo
  echo "  1)  Validate setup"
  echo "  2)  Auto-fix issues"
  echo "  3)  Run full diagnostics"
  echo "  4)  Show status"
  echo "  0)  Back to main menu"
  echo
  read -rp "  Select [0-4]: " choice

  case "$choice" in
    1) bash "$SCRIPT_DIR/validate.sh" ;;
    2) bash "$SCRIPT_DIR/fix.sh" ;;
    3) bash "$SCRIPT_DIR/diagnostics.sh" ;;
    4) bash "$SCRIPT_DIR/status.sh" ;;
    0) return ;;
    *) warn "Invalid choice"; sleep 1 ;;
  esac
  echo; read -rp "  Press Enter to continue ... "
}

# ============================================================
# Start
# ============================================================

menu_main
