#!/bin/bash
#
# theme-engine — Generate all config files from a theme INI profile
#
# Usage:
#   theme-engine apply <theme.ini>           Apply theme (generate + install)
#   theme-engine preview <theme.ini>         Show what would be generated
#   theme-engine list                        List available themes
#   theme-engine current                     Show active theme
#   theme-engine export <theme.ini>          Export generated files to dotfiles/
#
# Themes are INI files in themes/ with sections:
#   [meta], [colors], [labwc], [gtk3], [gtk4], [fonts],
#   [rofi], [sfwbar], [zebar], [mako], [foot], [qt6ct], [kvantum], [cursor]
#

set -uo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find project root: check env var, then walk up from script dir
if [[ -n "${LABWC_PROJECT:-}" && -d "$LABWC_PROJECT/themes" ]]; then
    PROJECT_DIR="$LABWC_PROJECT"
else
    PROJECT_DIR="$SCRIPT_DIR"
    while [[ ! -d "$PROJECT_DIR/themes" && "$PROJECT_DIR" != "/" ]]; do
        PROJECT_DIR="$(dirname "$PROJECT_DIR")"
    done
fi
# Fallback: known path
[[ -d "$PROJECT_DIR/themes" ]] || PROJECT_DIR="/media/naranyala/Data/projects-remote/labwc-crystaldock-barandwidgets"
[[ -d "$PROJECT_DIR/themes" ]] || fail "Cannot find project root (themes/ not found)"
THEMES_DIR="$PROJECT_DIR/themes"
TEMPLATES_DIR="$PROJECT_DIR/templates"
DOTFILES_DIR="$PROJECT_DIR/dotfiles"

# ============================================================
# INI Parser — reads INI into associative arrays
# ============================================================

declare -A INI_VALUES

