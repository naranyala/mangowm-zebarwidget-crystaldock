#!/bin/bash
#
# fix.sh — Auto-fix common issues with labwc + zebar + crystal-dock setup
#
# Fixes: permissions, missing dirs, broken symlinks, config issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${HOME}/.config/labwc"
SFWBAR_DIR="${HOME}/.config/sfwbar"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

FIXED=0
SKIPPED=0

pass()  { echo -e "  ${GREEN}✓${NC} $1"; FIXED=$((FIXED + 1)); }
skip()  { echo -e "  ${YELLOW}→${NC} $1 (skipped)"; SKIPPED=$((SKIPPED + 1)); }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
section() { echo -e "\n${BOLD}[$1]${NC}"; }

echo ""
echo "== labwc Auto-Fix =="
echo ""

# ============================================================
section "1. Create Missing Directories"
# ============================================================
for dir in "$CONFIG_DIR" "$SFWBAR_DIR" "$HOME/.local/bin" "$HOME/Pictures/wallpapers"; do
  if [ -d "$dir" ]; then
    skip "$dir already exists"
  else
    mkdir -p "$dir"
    pass "Created $dir"
  fi
done

# ============================================================
section "2. Fix Permissions"
# ============================================================
for file in "$CONFIG_DIR/autostart"; do
  if [ -f "$file" ] && [ ! -x "$file" ]; then
    chmod +x "$file"
    pass "Made $file executable"
  else
    skip "$file permissions OK"
  fi
done

# ============================================================
section "3. Fix Broken Symlinks"
# ============================================================
BROKEN=0
while IFS= read -r -d '' link; do
  if [ ! -e "$link" ]; then
    warn "Broken symlink: $link -> $(readlink "$link")"
    rm -f "$link"
    pass "Removed broken symlink: $link"
    ((BROKEN++))
  fi
done < <(find "$CONFIG_DIR" "$SFWBAR_DIR" -type l -print0 2>/dev/null)

if [ "$BROKEN" -eq 0 ]; then
  skip "No broken symlinks found"
fi

# ============================================================
section "4. Install Missing Config Files"
# ============================================================
DOTFILES_DIR="$PROJECT_DIR/dotfiles/labwc"

for cfg in rc.xml autostart environment menu.xml themerc-override; do
  if [ -f "$DOTFILES_DIR/$cfg" ] && [ ! -f "$CONFIG_DIR/$cfg" ]; then
    # Validate rc.xml source before installing
    if [ "$cfg" = "rc.xml" ]; then
      CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$DOTFILES_DIR/$cfg")
      if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
        warn "Source rc.xml has broken Client context — skipping install"
        continue
      fi
    fi
    cp "$DOTFILES_DIR/$cfg" "$CONFIG_DIR/$cfg"
    pass "Installed missing $cfg"
  else
    skip "$cfg already exists"
  fi
done

# ============================================================
section "5. Fix Wallpaper Script"
# ============================================================
WALLPAPER_SRC="$PROJECT_DIR/dotfiles/wallpaper"
WALLPAPER_DST="$HOME/.local/bin/wallpaper"

if [ -f "$WALLPAPER_SRC" ]; then
  if [ ! -f "$WALLPAPER_DST" ] || [ "$WALLPAPER_SRC" -nt "$WALLPAPER_DST" ]; then
    cp "$WALLPAPER_SRC" "$WALLPAPER_DST"
    chmod +x "$WALLPAPER_DST"
    pass "Installed/updated wallpaper script"
  else
    skip "Wallpaper script up to date"
  fi
fi

# ============================================================
section "6. Fix SFWBar Configuration"
# ============================================================
SFWBAR_SRC="$PROJECT_DIR/dotfiles/sfwbar"
SFWBAR_DST="$HOME/.config/sfwbar"

if [ -d "$SFWBAR_SRC" ]; then
  mkdir -p "$SFWBAR_DST"
  for cfg in sfwbar.config catppuccin-mocha.css; do
    if [ -f "$SFWBAR_SRC/$cfg" ]; then
      if [ ! -f "$SFWBAR_DST/$cfg" ]; then
        cp "$SFWBAR_SRC/$cfg" "$SFWBAR_DST/$cfg"
        pass "Installed $cfg"
      else
        skip "$cfg already exists"
      fi
    fi
  done
fi

