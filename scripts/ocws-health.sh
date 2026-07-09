#!/bin/bash
set -euo pipefail

# Desktop notifications for failures (ocws-notify / mako / dunst).
# Sourced without ocws_enable_strict: health checks must keep running and
# tally failures rather than aborting on the first one.
source "$(dirname "${BASH_SOURCE[0]}")/lib/ocws-err.sh"

# ocws-health.sh — Comprehensive health diagnostics for OCWS
# Checks system resources, services, dependencies, config integrity, and C binaries.

OCWS_DIR="${OCWS_DIR:-$HOME/.config/ocws}"
LABWC_DIR="${LABWC_DIR:-$HOME/.config/labwc}"
LOCAL_BIN="${HOME}/.local/bin"
STATE_DIR="$OCWS_DIR/state"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0
INFO=0

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; WARN=$((WARN+1)); }
fail() { ocws_notify_error "OCWS Health" "$1"; echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); }
info() { echo -e "  ${CYAN}INFO${NC} $1"; INFO=$((INFO+1)); }
header() { echo -e "\n${BOLD}${CYAN}[$1]${NC} ${BOLD}$2${NC}"; }

echo -e "${BOLD}=== OCWS Health Check ===${NC}"
echo -e "${DIM}$(date)${NC}"

# ============================================================
# [1/12] System Resources
# ============================================================
header "1/12" "System Resources"

# Memory
MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))

if [[ "$MEM_PCT" -lt 70 ]]; then
    pass "Memory: ${MEM_PCT}% used ($((MEM_USED/1024))MB / $((MEM_TOTAL/1024))MB)"
elif [[ "$MEM_PCT" -lt 85 ]]; then
    warn "Memory: ${MEM_PCT}% used ($((MEM_USED/1024))MB / $((MEM_TOTAL/1024))MB)"
else
    fail "Memory: ${MEM_PCT}% used ($((MEM_USED/1024))MB / $((MEM_TOTAL/1024))MB) — critical"
fi

# CPU Load
LOAD_1=$(awk '{print $1}' /proc/loadavg)
LOAD_5=$(awk '{print $2}' /proc/loadavg)
CORES=$(nproc)
LOAD_PCT=$(echo "$LOAD_1 $CORES" | awk '{printf "%.0f", ($1/$2)*100}')

if [[ "$LOAD_PCT" -lt 70 ]]; then
    pass "CPU Load: ${LOAD_PCT}% (${LOAD_1} avg, ${CORES} cores)"
elif [[ "$LOAD_PCT" -lt 100 ]]; then
    warn "CPU Load: ${LOAD_PCT}% (${LOAD_1} avg, ${CORES} cores)"
else
    fail "CPU Load: ${LOAD_PCT}% (${LOAD_1} avg, ${CORES} cores) — overloaded"
fi

# Disk
DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
if [[ "$DISK_PCT" -lt 70 ]]; then
    pass "Disk: ${DISK_PCT}% used (${DISK_AVAIL} free)"
elif [[ "$DISK_PCT" -lt 85 ]]; then
    warn "Disk: ${DISK_PCT}% used (${DISK_AVAIL} free)"
else
    fail "Disk: ${DISK_PCT}% used (${DISK_AVAIL} free) — low space"
fi

# Swap
SWAP_TOTAL=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
if [[ "$SWAP_TOTAL" -gt 0 ]]; then
    SWAP_AVAIL=$(grep SwapFree /proc/meminfo | awk '{print $2}')
    SWAP_USED=$((SWAP_TOTAL - SWAP_AVAIL))
    SWAP_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
    if [[ "$SWAP_PCT" -lt 50 ]]; then
        pass "Swap: ${SWAP_PCT}% used ($((SWAP_USED/1024))MB / $((SWAP_TOTAL/1024))MB)"
    elif [[ "$SWAP_PCT" -lt 80 ]]; then
        warn "Swap: ${SWAP_PCT}% used ($((SWAP_USED/1024))MB / $((SWAP_TOTAL/1024))MB)"
    else
        fail "Swap: ${SWAP_PCT}% used — heavy swapping"
    fi
else
    info "Swap: not configured"
fi

# ============================================================
# [2/12] Wayland Session
# ============================================================
header "2/12" "Wayland Session"

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    pass "WAYLAND_DISPLAY: $WAYLAND_DISPLAY"
else
    fail "WAYLAND_DISPLAY not set — not in Wayland session"
fi

if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
    pass "XDG_CURRENT_DESKTOP: $XDG_CURRENT_DESKTOP"
else
    warn "XDG_CURRENT_DESKTOP not set"
fi

if [[ -n "${XDG_SESSION_TYPE:-}" ]]; then
    pass "XDG_SESSION_TYPE: $XDG_SESSION_TYPE"
else
    warn "XDG_SESSION_TYPE not set"