parse_ini() {
    local file="$1"
    local section=""

    [[ -f "$file" ]] || fail "Theme not found: $file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty/comment lines
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Section header
        if [[ "$line" =~ ^\[([a-zA-Z0-9_]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key=Value
        if [[ "$line" =~ ^([a-zA-Z0-9_]+)=(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Strip surrounding quotes
            val="${val#\"}"
            val="${val%\"}"
            val="${val#\'}"
            val="${val%\'}"
            INI_VALUES["${section}.${key}"]="$val"
        fi
    done < "$file"
}

# Get value with section.key, with optional default
ini_get() {
    local key="$1" default="${2:-}"
    echo "${INI_VALUES[$key]:-$default}"
}

# ============================================================
# Variable Expansion — resolves ${ref} in values
# ============================================================

expand_vars() {
    local max_depth=5
    local depth=0

    while (( depth < max_depth )); do
        local changed=false
        for key in "${!INI_VALUES[@]}"; do
            local val="${INI_VALUES[$key]}"
            # Expand ${section.key} references
            while [[ "$val" =~ \$\{([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)\} ]]; do
                local ref="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
                local replacement="${INI_VALUES[$ref]:-}"
                if [[ -n "$replacement" ]]; then
                    val="${val//\$\{${BASH_REMATCH[1]}.${BASH_REMATCH[2]}\}/$replacement}"
                    changed=true
                else
                    break
                fi
            done
            INI_VALUES["$key"]="$val"
        done
        [[ "$changed" == "false" ]] && break
        ((depth++))
    done
}

# ============================================================
# Template Renderer — replaces {{VAR}} placeholders
# ============================================================

render_template() {
    local template_file="$1"
    [[ -f "$template_file" ]] || { warn "Template not found: $template_file"; return 1; }

    local content
    content=$(<"$template_file")

    # Replace {{KEY}} with INI values
    while [[ "$content" =~ \{\{([A-Z_]+)\}\} ]]; do
        local placeholder="${BASH_REMATCH[0]}"
        local var_name="${BASH_REMATCH[1]}"
        local value=""

        # Map template variables to INI keys
        case "$var_name" in
            # Meta
            THEME_NAME) value=$(ini_get "meta.name" "Unknown") ;;

            # Colors (direct palette)
            COLOR_BG)          value=$(ini_get "colors.bg" "#1e1e2e") ;;
            COLOR_FG)          value=$(ini_get "colors.text" "#cdd6f4") ;;
            COLOR_ACCENT)      value=$(ini_get "colors.blue" "#89b4fa") ;;
            COLOR_URGENT)      value=$(ini_get "colors.red" "#f38ba8") ;;
            COLOR_WARNING)     value=$(ini_get "colors.yellow" "#f9e2af") ;;
            COLOR_OK)          value=$(ini_get "colors.green" "#a6e3a1") ;;
            COLOR_SURFACE)     value=$(ini_get "colors.surface1" "#45475a") ;;
            COLOR_BORDER)      value=$(ini_get "colors.surface2" "#585b70") ;;
            COLOR_MUTED)       value=$(ini_get "colors.overlay0" "#6c7086") ;;
            COLOR_TEAL)        value=$(ini_get "colors.teal" "#94e2d5") ;;
            COLOR_MAUVE)       value=$(ini_get "colors.mauve" "#cba6f7") ;;

            # Alpha suffixes (convert 0.92 → eb hex)
            BG_ALPHA)
                local a=$(ini_get "sfwbar.bar_bg_alpha" "0.92")
                value=$(printf "%02x" "$(awk "BEGIN{printf \"%d\", $a * 255}")" 2>/dev/null || echo "eb")
                ;;
            SURFACE_ALPHA)
                local a=$(ini_get "sfwbar.module_bg_alpha" "0.4")
                value=$(printf "%02x" "$(awk "BEGIN{printf \"%d\", $a * 255}")" 2>/dev/null || echo "66")
                ;;
            BORDER_ALPHA)
                local a=$(ini_get "sfwbar.bar_border_alpha" "0.6")
                value=$(printf "%02x" "$(awk "BEGIN{printf \"%d\", $a * 255}")" 2>/dev/null || echo "99")
                ;;

            # Labwc
            CORNER_RADIUS)     value=$(ini_get "labwc.cornerRadius" "8") ;;
            BORDER_WIDTH)      value=$(ini_get "labwc.border_width" "1") ;;
            THEMERC_FONT)      value=$(ini_get "labwc.themerc_font" "sans 10") ;;
            THEMERC_ACTIVE_BG)     value=$(ini_get "labwc.themerc_active_bg" "#313244") ;;
            THEMERC_INACTIVE_BG)   value=$(ini_get "labwc.themerc_inactive_bg" "#181825") ;;
            THEMERC_ACTIVE_TEXT)   value=$(ini_get "labwc.themerc_active_text" "#cdd6f4") ;;
            THEMERC_INACTIVE_TEXT) value=$(ini_get "labwc.themerc_inactive_text" "#6c7086") ;;
            THEMERC_BORDER)    value=$(ini_get "labwc.themerc_border" "#45475a") ;;
            THEMERC_HEIGHT)    value=$(ini_get "labwc.themerc_height" "28") ;;
            TITLEBAR_LAYOUT)   value=$(ini_get "labwc.titlebar_layout" "icon:iconify,max,close") ;;

            # GTK
            GTK_THEME)             value=$(ini_get "gtk3.gtk_theme" "Adwaita-dark") ;;
            ICON_THEME)            value=$(ini_get "gtk3.icon_theme" "Papirus-Dark") ;;
            CURSOR_THEME)          value=$(ini_get "cursor.theme" "Catppuccin-Mocha-Dark") ;;
            CURSOR_SIZE)           value=$(ini_get "cursor.size" "24") ;;
            FONT_INTERFACE)        value=$(ini_get "fonts.interface" "Noto Sans 10") ;;
            FONT_MONOSPACE)        value=$(ini_get "fonts.monospace" "Noto Sans Mono 10") ;;
            GTK_PREFER_DARK)       value=$(ini_get "gtk3.gtk_application_prefer_dark_theme" "true") ;;
            GTK_ENABLE_ANIMATIONS) value=$(ini_get "gtk3.gtk_enable_animations" "true") ;;
            GTK_SHOWS_APP_MENU)    value=$(ini_get "gtk3.gtk_shell_shows_app_menu" "false") ;;
            GTK_SHOWS_MENU_BAR)    value=$(ini_get "gtk3.gtk_shell_shows_menu_bar" "false") ;;
            GTK_MENU_IMAGES)       value=$(ini_get "gtk3.gtk_menu_images" "true") ;;
            GTK_BUTTON_IMAGES)     value=$(ini_get "gtk3.gtk_button_images" "true") ;;
            GTK_TOOLBAR_STYLE)     value=$(ini_get "gtk3.gtk_toolbar_style" "GTK_TOOLBAR_BOTH_HORIZ") ;;
            GTK_DECORATION_LAYOUT) value=$(ini_get "gtk3.gtk_decoration_layout" ":menu") ;;
            XFT_ANTIALIAS)         value=$(ini_get "gtk3.xft_antialias" "1") ;;
            XFT_HINTING)           value=$(ini_get "gtk3.xft_hinting" "1") ;;
            XFT_HINTSTYLE)         value=$(ini_get "gtk3.xft_hintstyle" "hintfull") ;;
            XFT_RGBA)              value=$(ini_get "gtk3.xft_rgba" "rgb") ;;

            # Rofi
            ROFI_BG)           value=$(ini_get "rofi.bg" "#2e3440") ;;
            ROFI_BG_ALT)       value=$(ini_get "rofi.bg_alt" "#3b4252") ;;
            ROFI_FG)           value=$(ini_get "rofi.fg" "#d8dee9") ;;
            ROFI_FG_ALT)       value=$(ini_get "rofi.fg_alt" "#a6adc8") ;;
            ROFI_ACCENT)       value=$(ini_get "rofi.accent" "#81a1c1") ;;
            ROFI_URGENT)       value=$(ini_get "rofi.urgent" "#bf616a") ;;
            ROFI_SELECTED)     value=$(ini_get "rofi.selected" "#434c5e") ;;
            ROFI_BORDER_COLOR) value=$(ini_get "rofi.border_color" "#81a1c1") ;;
            ROFI_BORDER_WIDTH) value=$(ini_get "rofi.border_width" "2") ;;
            ROFI_BORDER_RADIUS)value=$(ini_get "rofi.border_radius" "12") ;;
            ROFI_FONT)         value=$(ini_get "rofi.font" "Noto Sans 12") ;;
            ROFI_ICON_THEME)   value=$(ini_get "rofi.icon_theme" "Papirus-Dark") ;;
            ROFI_TERMINAL)     value=$(ini_get "rofi.terminal" "foot") ;;

            # SFWBar
            FONT_SIZE)         value=$(ini_get "sfwbar.font_size" "12") ;;
            FONT_SIZE_SMALL)   value=$(ini_get "sfwbar.font_size_small" "10") ;;
            MODULE_RADIUS)     value=$(ini_get "sfwbar.module_radius" "5") ;;
            MODULE_PADDING_H)  value=$(ini_get "sfwbar.module_padding_h" "8") ;;
            MODULE_PADDING_V)  value=$(ini_get "sfwbar.module_padding_v" "2") ;;

            # Zebar (uses same font vars as sfwbar)

            # Mako
            MAKO_FONT)            value=$(ini_get "mako.font" "Noto Sans 11") ;;
            MAKO_BG_COLOR)        value=$(ini_get "mako.bg_color" "#313244") ;;
            MAKO_TEXT_COLOR)       value=$(ini_get "mako.text_color" "#cdd6f4") ;;
            MAKO_BORDER_COLOR)    value=$(ini_get "mako.border_color" "#89b4fa") ;;
            MAKO_BORDER_WIDTH)    value=$(ini_get "mako.border_width" "2") ;;
            MAKO_PADDING)         value=$(ini_get "mako.padding" "12") ;;
            MAKO_MAX_WIDTH)       value=$(ini_get "mako.max_width" "350") ;;
            MAKO_DEFAULT_TIMEOUT) value=$(ini_get "mako.default_timeout" "5000") ;;
            MAKO_MARKUP)          value=$(ini_get "mako.markup" "true") ;;
            MAKO_ACTIONS)         value=$(ini_get "mako.actions" "true") ;;
            MAKO_MAX_VISIBLE)     value=$(ini_get "mako.max_visible" "5") ;;

            # Foot
            FOOT_TERM)            value=$(ini_get "foot.term" "foot") ;;
            FOOT_FONT)            value=$(ini_get "foot.font" "Noto Sans Mono:size=11") ;;
            FOOT_DPI)             value=$(ini_get "foot.dpi" "96") ;;
            FOOT_PAD)             value=$(ini_get "foot.pad" "12x12") ;;
            FOOT_SHELL)           value=$(ini_get "foot.shell" "/bin/bash") ;;
            FOOT_FG)              value=$(ini_get "foot.color_foreground" "#cdd6f4") ;;
            FOOT_BG)              value=$(ini_get "foot.color_background" "#1e1e2e") ;;
            FOOT_CURSOR)          value=$(ini_get "foot.color_cursor" "#cdd6f4") ;;
            FOOT_CURSOR_TEXT)     value=$(ini_get "foot.color_cursor_text" "#1e1e2e") ;;
            FOOT_SELECTION)       value=$(ini_get "foot.color_selection" "#45475a") ;;
            FOOT_SELECTION_FG)    value=$(ini_get "foot.color_selection_foreground" "#cdd6f4") ;;
            FOOT_REGULAR_0)       value=$(ini_get "foot.color_regular_0" "#1e1e2e") ;;
            FOOT_REGULAR_1)       value=$(ini_get "foot.color_regular_1" "#f38ba8") ;;
            FOOT_REGULAR_2)       value=$(ini_get "foot.color_regular_2" "#a6e3a1") ;;
            FOOT_REGULAR_3)       value=$(ini_get "foot.color_regular_3" "#f9e2af") ;;
            FOOT_REGULAR_4)       value=$(ini_get "foot.color_regular_4" "#89b4fa") ;;
            FOOT_REGULAR_5)       value=$(ini_get "foot.color_regular_5" "#cba6f7") ;;
            FOOT_REGULAR_6)       value=$(ini_get "foot.color_regular_6" "#94e2d5") ;;
            FOOT_REGULAR_7)       value=$(ini_get "foot.color_regular_7" "#bac2de") ;;
            FOOT_BRIGHT_0)        value=$(ini_get "foot.color_bright_0" "#45475a") ;;
            FOOT_BRIGHT_1)        value=$(ini_get "foot.color_bright_1" "#f38ba8") ;;
            FOOT_BRIGHT_2)        value=$(ini_get "foot.color_bright_2" "#a6e3a1") ;;
            FOOT_BRIGHT_3)        value=$(ini_get "foot.color_bright_3" "#f9e2af") ;;
            FOOT_BRIGHT_4)        value=$(ini_get "foot.color_bright_4" "#89b4fa") ;;
            FOOT_BRIGHT_5)        value=$(ini_get "foot.color_bright_5" "#cba6f7") ;;
            FOOT_BRIGHT_6)        value=$(ini_get "foot.color_bright_6" "#94e2d5") ;;
            FOOT_BRIGHT_7)        value=$(ini_get "foot.color_bright_7" "#cdd6f4") ;;

            # Qt
            QT_ICON_THEME)        value=$(ini_get "qt6ct.icon_theme" "Papirus-Dark") ;;
            QT_COLOR_SCHEME)      value=$(ini_get "qt6ct.color_scheme" "dark") ;;
            QT_STANDARD_DIALOGS)  value=$(ini_get "qt6ct.standard_dialogs" "xdg-desktop-portal") ;;
            QT_FONT)              value=$(ini_get "qt6ct.font" "Noto Sans,10,-1,5,50,0,0,0,0,0") ;;
            QT_MONO_FONT)         value=$(ini_get "qt6ct.mono_font" "Noto Sans Mono,10,-1,5,50,0,0,0,0,0") ;;
            *) ;;
        esac

        content="${content//$placeholder/$value}"
    done

    echo "$content"
}