# ============================================================
section "7. Fix rc.xml Client Context"
# ============================================================
RC_XML="$CONFIG_DIR/rc.xml"
if [ -f "$RC_XML" ]; then
  CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$RC_XML")
  if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
    # Replace entire Client context — plain Left/Right Drag and Middle Press
    # consume click events and prevent apps from receiving clicks.
    # Only keep Alt+Left (Move) and Alt+Right (Resize).
    GOOD_CTX='      <context name="Client">
        <mousebind button="A-Left" action="Drag">
          <action name="Move" />
        </mousebind>
        <mousebind button="A-Right" action="Drag">
          <action name="Resize" />
        </mousebind>
      </context>'
    python3 -c "
import re, sys
with open('$RC_XML', 'r') as f:
    content = f.read()
pattern = r'<context name=\"Client\">.*?</context>'
replacement = '''$GOOD_CTX'''
content = re.sub(pattern, replacement, content, flags=re.DOTALL)
with open('$RC_XML', 'w') as f:
    f.write(content)
" && pass "Fixed Client context: removed Left Press binding" || warn "Could not fix Client context"
  else
    skip "Client context OK"
  fi
fi

# ============================================================
section "8. Fix Environment Variables"
# ============================================================
ENV_FILE="$CONFIG_DIR/environment"
if [ -f "$ENV_FILE" ]; then
  CHANGES=0
  for var in XDG_CURRENT_DESKTOP=labwc XDG_SESSION_TYPE=wayland XDG_SESSION_DESKTOP=labwc; do
    KEY="${var%%=*}"
    VALUE="${var#*=}"
    if ! grep -q "^${KEY}=" "$ENV_FILE" 2>/dev/null; then
      echo "${KEY}=${VALUE}" >> "$ENV_FILE"
      pass "Added $KEY=$VALUE to environment"
      ((CHANGES++))
    fi
  done
  if [ "$CHANGES" -eq 0 ]; then
    skip "Environment variables OK"
  fi
fi

# ============================================================
section "8. Fix Path"
# ============================================================
PROFILE_FILE=""
for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
  if [ -f "$f" ]; then
    PROFILE_FILE="$f"
    break
  fi
done

if [ -n "$PROFILE_FILE" ]; then
  if ! grep -q '\.local/bin' "$PROFILE_FILE" 2>/dev/null; then
    echo '' >> "$PROFILE_FILE"
    echo '# labwc - add local bin to PATH' >> "$PROFILE_FILE"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE_FILE"
    pass "Added ~/.local/bin to PATH in $PROFILE_FILE"
  else
    skip "PATH already configured in $PROFILE_FILE"
  fi
fi

# ============================================================
section "9. Create Wayland Session File"
# ============================================================
SESSION_DIR="/usr/share/wayland-sessions"
SESSION_FILE="$SESSION_DIR/labwc.desktop"

LABWC_BIN="$(command -v labwc 2>/dev/null || echo "")"
if [ -n "$LABWC_BIN" ]; then
  if [ -d "$SESSION_DIR" ] && [ ! -f "$SESSION_FILE" ]; then
    cat > /tmp/labwc.desktop << EOF
[Desktop Entry]
Name=labwc
Comment=Lab Wayland Compositor
Exec=$LABWC_BIN
Type=Application
DesktopNames=labwc
Keywords=wayland;compositor;labwc;
EOF
    if sudo cp /tmp/labwc.desktop "$SESSION_FILE" 2>/dev/null; then
      sudo chmod 644 "$SESSION_FILE"
      pass "Created labwc.desktop session file"
    else
      warn "Could not create session file (need sudo)"
    fi
    rm -f /tmp/labwc.desktop
  else
    skip "Session file exists or session dir not found"
  fi
fi

# ============================================================
section "10. Remove Old Files"
# ============================================================
for old_file in "$PROJECT_DIR/download-mango.sh" "$PROJECT_DIR/scripts/start-mango.sh"; do
  if [ -f "$old_file" ]; then
    rm -f "$old_file"
    pass "Removed old file: $(basename "$old_file")"
  fi
done

for old_dir in "$PROJECT_DIR/dotfiles/mango" "$PROJECT_DIR/config/mango"; do
  if [ -d "$old_dir" ]; then
    rm -rf "$old_dir"
    pass "Removed old directory: $(basename "$old_dir")"
  fi
done

# ============================================================
section "Summary"
# ============================================================
echo ""
echo -e "${GREEN}${BOLD}$FIXED fix(es) applied${NC}, ${YELLOW}$SKIPPED item(s) skipped${NC}"
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/validate.sh to check for remaining issues"
echo "  2. Run ./scripts/start-labwc.sh to launch"
echo ""