fi

# Check labwc version
if command -v labwc &>/dev/null; then
    LABWC_VER=$(labwc --version 2>&1 | head -1 || echo "unknown")
    info "labwc version: $LABWC_VER"
fi

# ============================================================
# [3/12] Core Services
# ============================================================
header "3/12" "Core Services"

# sfwbar
if pgrep -x sfwbar &>/dev/null; then
    SFWPID=$(pgrep -x sfwbar | head -1)
    SFWMEM=$(ps -o rss= -p "$SFWPID" 2>/dev/null | awk '{printf "%.1f", $1/1024}' || echo "?")
    pass "sfwbar running (PID: $SFWPID, RSS: ${SFWMEM}MB)"
else
    fail "sfwbar not running"
fi

# labwc
if pgrep -x labwc &>/dev/null; then
    pass "labwc running"
else
    warn "labwc not running"
fi

# ocws-daemon
if pgrep -f "ocws-daemon" &>/dev/null; then
    pass "ocws-daemon running"
else
    warn "ocws-daemon not running — some features may not work"
fi

# ============================================================
# [4/12] OCWS C Binaries
# ============================================================
header "4/12" "OCWS C Binaries"

OCWS_BINS=(
    ocws-sysmon ocws-clip ocws-shot ocws-lock ocws-kv
    ocws-brightness ocws-volume ocws-notify ocws-wallpaper
    ocws-color ocws-emit ocws osd-notify ocws-ocr
    ocws-recorder ocws-search ocws-settings ocws-hypertile
    ocws-live-bg ocws-player ocws-network-bandwidth
)

for bin in "${OCWS_BINS[@]}"; do
    if [[ -x "$LOCAL_BIN/$bin" ]]; then
        # Test if binary runs without segfault (check exit code, not output)
        set +e
        timeout 2 "$LOCAL_BIN/$bin" --help >/dev/null 2>&1
        EXIT_CODE=$?
        set -e
        # Exit codes: 0=ok, 1=normal error, 124=timeout (ok), 139=segfault (bad)
        if [[ "$EXIT_CODE" -eq 139 ]] || [[ "$EXIT_CODE" -eq 136 ]]; then
            fail "$bin installed but crashes (segfault/signal)"
        elif [[ "$EXIT_CODE" -eq 124 ]]; then
            pass "$bin installed and responsive"
        else
            pass "$bin installed"
        fi
    else
        fail "$bin not found at $LOCAL_BIN/$bin"
    fi
done

# Check shell scripts
for script in ocws-daemon.sh ocws-plugin-loader.sh ocws-autorun.sh; do
    if [[ -x "$LOCAL_BIN/$script" ]] || [[ -f "$LOCAL_BIN/$script" ]]; then
        pass "$script installed"
    elif [[ -f "$OCWS_DIR/$script" ]]; then
        warn "$script found in OCWS_DIR but not linked to PATH"
    else
        fail "$script missing"
    fi
done

# ============================================================
# [5/12] Runtime Dependencies
# ============================================================
header "5/12" "Runtime Dependencies"

# Critical tools
for cmd in contour foot rofi wl-copy wl-paste grim slurp jq; do
    if command -v "$cmd" &>/dev/null; then
        pass "$cmd: $(command -v $cmd)"
    else
        fail "$cmd not found — critical dependency"
    fi
done

# Important tools
for cmd in playerctl brightnessctl cliphist swaybg swayidle swaylock; do
    if command -v "$cmd" &>/dev/null; then
        pass "$cmd: $(command -v $cmd)"
    else
        warn "$cmd not found — optional but recommended"
    fi
done

# Notification daemons
if pgrep -x mako &>/dev/null; then
    pass "mako notification daemon running"
elif pgrep -x dunst &>/dev/null; then
    pass "dunst notification daemon running"
else
    warn "No notification daemon running (mako/dunst)"
fi

# Clipboard daemon
if pgrep -f "wl-paste.*cliphist" &>/dev/null; then
    pass "Clipboard daemon (cliphist) running"
elif pgrep -f "wl-paste" &>/dev/null; then
    pass "wl-paste running (without cliphist)"
else
    warn "Clipboard daemon not running"
fi

# ============================================================
# [6/12] Config Directories
# ============================================================
header "6/12" "Config Directories"

for dir in "$OCWS_DIR" "$LABWC_DIR" "$OCWS_DIR/plugins" "$STATE_DIR"; do
    if [[ -d "$dir" ]]; then
        FILE_COUNT=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
        pass "$dir ($FILE_COUNT files)"
    else
        if [[ "$dir" == "$STATE_DIR" ]]; then
            info "$dir not found — will be created on first use"
        else
            fail "$dir missing"
        fi
    fi
done

# ============================================================
# [7/12] Core Config Files
# ============================================================
header "7/12" "Core Config Files"