# ============================================================
# Output paths
# ============================================================

# Maps template name → install destination
declare -A OUTPUT_MAP=(
    [gtk.css.tmpl]="$HOME/.config/gtk-3.0/gtk.css"
    [gtk4.css.tmpl]="$HOME/.config/gtk-4.0/gtk.css"
    [gtk3-settings.ini.tmpl]="$HOME/.config/gtk-3.0/settings.ini"
    [gtk4-settings.ini.tmpl]="$HOME/.config/gtk-4.0/settings.ini"
    [themerc-override.tmpl]="$HOME/.config/labwc/themerc-override"
    [environment.tmpl]="$HOME/.config/labwc/environment"
    [sfwbar.css.tmpl]="$HOME/.config/sfwbar/theme.css"
    [rofi.rasi.tmpl]="$HOME/.config/rofi/config.rasi"
    [mako.ini.tmpl]="$HOME/.config/mako/config"
    [foot.ini.tmpl]="$HOME/.config/foot/foot.ini"
    [qt6ct.conf.tmpl]="$HOME/.config/qt6ct/qt6ct.conf"
)

# Also write zebar CSS to both locations
declare -A ZEBAR_MAP=(
    [zebar.css.tmpl]="$HOME/.glzr/zebar/labwc-zebar/main/style.css"
)