# OCWS configs
for file in "$OCWS_DIR/ocws.config" "$OCWS_DIR/user.config" "$OCWS_DIR/plugins.config" "$OCWS_DIR/ocws.css" "$OCWS_DIR/theme.css"; do
    if [[ -f "$file" ]]; then
        FILE_SIZE=$(du -h "$file" | awk '{print $1}')
        pass "$(basename $file) ($FILE_SIZE)"
    else
        fail "$(basename $file) missing"
    fi
done

# Labwc configs
for file in "$LABWC_DIR/rc.xml" "$LABWC_DIR/autostart" "$LABWC_DIR/environment" "$LABWC_DIR/themerc-override"; do
    if [[ -f "$file" ]]; then
        pass "$(basename $file)"
    else
        fail "$(basename $file) missing"
    fi
done

# Other tool configs
for file in "$HOME/.config/contour/contour.yml" "$HOME/.config/foot/foot.ini" "$HOME/.config/rofi/config.rasi" "$HOME/.config/mako/config" "$HOME/.config/swaylock/config"; do
    if [[ -f "$file" ]]; then
        pass "$(basename $file)"
    else
        warn "$(basename $file) missing"
    fi
done

# ============================================================
# [8/12] Widget Files
# ============================================================
header "8/12" "Widget Files"

WIDGET_COUNT=$(find "$OCWS_DIR" -name "*.widget" 2>/dev/null | wc -l)
if [[ "$WIDGET_COUNT" -ge 20 ]]; then
    pass "Widget files: $WIDGET_COUNT found"
elif [[ "$WIDGET_COUNT" -ge 10 ]]; then
    warn "Widget files: only $WIDGET_COUNT found (expected 20+)"
else
    fail "Widget files: only $WIDGET_COUNT found (expected 20+)"
fi

# Critical widgets
for widget in launcher.widget workspaces.widget clock.widget volume-text.widget battery-text.widget tray.widget dock.widget; do
    if [[ -f "$OCWS_DIR/$widget" ]]; then
        pass "$widget"
    else
        fail "$widget missing"
    fi
done

# Widget sets
if [[ -d "$OCWS_DIR/widget-sets" ]]; then
    SET_COUNT=$(find "$OCWS_DIR/widget-sets" -name "*.set" 2>/dev/null | wc -l)
    pass "Widget sets: $SET_COUNT found"
else
    warn "widget-sets directory missing"
fi

# ============================================================
# [9/12] Source Files
# ============================================================
header "9/12" "Source Files"

for source in ocws-sysmon.source cpu.source memory.source battery.source; do
    if [[ -f "$OCWS_DIR/$source" ]]; then
        pass "$source"
    else
        fail "$source missing"
    fi
done

# Check source file references in ocws.config
if [[ -f "$OCWS_DIR/ocws.config" ]]; then
    MISSING_SOURCES=0
    for ref in $(grep -oP 'include\("[^"]+\.source"\)' "$OCWS_DIR/ocws.config" 2>/dev/null | grep -oP '"[^"]+"' | tr -d '"'); do
        if [[ ! -f "$OCWS_DIR/$ref" ]]; then
            warn "Referenced source missing: $ref"
            MISSING_SOURCES=$((MISSING_SOURCES+1))
        fi
    done
    if [[ "$MISSING_SOURCES" -eq 0 ]]; then
        pass "All source references in ocws.config valid"
    fi
fi

# ============================================================
# [10/12] CSS Validation
# ============================================================
header "10/12" "CSS Validation"

for css in "$OCWS_DIR/ocws.css" "$OCWS_DIR/theme.css"; do
    if [[ -f "$css" ]]; then
        # Check for invalid GTK3 CSS features
        INVALID=$(grep -c "linear-gradient\|backdrop-filter\|:root\|--blur\|var(\|@keyframes" "$css" 2>/dev/null || true)
        if [[ "$INVALID" -eq 0 ]]; then
            pass "$(basename $css) — valid GTK3 CSS"
        else
            warn "$(basename $css) — $INVALID invalid GTK3 features found"
        fi

        # Check for missing @define-color
        COLOR_COUNT=$(grep -c "@define-color" "$css" 2>/dev/null || true)
        if [[ "$COLOR_COUNT" -gt 0 ]]; then
            pass "$(basename $css) — $COLOR_COUNT color definitions"
        else
            info "$(basename $css) — no color definitions"
        fi
    else
        fail "$(basename $css) missing"
    fi
done

# ============================================================
# [11/12] Theme & State
# ============================================================
header "11/12" "Theme & State"

# Current theme
CURRENT_THEME_FILE="$LABWC_DIR/.current-theme"
if [[ -f "$CURRENT_THEME_FILE" ]]; then
    CURRENT_THEME=$(cat "$CURRENT_THEME_FILE")
    pass "Active theme: $CURRENT_THEME"
else
    info "No active theme set"
fi

# State files
if [[ -d "$STATE_DIR" ]]; then
    STATE_COUNT=$(find "$STATE_DIR" -type f 2>/dev/null | wc -l)
    pass "State files: $STATE_COUNT"

    # Check for corrupted JSON
    CORRUPTED=0
    for f in "$STATE_DIR"/*.json; do
        if [[ -f "$f" ]]; then
            if ! jq . "$f" &>/dev/null; then
                warn "Corrupted JSON: $(basename $f)"
                CORRUPTED=$((CORRUPTED+1))
            fi
        fi
    done
    if [[ "$CORRUPTED" -eq 0 ]] && [[ "$STATE_COUNT" -gt 0 ]]; then
        pass "All state JSON files valid"
    fi
else
    info "State directory not found — will be created on first use"
fi

# KV store
if [[ -x "$LOCAL_BIN/ocws-kv" ]]; then
    if "$LOCAL_BIN/ocws-kv" get shell_mode &>/dev/null 2>&1; then
        SHELL_MODE=$("$LOCAL_BIN/ocws-kv" get shell_mode 2>/dev/null || echo "unknown")
        pass "KV store working — shell_mode: $SHELL_MODE"
    else
        info "KV store available but no shell_mode set"
    fi
fi

# ============================================================
# [12/12] Potential Issues
# ============================================================
header "12/12" "Potential Issues"

# Stale lock files
LOCK_COUNT=$(find /tmp -name "ocws-*.lock" 2>/dev/null | wc -l)
if [[ "$LOCK_COUNT" -gt 0 ]]; then
    warn "$LOCK_COUNT stale lock files in /tmp"
else
    pass "No stale lock files"
fi

# Zombie processes
ZOMBIES=$(ps aux | awk '$8 ~ /Z/ {count++} END {print count+0}')
if [[ "$ZOMBIES" -gt 0 ]]; then
    warn "$ZOMBIES zombie processes found"
else
    pass "No zombie processes"
fi

# Config size
CONFIG_SIZE=$(du -sh "$OCWS_DIR" 2>/dev/null | awk '{print $1}')
pass "Config size: $CONFIG_SIZE"

# Binary sizes
TOTAL_BIN_SIZE=0
for bin in "$LOCAL_BIN"/ocws-*; do
    if [[ -f "$bin" ]] && file "$bin" | grep -q "ELF"; then
        BIN_SIZE=$(stat -c%s "$bin" 2>/dev/null || echo 0)
        TOTAL_BIN_SIZE=$((TOTAL_BIN_SIZE + BIN_SIZE))
    fi
done
TOTAL_BIN_MB=$((TOTAL_BIN_SIZE / 1024 / 1024))
info "Total OCWS binary size: ${TOTAL_BIN_MB}MB"

# Duplicate processes
SFWBAR_COUNT=$(pgrep -c sfwbar 2>/dev/null || echo 0)
if [[ "$SFWBAR_COUNT" -gt 1 ]]; then
    warn "$SFWBAR_COUNT sfwbar instances running (expected: 1)"
fi

# Theme consistency
if [[ -f "$HOME/.config/gtk-3.0/settings.ini" ]]; then
    GTK_THEME=$(grep "gtk-theme-name" "$HOME/.config/gtk-3.0/settings.ini" | cut -d= -f2)
    if [[ "$GTK_THEME" == *"Catppuccin"* ]]; then
        pass "GTK theme: Catppuccin (consistent)"
    else
        warn "GTK theme: $GTK_THEME (expected Catppuccin)"
    fi
fi

if [[ -f "$HOME/.config/qt6ct/qt6ct.conf" ]]; then
    QT_ICON=$(grep "icon_theme" "$HOME/.config/qt6ct/qt6ct.conf" | cut -d= -f2)
    if [[ "$QT_ICON" == *"Papirus"* ]]; then
        pass "Qt icon theme: Papirus (consistent)"
    else
        warn "Qt icon theme: $QT_ICON (expected Papirus)"
    fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${BOLD}=== Health Check Complete ===${NC}"
echo -e "  ${GREEN}PASS: $PASS${NC}"
echo -e "  ${YELLOW}WARN: $WARN${NC}"
echo -e "  ${RED}FAIL: $FAIL${NC}"
echo -e "  ${CYAN}INFO: $INFO${NC}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${RED}${BOLD}Some checks failed.${NC} Run 'ocws-validate' to diagnose, or './install.sh' to fix."
    exit 1
elif [[ "$WARN" -gt 0 ]]; then
    echo -e "${YELLOW}${BOLD}Some warnings.${NC} OCWS will work but some features may be limited."
    exit 0
else
    echo -e "${GREEN}${BOLD}All checks passed!${NC}"
    exit 0
fi