# ============================================================
# Commands
# ============================================================

cmd_list() {
    echo -e "${BOLD}Available themes:${NC}"
    echo ""
    for f in "$THEMES_DIR"/*.ini; do
        [[ -f "$f" ]] || continue
        local name desc
        # Quick parse without full INI load
        name=$(grep -m1 '^name=' "$f" 2>/dev/null | cut -d= -f2- | xargs)
        desc=$(grep -m1 '^description=' "$f" 2>/dev/null | cut -d= -f2- | xargs)
        local base
        base=$(basename "$f" .ini)
        printf "  ${CYAN}%-20s${NC} %s — %s\n" "$base" "${name:-$base}" "${desc:-}"
    done
    echo ""
}

cmd_current() {
    local current_theme="$HOME/.config/labwc/.current-theme"
    if [[ -f "$current_theme" ]]; then
        echo "Active theme: $(cat "$current_theme")"
    else
        echo "No active theme set"
    fi
}

cmd_apply() {
    local theme_file="$1"
    [[ -f "$theme_file" ]] || fail "Theme not found: $theme_file"

    local theme_name
    theme_name=$(basename "$theme_file" .ini)

    echo -e "${BOLD}Applying theme: $theme_name${NC}"
    echo ""

    # Parse and expand
    parse_ini "$theme_file"
    expand_vars

    local applied=0

    # GTK CSS (same for GTK3 and GTK4)
    local gtk_css
    gtk_css=$(render_template "$TEMPLATES_DIR/gtk.css.tmpl")
    if [[ -n "$gtk_css" ]]; then
        echo "$gtk_css" > "$HOME/.config/gtk-3.0/gtk.css"
        echo "$gtk_css" > "$HOME/.config/gtk-4.0/gtk.css"
        pass "gtk.css (GTK3 + GTK4)"
        ((applied++))
    fi

    # GTK3 settings.ini
    local gtk3_ini
    gtk3_ini=$(render_template "$TEMPLATES_DIR/gtk3-settings.ini.tmpl")
    if [[ -n "$gtk3_ini" ]]; then
        echo "$gtk3_ini" > "$HOME/.config/gtk-3.0/settings.ini"
        pass "GTK3 settings.ini"
        ((applied++))
    fi

    # GTK4 settings.ini
    local gtk4_ini
    gtk4_ini=$(render_template "$TEMPLATES_DIR/gtk4-settings.ini.tmpl")
    if [[ -n "$gtk4_ini" ]]; then
        echo "$gtk4_ini" > "$HOME/.config/gtk-4.0/settings.ini"
        pass "GTK4 settings.ini"
        ((applied++))
    fi

    # Labwc themerc-override
    local themerc
    themerc=$(render_template "$TEMPLATES_DIR/themerc-override.tmpl")
    if [[ -n "$themerc" ]]; then
        echo "$themerc" > "$HOME/.config/labwc/themerc-override"
        pass "labwc themerc-override"
        ((applied++))
    fi

    # Labwc environment (cursor only)
    local env_file
    env_file=$(render_template "$TEMPLATES_DIR/environment.tmpl")
    if [[ -n "$env_file" ]]; then
        echo "$env_file" > "$HOME/.config/labwc/environment"
        pass "labwc environment"
        ((applied++))
    fi

    # SFWBar CSS
    local sfwbar_css
    sfwbar_css=$(render_template "$TEMPLATES_DIR/sfwbar.css.tmpl")
    if [[ -n "$sfwbar_css" ]]; then
        mkdir -p "$HOME/.config/sfwbar"
        echo "$sfwbar_css" > "$HOME/.config/sfwbar/theme.css"
        pass "sfwbar theme.css"
        ((applied++))
    fi

    # Rofi config
    local rofi_cfg
    rofi_cfg=$(render_template "$TEMPLATES_DIR/rofi.rasi.tmpl")
    if [[ -n "$rofi_cfg" ]]; then
        mkdir -p "$HOME/.config/rofi"
        echo "$rofi_cfg" > "$HOME/.config/rofi/config.rasi"
        pass "rofi config.rasi"
        ((applied++))
    fi

    # Zebar CSS
    local zebar_css
    zebar_css=$(render_template "$TEMPLATES_DIR/zebar.css.tmpl")
    if [[ -n "$zebar_css" ]]; then
        mkdir -p "$HOME/.glzr/zebar/labwc-zebar/main"
        echo "$zebar_css" > "$HOME/.glzr/zebar/labwc-zebar/main/style.css"
        pass "zebar style.css"
        ((applied++))
    fi

    # Mako
    local mako_cfg
    mako_cfg=$(render_template "$TEMPLATES_DIR/mako.ini.tmpl")
    if [[ -n "$mako_cfg" ]]; then
        mkdir -p "$HOME/.config/mako"
        echo "$mako_cfg" > "$HOME/.config/mako/config"
        pass "mako config"
        ((applied++))
    fi

    # Foot
    local foot_cfg
    foot_cfg=$(render_template "$TEMPLATES_DIR/foot.ini.tmpl")
    if [[ -n "$foot_cfg" ]]; then
        mkdir -p "$HOME/.config/foot"
        echo "$foot_cfg" > "$HOME/.config/foot/foot.ini"
        pass "foot foot.ini"
        ((applied++))
    fi

    # Qt6ct
    local qt6ct_cfg
    qt6ct_cfg=$(render_template "$TEMPLATES_DIR/qt6ct.conf.tmpl")
    if [[ -n "$qt6ct_cfg" ]]; then
        mkdir -p "$HOME/.config/qt6ct"
        echo "$qt6ct_cfg" > "$HOME/.config/qt6ct/qt6ct.conf"
        pass "qt6ct config"
        ((applied++))
    fi

    # Apply font size via font-scale if it exists
    if command -v font-scale &>/dev/null; then
        local font_size
        font_size=$(ini_get "fonts.interface" "Noto Sans 10" | grep -oE '[0-9]+$' || echo "10")
        # Don't call font-scale here — let the user do it separately
    fi

    # Sync GTK settings to gsettings (within labwc session only)
    if [[ "$XDG_CURRENT_DESKTOP" == "labwc" ]] && command -v gsettings &>/dev/null; then
        local gt
        gt=$(ini_get "gtk3.gtk_theme" "")
        local it
        it=$(ini_get "gtk3.icon_theme" "")
        local ct
        ct=$(ini_get "cursor.theme" "")
        local fi
        fi=$(ini_get "fonts.interface" "")
        [[ -n "$gt" ]] && gsettings set org.gnome.desktop.interface gtk-theme "$gt" 2>/dev/null || true
        [[ -n "$it" ]] && gsettings set org.gnome.desktop.interface icon-theme "$it" 2>/dev/null || true
        [[ -n "$ct" ]] && gsettings set org.gnome.desktop.interface cursor-theme "$ct" 2>/dev/null || true
        [[ -n "$fi" ]] && gsettings set org.gnome.desktop.interface font-name "$fi" 2>/dev/null || true
        pass "gsettings synced"
    fi

    # Record active theme
    echo "$theme_name" > "$HOME/.config/labwc/.current-theme"

    # Signal labwc to reload
    if pidof labwc &>/dev/null; then
        kill -SIGHUP "$(pidof labwc)" 2>/dev/null && \
            pass "labwc reloaded" || warn "labwc reload failed"
    fi

    # Restart sfwbar
    if pidof sfwbar &>/dev/null; then
        killall sfwbar 2>/dev/null
        sleep 0.3
        sfwbar &>/dev/null &
        disown
        pass "sfwbar restarted"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Theme applied: $theme_name${NC} ($applied files)"
    echo -e "${DIM}Some changes take effect on next app launch.${NC}"
}

cmd_export() {
    local theme_file="$1"
    [[ -f "$theme_file" ]] || fail "Theme not found: $theme_file"

    local theme_name
    theme_name=$(basename "$theme_file" .ini)

    echo -e "${BOLD}Exporting theme to dotfiles/: $theme_name${NC}"
    echo ""

    parse_ini "$theme_file"
    expand_vars

    mkdir -p "$DOTFILES_DIR/gtk"
    mkdir -p "$DOTFILES_DIR/labwc"
    mkdir -p "$DOTFILES_DIR/sfwbar"
    mkdir -p "$DOTFILES_DIR/rofi"
    mkdir -p "$DOTFILES_DIR/mako"
    mkdir -p "$DOTFILES_DIR/foot"

    local gtk_css
    gtk_css=$(render_template "$TEMPLATES_DIR/gtk.css.tmpl")
    echo "$gtk_css" > "$DOTFILES_DIR/gtk/gtk.css"

    local gtk3_ini
    gtk3_ini=$(render_template "$TEMPLATES_DIR/gtk3-settings.ini.tmpl")
    echo "$gtk3_ini" > "$DOTFILES_DIR/gtk/gtk3-settings.ini"

    local gtk4_ini
    gtk4_ini=$(render_template "$TEMPLATES_DIR/gtk4-settings.ini.tmpl")
    echo "$gtk4_ini" > "$DOTFILES_DIR/gtk/gtk4-settings.ini"

    local themerc
    themerc=$(render_template "$TEMPLATES_DIR/themerc-override.tmpl")
    echo "$themerc" > "$DOTFILES_DIR/labwc/themerc-override"

    local env_file
    env_file=$(render_template "$TEMPLATES_DIR/environment.tmpl")
    echo "$env_file" > "$DOTFILES_DIR/labwc/environment"

    local sfwbar_css
    sfwbar_css=$(render_template "$TEMPLATES_DIR/sfwbar.css.tmpl")
    echo "$sfwbar_css" > "$DOTFILES_DIR/sfwbar/theme.css"

    local rofi_cfg
    rofi_cfg=$(render_template "$TEMPLATES_DIR/rofi.rasi.tmpl")
    echo "$rofi_cfg" > "$DOTFILES_DIR/rofi/config.rasi"

    local mako_cfg
    mako_cfg=$(render_template "$TEMPLATES_DIR/mako.ini.tmpl")
    echo "$mako_cfg" > "$DOTFILES_DIR/mako/config"

    local foot_cfg
    foot_cfg=$(render_template "$TEMPLATES_DIR/foot.ini.tmpl")
    echo "$foot_cfg" > "$DOTFILES_DIR/foot/foot.ini"

    local qt6ct_cfg
    qt6ct_cfg=$(render_template "$TEMPLATES_DIR/qt6ct.conf.tmpl")
    echo "$qt6ct_cfg" > "$DOTFILES_DIR/qt6ct/qt6ct.conf"

    pass "Exported to $DOTFILES_DIR/"
}

cmd_preview() {
    local theme_file="$1"
    [[ -f "$theme_file" ]] || fail "Theme not found: $theme_file"

    parse_ini "$theme_file"
    expand_vars

    echo -e "${BOLD}Preview: $(basename "$theme_file" .ini)${NC}"
    echo ""

    for tmpl in "$TEMPLATES_DIR"/*.tmpl; do
        [[ -f "$tmpl" ]] || continue
        local name
        name=$(basename "$tmpl" .tmpl)
        echo -e "${CYAN}--- $name ---${NC}"
        render_template "$tmpl" | head -5
        echo -e "${DIM}  ... ($(render_template "$tmpl" | wc -l) lines)${NC}"
        echo ""
    done
}

# ============================================================
# Main
# ============================================================

usage() {
    echo -e "${BOLD}theme-engine${NC} — Generate all configs from theme INI profiles"
    echo ""
    echo "Usage:"
    echo "  theme-engine list                  List available themes"
    echo "  theme-engine current               Show active theme"
    echo "  theme-engine apply <theme.ini>     Apply theme (generate + install)"
    echo "  theme-engine preview <theme.ini>   Preview generated output"
    echo "  theme-engine export <theme.ini>    Export to dotfiles/ directory"
    echo ""
    echo "Examples:"
    echo "  theme-engine list"
    echo "  theme-engine apply $THEMES_DIR/catppuccin-mocha.ini"
    echo "  theme-engine export $THEMES_DIR/catppuccin-mocha.ini"
}

case "${1:-}" in
    list)    cmd_list ;;
    current) cmd_current ;;
    apply)   [[ -n "${2:-}" ]] || fail "Usage: theme-engine apply <theme.ini>"; cmd_apply "$2" ;;
    preview) [[ -n "${2:-}" ]] || fail "Usage: theme-engine preview <theme.ini>"; cmd_preview "$2" ;;
    export)  [[ -n "${2:-}" ]] || fail "Usage: theme-engine export <theme.ini>"; cmd_export "$2" ;;
    -h|--help|help) usage ;;
    *) usage; exit 1 ;;
esac
