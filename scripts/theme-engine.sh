#!/bin/bash
#
# theme-engine — Generate all config files from a theme INI profile
#
# Usage:
#   theme-engine apply <theme.ini> [--profile standard|full]   Apply theme and set profile
#   theme-engine preview <theme.ini>                           Show what would be generated
#   theme-engine list                        List available themes
#   theme-engine current                     Show active theme
#   theme-engine export <theme.ini>          Export generated files to dotfiles/
#
# Themes are INI files in themes/ with sections:
#   [meta], [colors], [labwc], [gtk3], [gtk4], [fonts],
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info() { echo -e "  ${CYAN}→${NC} $1" >&2; }
pass()  { echo -e "  ${GREEN}✓${NC} $1" >&2; }
fail()  { echo -e "  ${RED}✗${NC} $1" >&2; exit 1; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $*" >&2; }

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
    for ((depth=1; depth<=max_depth; depth++)); do
        local changed
        changed=false
        for key in "${!INI_VALUES[@]}"; do
            local val="${INI_VALUES[$key]}"
            local new_val="$val"

            # Replace ${section.key} or ${key} references (defaulting to colors.key)
            local regex='\$\{([a-zA-Z0-9_]+)(\.[a-zA-Z0-9_]+)?\}'
            while [[ "$new_val" =~ $regex ]]; do
                local ref_part1="${BASH_REMATCH[1]}"
                local ref_part2="${BASH_REMATCH[2]:-}"
                
                local ref_section
                local ref_key
                
                if [[ -z "$ref_part2" ]]; then
                    # No dot, assume colors section
                    ref_section="colors"
                    ref_key="$ref_part1"
                else
                    # Has dot, e.g. section.key
                    ref_section="$ref_part1"
                    ref_key="${ref_part2#.}"
                fi
                
                local ref_val="${INI_VALUES[${ref_section}.${ref_key}]:-}"

                if [[ -n "$ref_val" ]]; then
                    if [[ -z "$ref_part2" ]]; then
                        new_val="${new_val//\$\{${ref_key}\}/$ref_val}"
                    else
                        new_val="${new_val//\$\{${ref_section}.${ref_key}\}/$ref_val}"
                    fi
                    changed=true
                else
                    warn "Undefined reference: \${${ref_section}.${ref_key}} in $key"
                    break # prevent infinite loop on undefined reference
                fi
            done

            if [[ "$new_val" != "$val" ]]; then
                INI_VALUES["$key"]="$new_val"
            fi
        done

        if [[ "$changed" == false ]]; then
            break
        fi
    done
}

# ============================================================
# Template Rendering
# ============================================================

render_template() {
    local template_file="$1"
    local content=""

    [[ -f "$template_file" ]] || warn "Template not found: $template_file"
    content="$(<"$template_file")"

    # Replace {{VARIABLE}} references
    local tpl_regex='\{\{([A-Z_][A-Z0-9_]+)\}\}'
    while [[ "$content" =~ $tpl_regex ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value=""

                case "$var_name" in
                    THEME_NAME)      var_value=$(ini_get "meta.name" "$(basename "${theme_file:-$template_file}" .ini)" ) ;;
                    COLOR_BG)        var_value=$(ini_get "colors.bg" "#1e1e2e") ;;
                    COLOR_FG)        var_value=$(ini_get "colors.fg" "#cdd6f4") ;;
                    COLOR_SURFACE)   var_value=$(ini_get "colors.surface" "#1e1e2e") ;;
                    COLOR_BORDER)    var_value=$(ini_get "colors.border" "#45475a") ;;
                    COLOR_ACCENT)    var_value=$(ini_get "colors.accent" "#89b4fa") ;;
                    COLOR_URGENT)     var_value=$(ini_get "colors.urgent" "#f38ba8") ;;
                    COLOR_OK)         var_value=$(ini_get "colors.ok" "#a6e3a1") ;;
                    COLOR_MUTED)     var_value=$(ini_get "colors.muted" "#a6adc8") ;;
                    OCWS_BLUR)       var_value=$(ini_get "ocws.blur" "5") ;;
                    OCWS_BORDER)     var_value=$(ini_get "ocws.border" "1") ;;
                    OCWS_RADIUS)     var_value=$(ini_get "ocws.radius" "8") ;;
                    OCWS_SHADOW)     var_value=$(ini_get "ocws.shadow" "4") ;;
                    ICON_THEME)      var_value=$(ini_get "gtk3.icon_theme" "elementary") ;;
                    FONT_MONO)       var_value=$(ini_get "fonts.mono" "Noto Sans Mono CJK SC:hilight=Filled") ;;
                    THEMERC_FONT)        var_value=$(ini_get "labwc.themerc_font" "sans 10") ;;
                    THEMERC_ACTIVE_BG)   var_value=$(ini_get "labwc.themerc_active_bg" "#1e1e2e") ;;
                    THEMERC_ACTIVE_TEXT) var_value=$(ini_get "labwc.themerc_active_text" "#cdd6f4") ;;
                    THEMERC_INACTIVE_BG) var_value=$(ini_get "labwc.themerc_inactive_bg" "#181825") ;;
                    THEMERC_INACTIVE_TEXT) var_value=$(ini_get "labwc.themerc_inactive_text" "#a6adc8") ;;
                    BORDER_WIDTH)        var_value=$(ini_get "labwc.border_width" "1") ;;
                    THEMERC_BORDER)      var_value=$(ini_get "labwc.themerc_border" "#45475a") ;;
                    THEMERC_HEIGHT)      var_value=$(ini_get "labwc.themerc_height" "28") ;;
                    OSD_BG)              var_value=$(ini_get "labwc.osd_bg" "#1e1e2e") ;;
                    OSD_BORDER)          var_value=$(ini_get "labwc.osd_border" "#45475a") ;;
                    OSD_TEXT)            var_value=$(ini_get "labwc.osd_text" "#cdd6f4") ;;
                    OSD_ACCENT)          var_value=$(ini_get "labwc.osd_accent" "#89b4fa") ;;
                    OSD_INACTIVE)        var_value=$(ini_get "labwc.osd_inactive" "#6c7086") ;;
                    TITLEBAR_LAYOUT)     var_value=$(ini_get "labwc.titlebar_layout" "icon:iconify,max,close") ;;
                    *)
                        if [[ "$var_name" == FOOT_* ]]; then
                            local foot_key="${var_name#FOOT_}"
                            foot_key="${foot_key,,}"
                            # Map FOOT vars to colors section (foot uses bare hex, no #)
                            case "$foot_key" in
                                fg)            var_value=$(ini_get "colors.text" "#cdd6f4") ;;
                                bg)            var_value=$(ini_get "colors.base" "#1e1e2e") ;;
                                cursor_fg)     var_value=$(ini_get "colors.text" "#cdd6f4") ;;
                                cursor_bg)     var_value=$(ini_get "colors.base" "#1e1e2e") ;;
                                selection_bg)  var_value=$(ini_get "colors.surface1" "#45475a") ;;
                                selection_fg)  var_value=$(ini_get "colors.text" "#cdd6f4") ;;
                                regular_0)     var_value=$(ini_get "colors.base" "#1e1e2e") ;;
                                regular_1)     var_value=$(ini_get "colors.red" "#f38ba8") ;;
                                regular_2)     var_value=$(ini_get "colors.green" "#a6e3a1") ;;
                                regular_3)     var_value=$(ini_get "colors.yellow" "#f9e2af") ;;
                                regular_4)     var_value=$(ini_get "colors.blue" "#89b4fa") ;;
                                regular_5)     var_value=$(ini_get "colors.mauve" "#cba6f7") ;;
                                regular_6)     var_value=$(ini_get "colors.teal" "#94e2d5") ;;
                                regular_7)     var_value=$(ini_get "colors.subtext1" "#bac2de") ;;
                                bright_0)      var_value=$(ini_get "colors.surface1" "#45475a") ;;
                                bright_1)      var_value=$(ini_get "colors.red" "#f38ba8") ;;
                                bright_2)      var_value=$(ini_get "colors.green" "#a6e3a1") ;;
                                bright_3)      var_value=$(ini_get "colors.yellow" "#f9e2af") ;;
                                bright_4)      var_value=$(ini_get "colors.blue" "#89b4fa") ;;
                                bright_5)      var_value=$(ini_get "colors.mauve" "#cba6f7") ;;
                                bright_6)      var_value=$(ini_get "colors.teal" "#94e2d5") ;;
                                bright_7)      var_value=$(ini_get "colors.text" "#cdd6f4") ;;
                                font)
                                    local raw_font
                                    raw_font=$(ini_get "fonts.monospace" "Noto Sans Mono 10")
                                    # Convert "Family Size" to "Family:size=Size" for foot
                                    raw_font="${raw_font%% }"
                                    if [[ "$raw_font" =~ ^(.+)[[:space:]]([0-9]+)$ ]]; then
                                        var_value="${BASH_REMATCH[1]}:size=${BASH_REMATCH[2]}"
                                    else
                                        var_value="$raw_font"
                                    fi
                                    ;;
                                term)          var_value="xterm-256color" ;;
                                pad)           var_value="12x12" ;;
                                shell)         var_value="/bin/bash" ;;
                                *)             var_value="" ;;
                            esac
                            # Foot uses bare hex without # prefix
                            if [[ "$foot_key" =~ ^(fg|bg|cursor_fg|cursor_bg|selection_bg|selection_fg|regular_[0-7]|bright_[0-7])$ ]]; then
                                var_value="${var_value#\#}"
                            fi
                        elif [[ "$var_name" == ROFI_* ]]; then
                            local key="${var_name#ROFI_}"
                            key="${key,,}"
                            case "$key" in
                                bg)             var_value=$(ini_get "colors.bg" "#1e1e2e") ;;
                                bg_alt)         var_value=$(ini_get "colors.surface" "#313244") ;;
                                fg)             var_value=$(ini_get "colors.fg" "#cdd6f4") ;;
                                fg_alt)         var_value=$(ini_get "colors.muted" "#a6adc8") ;;
                                accent)         var_value=$(ini_get "colors.accent" "#89b4fa") ;;
                                urgent)         var_value=$(ini_get "colors.urgent" "#f38ba8") ;;
                                error)          var_value=$(ini_get "colors.urgent" "#f38ba8") ;;
                                selected)       var_value=$(ini_get "colors.surface" "#45475a") ;;
                                border_width)   var_value=$(ini_get "ocws.border" "2") ;;
                                border_radius)  var_value=$(ini_get "ocws.radius" "8") ;;
                                icon_theme)     var_value=$(ini_get "gtk3.icon_theme" "Papirus-Dark") ;;
                                font)           var_value=$(ini_get "fonts.interface" "Noto Sans 10") ;;
                                terminal)       var_value="foot" ;;
                                *)              var_value=$(ini_get "rofi.${key}" "") ;;
                            esac
                        elif [[ "$var_name" == FUZZEL_* ]]; then
                            local key="${var_name#FUZZEL_}"
                            key="${key,,}"
                            case "$key" in
                                bg)             var_value=$(ini_get "colors.bg" "#1e1e2e") ;;
                                fg)             var_value=$(ini_get "colors.fg" "#cdd6f4") ;;
                                fg_alt)         var_value=$(ini_get "colors.muted" "#a6adc8") ;;
                                accent)         var_value=$(ini_get "colors.accent" "#89b4fa") ;;
                                urgent)         var_value=$(ini_get "colors.urgent" "#f38ba8") ;;
                                selected)       var_value=$(ini_get "colors.surface" "#45475a") ;;
                                border_color)   var_value=$(ini_get "colors.border" "#45475a") ;;
                                border_width)   var_value=$(ini_get "ocws.border" "2") ;;
                                border_radius)  var_value=$(ini_get "ocws.radius" "8") ;;
                                icon_theme)     var_value=$(ini_get "gtk3.icon_theme" "Papirus-Dark") ;;
                                font)           var_value=$(ini_get "fonts.interface" "Noto Sans 10") ;;
                                prompt)         var_value="\"> \"" ;;
                                placeholder)    var_value="Search..." ;;
                                width)          var_value="40" ;;
                                lines)          var_value="10" ;;
                                hpad)           var_value="20" ;;
                                vpad)           var_value="20" ;;
                                *)              var_value=$(ini_get "fuzzel.${key}" "") ;;
                            esac
                        elif [[ "$var_name" == MAKO_* ]]; then
                            local key="${var_name#MAKO_}"
                            key="${key,,}"
                            case "$key" in
                                bg)             var_value=$(ini_get "colors.bg" "#1e1e2e") ;;
                                text)           var_value=$(ini_get "colors.fg" "#cdd6f4") ;;
                                border)         var_value=$(ini_get "colors.accent" "#89b4fa") ;;
                                border_size)    var_value=$(ini_get "ocws.border" "2") ;;
                                border_radius)  var_value=$(ini_get "ocws.radius" "8") ;;
                                font)           var_value=$(ini_get "fonts.interface" "Noto Sans 10") ;;
                                width)          var_value="350" ;;
                                max_visible)    var_value="5" ;;
                                default_timeout) var_value="5000" ;;
                                *)              var_value=$(ini_get "mako.${key}" "") ;;
                            esac
                        elif [[ "$var_name" == CONTOUR_* ]]; then
                            local key="${var_name#CONTOUR_}"
                            key="${key,,}"
                            # Map CONTOUR vars to colors section
                            case "$key" in
                                bg)              var_value=$(ini_get "colors.base" "#1e1e2e") ;;
                                fg)              var_value=$(ini_get "colors.text" "#cdd6f4") ;;
                                bright_fg)       var_value="#ffffff" ;;
                                dim_fg)          var_value=$(ini_get "colors.overlay0" "#6c7086") ;;
                                accent)          var_value=$(ini_get "colors.blue" "#89b4fa") ;;
                                urgent)          var_value=$(ini_get "colors.red" "#f38ba8") ;;
                                surface)         var_value=$(ini_get "colors.surface1" "#45475a") ;;
                                muted)           var_value=$(ini_get "colors.overlay0" "#6c7086") ;;
                                selection)       var_value=$(ini_get "colors.surface1" "#45475a") ;;
                                hyperlink_normal) var_value=$(ini_get "colors.yellow" "#f9e2af") ;;
                                hyperlink_hover)  var_value=$(ini_get "colors.red" "#f38ba8") ;;
                                font_family)     var_value=$(ini_get "fonts.monospace" "Noto Sans Mono") ;;
                                font_size)       var_value="11" ;;
                                profile_name)    var_value="terminal" ;;
                                normal_0)  var_value=$(ini_get "colors.surface1" "#45475a") ;;
                                normal_1)  var_value=$(ini_get "colors.red" "#f38ba8") ;;
                                normal_2)  var_value=$(ini_get "colors.green" "#a6e3a1") ;;
                                normal_3)  var_value=$(ini_get "colors.yellow" "#f9e2af") ;;
                                normal_4)  var_value=$(ini_get "colors.blue" "#89b4fa") ;;
                                normal_5)  var_value=$(ini_get "colors.mauve" "#cba6f7") ;;
                                normal_6)  var_value=$(ini_get "colors.teal" "#94e2d5") ;;
                                normal_7)  var_value=$(ini_get "colors.subtext1" "#bac2de") ;;
                                bright_0)  var_value=$(ini_get "colors.surface2" "#585b70") ;;
                                bright_1)  var_value=$(ini_get "colors.red" "#f38ba8") ;;
                                bright_2)  var_value=$(ini_get "colors.green" "#a6e3a1") ;;
                                bright_3)  var_value=$(ini_get "colors.yellow" "#f9e2af") ;;
                                bright_4)  var_value=$(ini_get "colors.blue" "#89b4fa") ;;
                                bright_5)  var_value=$(ini_get "colors.mauve" "#cba6f7") ;;
                                bright_6)  var_value=$(ini_get "colors.teal" "#94e2d5") ;;
                                bright_7)  var_value=$(ini_get "colors.text" "#cdd6f4") ;;
                                *) var_value="" ;;
                            esac
                        elif [[ "$var_name" == TMUX_* ]]; then
                            local key="${var_name#TMUX_}"
                            key="${key,,}"
                            case "$key" in
                                status_bg)    var_value=$(ini_get "tmux.status_bg" "#1e1e2e") ;;
                                status_fg)    var_value=$(ini_get "tmux.status_fg" "#cdd6f4") ;;
                                accent)       var_value=$(ini_get "tmux.accent" "#89b4fa") ;;
                                accent_fg)    var_value=$(ini_get "tmux.accent_fg" "#1e1e2e") ;;
                                *) var_value="" ;;
                            esac
                        elif [[ "$var_name" == QT_* ]]; then
                            local key="${var_name#QT_}"
                            var_value=$(ini_get "qt6ct.${key,,}" "")
                        elif [[ "$var_name" == GTK_* ]]; then
                            local key="${var_name#GTK_}"
                            if [[ "$key" == PREFER_DARK ]]; then key="application_prefer_dark_theme"; fi
                            if [[ "$key" == SHOWS_APP_MENU ]]; then key="shell_shows_app_menu"; fi
                            if [[ "$key" == SHOWS_MENU_BAR ]]; then key="shell_shows_menu_bar"; fi
                            var_value=$(ini_get "gtk3.gtk_${key,,}" "")
                            if [[ -z "$var_value" ]]; then var_value=$(ini_get "gtk3.${key,,}" ""); fi
                        elif [[ "$var_name" == XFT_* ]]; then
                            local key="${var_name,,}"
                            var_value=$(ini_get "gtk3.${key}" "")
                        elif [[ "$var_name" == FONT_* ]]; then
                            local key="${var_name#FONT_}"
                            var_value=$(ini_get "fonts.${key,,}" "")
                        elif [[ "$var_name" == CURSOR_* ]]; then
                            local key="${var_name#CURSOR_}"
                            var_value=$(ini_get "cursor.${key,,}" "")
                        elif [[ "$var_name" == COLOR_* ]]; then
                            local key="${var_name#COLOR_}"
                            var_value=$(ini_get "colors.${key,,}" "")
                        elif [[ "$var_name" == BG_ALPHA || "$var_name" == SURFACE_ALPHA || "$var_name" == BORDER_ALPHA ]]; then
                            :
                        elif [[ "$var_name" == FONT_SIZE || "$var_name" == FONT_SIZE_SMALL || "$var_name" == FONT_SIZE_LARGE || "$var_name" == MODULE_* ]]; then
                            var_value=$(ini_get "sfwbar.${var_name,,}" "")
                            if [[ -z "$var_value" ]]; then
                                case "${var_name,,}" in
                                    font_size)       var_value="12px" ;;
                                    font_size_small) var_value="11px" ;;
                                    font_size_large) var_value="13px" ;;
                                    module_font_family) var_value="'FiraCode Nerd Font','Noto Sans','DejaVu Sans',sans-serif" ;;
                                esac
                            fi
                        elif [[ "$var_name" == CORNER_RADIUS ]]; then
                            var_value=$(ini_get "labwc.cornerRadius" "8")
                        elif [[ "$var_name" == DMS_* ]]; then
                            local key="${var_name#DMS_}"
                            key="${key,,}"
                            case "$key" in
                                theme_name)         var_value=$(ini_get "dms.theme_name" "blue") ;;
                                matugen_scheme)     var_value=$(ini_get "dms.matugen_scheme" "scheme-tonal-spot") ;;
                                corner_radius)      var_value=$(ini_get "labwc.cornerRadius" "12") ;;
                                popup_transparency) var_value=$(ini_get "dms.popup_transparency" "1") ;;
                                dock_transparency)  var_value=$(ini_get "dms.dock_transparency" "1") ;;
                                blur_enabled)       var_value=$(ini_get "dms.blur_enabled" "false") ;;
                                blur_border_color)  var_value=$(ini_get "colors.overlay0" "#6c7086") ;;
                                icon_theme)         var_value=$(ini_get "gtk3.icon_theme" "Papirus-Dark") ;;
                                cursor_theme)       var_value=$(ini_get "cursor.theme" "Catppuccin-Mocha-Dark") ;;
                                cursor_size)        var_value=$(ini_get "cursor.size" "24") ;;
                                font_family)        var_value=$(ini_get "fonts.interface" "Noto Sans") ;;
                                mono_font)          var_value=$(ini_get "fonts.monospace" "Noto Sans Mono") ;;
                                *) var_value="" ;;
                            esac
                        elif [[ "$var_name" == NOCTALIA_* ]]; then
                            local key="${var_name#NOCTALIA_}"
                            key="${key,,}"
                            case "$key" in
                                dock_pinned) var_value='["org.gnome.Software","blender","org.inkscape.Inkscape","drawio","org.kde.dolphin","org.gnome.Nautilus","chromium_chromium","code","com.mitchellh.ghostty","firefox_firefox","brave-browser","foot"]' ;;
                                location)   var_value=$(ini_get "noctalia.location" "Madiun, East Java") ;;
                                *) var_value="" ;;
                            esac
                        else
                            warn "Unknown template variable: {{$var_name}}"
                        fi
                        ;;
        esac

        # Always replace to prevent infinite loops on empty/unknown variables
        # Use case defaults as fallback when var_value is empty
        if [[ -z "$var_value" ]]; then
            case "$var_name" in
                COLOR_BG)      var_value="#1e1e2e" ;;
                COLOR_FG)      var_value="#cdd6f4" ;;
                COLOR_SURFACE) var_value="#1e1e2e" ;;
                COLOR_BORDER)  var_value="#45475a" ;;
                COLOR_ACCENT)  var_value="#89b4fa" ;;
                COLOR_URGENT)  var_value="#f38ba8" ;;
                COLOR_OK)      var_value="#a6e3a1" ;;
                COLOR_MUTED)   var_value="#a6adc8" ;;
                COLOR_*)       var_value="#1e1e2e" ;;
                OCWS_BLUR)     var_value="5" ;;
                OCWS_BORDER)   var_value="1" ;;
                OCWS_RADIUS)   var_value="8" ;;
                OCWS_SHADOW)   var_value="4" ;;
                ICON_THEME)    var_value="elementary" ;;
                FONT_INTERFACE) var_value="Noto Sans" ;;
            esac
        fi
        content="${content//\{\{$var_name\}\}/$var_value}"
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
    [gtk2-rc.tmpl]="$HOME/.gtkrc-2.0"
    [gtk3-settings.ini.tmpl]="$HOME/.config/gtk-3.0/settings.ini"
    [gtk4-settings.ini.tmpl]="$HOME/.config/gtk-4.0/settings.ini"
    [themerc-override.tmpl]="$HOME/.config/labwc/themerc-override"
    [environment.tmpl]="$HOME/.config/labwc/environment"
    [sfwbar.css.tmpl]="$HOME/.config/ocws/css/theme.css"
    [tokens.css.tmpl]="$HOME/.config/ocws/css/tokens.css"
    [rofi.rasi.tmpl]="$HOME/.config/rofi/config.rasi"
    [fuzzel.ini.tmpl]="$HOME/.config/fuzzel/fuzzel.ini"
    [mako.ini.tmpl]="$HOME/.config/mako/config"
    [foot.ini.tmpl]="$HOME/.config/foot/foot.ini"
    [contour.yml.tmpl]="$HOME/.config/contour/contour.yml"
    [crystal-dock-appearance.conf.tmpl]="$HOME/.config/crystal-dock/appearance.conf"
    [tmux.conf.tmpl]="$HOME/.tmux.conf"
    [qt6ct.conf.tmpl]="$HOME/.config/qt6ct/qt6ct.conf"
    [dms-settings.json.tmpl]="$HOME/.config/DankMaterialShell/settings.json"
    [noctalia.toml.tmpl]="$HOME/.config/noctalia/config.toml"
    [firefox-userChrome.css.tmpl]="$HOME/.config/ocws/firefox/userChrome.css"
    [ocws.css.tmpl]="$HOME/.config/ocws/css/ocws.css"
    [spicetify.ini.tmpl]="$HOME/.config/spicetify/Themes/OCWS/color.ini"
    [vencord.css.tmpl]="$HOME/.config/vesktop/settings/quickCss.css"
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
    local theme_file=""
    local profile="full"
    local labwc_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)
                profile="$2"
                shift 2
                ;;
            --labwc-only)
                labwc_only=true
                shift
                ;;
            *)
                theme_file="$1"
                shift
                ;;
        esac
    done

    [[ -n "$theme_file" ]] || fail "No theme specified"
    [[ -f "$theme_file" ]] || fail "Theme not found: $theme_file"

    local theme_name
    theme_name=$(basename "$theme_file" .ini)

    echo -e "${BOLD}Applying theme: $theme_name (Profile: $profile)${NC}"
    echo ""

    # Parse and expand
    parse_ini "$theme_file"
    expand_vars

    local applied=0

    if [[ "$labwc_only" == false ]]; then
    # GTK CSS (same for GTK3 and GTK4)
    mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
    local gtk_css
    gtk_css=$(render_template "$TEMPLATES_DIR/gtk.css.tmpl")
    if [[ -n "$gtk_css" ]]; then
        echo "$gtk_css" > "$HOME/.config/gtk-3.0/gtk.css"
        echo "$gtk_css" > "$HOME/.config/gtk-4.0/gtk.css"
        pass "gtk.css (GTK3 + GTK4)"
        applied=$((applied + 1))
    fi

    # Shared color tokens must live next to gtk.css or @ocws_* is undefined
    local gtk_tokens
    gtk_tokens=$(render_template "$TEMPLATES_DIR/tokens.css.tmpl")
    if [[ -n "$gtk_tokens" ]]; then
        echo "$gtk_tokens" > "$HOME/.config/gtk-3.0/tokens.css"
        echo "$gtk_tokens" > "$HOME/.config/gtk-4.0/tokens.css"
        pass "gtk tokens.css (GTK3 + GTK4)"
        applied=$((applied + 1))
    fi

    # GTK2 settings
    local gtk2_ini
    gtk2_ini=$(render_template "$TEMPLATES_DIR/gtk2-rc.tmpl")
    if [[ -n "$gtk2_ini" ]]; then
        echo "$gtk2_ini" > "$HOME/.gtkrc-2.0"
        pass "GTK2 .gtkrc-2.0"
        applied=$((applied + 1))
    fi

    # GTK3 settings.ini
    local gtk3_ini
    gtk3_ini=$(render_template "$TEMPLATES_DIR/gtk3-settings.ini.tmpl")
    if [[ -n "$gtk3_ini" ]]; then
        echo "$gtk3_ini" > "$HOME/.config/gtk-3.0/settings.ini"
        pass "GTK3 settings.ini"
        applied=$((applied + 1))
    fi

    # GTK4 settings.ini
    local gtk4_ini
    gtk4_ini=$(render_template "$TEMPLATES_DIR/gtk4-settings.ini.tmpl")
    if [[ -n "$gtk4_ini" ]]; then
        echo "$gtk4_ini" > "$HOME/.config/gtk-4.0/settings.ini"
        pass "GTK4 settings.ini"
        applied=$((applied + 1))
    fi
    fi # !labwc_only

    # Labwc themerc-override
    local themerc
    themerc=$(render_template "$TEMPLATES_DIR/themerc-override.tmpl")
    if [[ -n "$themerc" ]]; then
        echo "$themerc" > "$HOME/.config/labwc/themerc-override"
        pass "labwc themerc-override"
        applied=$((applied + 1))
    fi

    # Environment
    local environment
    environment=$(render_template "$TEMPLATES_DIR/environment.tmpl")
    if [[ -n "$environment" ]]; then
        echo "$environment" > "$HOME/.config/labwc/environment"
        pass "labwc environment"
        applied=$((applied + 1))
    fi

    # Sync rc.xml theme section (cornerRadius, font)
    local rc_xml="$HOME/.config/labwc/rc.xml"
    if [[ -f "$rc_xml" ]]; then
        local corner_radius
        corner_radius=$(ini_get "labwc.cornerRadius" "8")
        local themerc_font_name
        themerc_font_name=$(ini_get "labwc.themerc_font" "sans 10" | awk '{print $1}')
        local themerc_font_size
        themerc_font_size=$(ini_get "labwc.themerc_font" "sans 10" | awk '{print $2}')

        # Update cornerRadius
        sed -i "s|<cornerRadius>[^<]*</cornerRadius>|<cornerRadius>${corner_radius}</cornerRadius>|" "$rc_xml"

        # Update titlebar font name and size (all 4 places)
        for place in ActiveWindow InactiveWindow MenuHeader MenuItem; do
            sed -i "/<font place=\"$place\">/,/<\/font>/{
                s|<name>[^<]*</name>|<name>${themerc_font_name}</name>|
                s|<size>[^<]*</size>|<size>${themerc_font_size}</size>|
            }" "$rc_xml"
        done

        # Update theme name
        local theme_name
        theme_name=$(ini_get "meta.name" "ocws-catppuccin-mocha")
        sed -i "s|<name>[^<]*</name>|<name>${theme_name}</name>|" "$rc_xml"

        pass "labwc rc.xml synced (cornerRadius=${corner_radius}, font=${themerc_font_name} ${themerc_font_size})"
        applied=$((applied + 1))
    fi

    if [[ "$labwc_only" == false ]]; then
    # SFWBar CSS
    local sfwbar_css
    sfwbar_css=$(render_template "$TEMPLATES_DIR/sfwbar.css.tmpl")
    if [[ -n "$sfwbar_css" ]]; then
        echo "$sfwbar_css" > "$HOME/.config/ocws/theme.css"
        pass "theme.css"
        applied=$((applied + 1))
    fi

    # CSS Tokens (single source of truth for colors)
    local tokens_css
    tokens_css=$(render_template "$TEMPLATES_DIR/tokens.css.tmpl")
    if [[ -n "$tokens_css" ]]; then
        echo "$tokens_css" > "$HOME/.config/ocws/tokens.css"
        pass "tokens.css"
        applied=$((applied + 1))
    fi

    # OCWS Glass CSS
    local ocws_css
    ocws_css=$(render_template "$TEMPLATES_DIR/ocws.css.tmpl")
    if [[ -n "$ocws_css" ]]; then
        echo "$ocws_css" > "$HOME/.config/ocws/ocws.css"
        pass "ocws.css"
        applied=$((applied + 1))
    fi

    # Rofi
    local rofi_css
    rofi_css=$(render_template "$TEMPLATES_DIR/rofi.rasi.tmpl")
    if [[ -n "$rofi_css" ]]; then
        echo "$rofi_css" > "$HOME/.config/rofi/config.rasi"
        pass "rofi.rasi"
        applied=$((applied + 1))
    fi

    # Fuzzel
    local fuzzel_ini
    fuzzel_ini=$(render_template "$TEMPLATES_DIR/fuzzel.ini.tmpl")
    if [[ -n "$fuzzel_ini" ]]; then
        mkdir -p "$HOME/.config/fuzzel"
        echo "$fuzzel_ini" > "$HOME/.config/fuzzel/fuzzel.ini"
        pass "fuzzel.ini"
        applied=$((applied + 1))
    fi

    # Mako
    local mako_ini
    mako_ini=$(render_template "$TEMPLATES_DIR/mako.ini.tmpl")
    if [[ -n "$mako_ini" ]]; then
        echo "$mako_ini" > "$HOME/.config/mako/config"
        pass "mako.ini"
        applied=$((applied + 1))
    fi

    # Foot
    local foot_ini
    foot_ini=$(render_template "$TEMPLATES_DIR/foot.ini.tmpl")
    if [[ -n "$foot_ini" ]]; then
        echo "$foot_ini" > "$HOME/.config/foot/foot.ini"
        pass "foot.ini"
        applied=$((applied + 1))
    fi

    # Contour
    local contour_yml
    contour_yml=$(render_template "$TEMPLATES_DIR/contour.yml.tmpl")
    if [[ -n "$contour_yml" ]]; then
        mkdir -p "$HOME/.config/contour"
        echo "$contour_yml" > "$HOME/.config/contour/contour.yml"
        pass "contour.yml"
        applied=$((applied + 1))
    fi

    # Crystal Dock
    local cd_conf
    cd_conf=$(render_template "$TEMPLATES_DIR/crystal-dock-appearance.conf.tmpl")
    if [[ -n "$cd_conf" ]]; then
        mkdir -p "$HOME/.config/crystal-dock"
        echo "$cd_conf" > "$HOME/.config/crystal-dock/appearance.conf"
        pass "crystal-dock appearance.conf"
        applied=$((applied + 1))
    fi

    # Tmux
    local tmux_conf
    tmux_conf=$(render_template "$TEMPLATES_DIR/tmux.conf.tmpl")
    if [[ -n "$tmux_conf" ]]; then
        echo "$tmux_conf" > "$HOME/.tmux.conf"
        pass "tmux.conf"
        applied=$((applied + 1))
    fi

    # Qt (Qt5 and Qt6)
    local qt_conf
    qt_conf=$(render_template "$TEMPLATES_DIR/qt6ct.conf.tmpl")
    if [[ -n "$qt_conf" ]]; then
        mkdir -p "$HOME/.config/qt6ct" "$HOME/.config/qt5ct"
        echo "$qt_conf" > "$HOME/.config/qt6ct/qt6ct.conf"
        echo "$qt_conf" > "$HOME/.config/qt5ct/qt5ct.conf"
        pass "qt6ct.conf & qt5ct.conf"
        applied=$((applied + 1))
    fi

    # DankMaterialShell
    local dms_conf
    dms_conf=$(render_template "$TEMPLATES_DIR/dms-settings.json.tmpl")
    if [[ -n "$dms_conf" ]]; then
        mkdir -p "$HOME/.config/DankMaterialShell"
        echo "$dms_conf" > "$HOME/.config/DankMaterialShell/settings.json"
        pass "DankMaterialShell settings.json"
        applied=$((applied + 1))
    fi

    # Noctalia
    local noctalia_conf
    noctalia_conf=$(render_template "$TEMPLATES_DIR/noctalia.toml.tmpl")
    if [[ -n "$noctalia_conf" ]]; then
        mkdir -p "$HOME/.config/noctalia"
        echo "$noctalia_conf" > "$HOME/.config/noctalia/config.toml"
        pass "Noctalia config.toml"
        applied=$((applied + 1))
    fi

    # Firefox userChrome.css (central copy, symlink to profiles)
    local firefox_css
    firefox_css=$(render_template "$TEMPLATES_DIR/firefox-userChrome.css.tmpl")
    if [[ -n "$firefox_css" ]]; then
        mkdir -p "$HOME/.config/ocws/firefox"
        echo "$firefox_css" > "$HOME/.config/ocws/firefox/userChrome.css"
        pass "Firefox userChrome.css"
        applied=$((applied + 1))

        # Auto-install to Firefox profiles if they exist
        local profiles_ini="$HOME/.mozilla/firefox/profiles.ini"
        if [[ -f "$profiles_ini" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ ^Path=(.+)$ ]]; then
                    local profile_path="$HOME/.mozilla/firefox/${BASH_REMATCH[1]}"
                    if [[ -d "$profile_path" ]]; then
                        mkdir -p "$profile_path/chrome"
                        cp "$HOME/.config/ocws/firefox/userChrome.css" "$profile_path/chrome/userChrome.css"
                    fi
                fi
            done < "$profiles_ini"
        fi
    fi

    # Spicetify
    local spicetify_ini
    spicetify_ini=$(render_template "$TEMPLATES_DIR/spicetify.ini.tmpl")
    if [[ -n "$spicetify_ini" ]]; then
        mkdir -p "$HOME/.config/spicetify/Themes/OCWS"
        echo "$spicetify_ini" > "$HOME/.config/spicetify/Themes/OCWS/color.ini"
        pass "Spicetify color.ini"
        applied=$((applied + 1))
    fi

    # Vencord / Vesktop
    local vencord_css
    vencord_css=$(render_template "$TEMPLATES_DIR/vencord.css.tmpl")
    if [[ -n "$vencord_css" ]]; then
        mkdir -p "$HOME/.config/vesktop/settings"
        echo "$vencord_css" > "$HOME/.config/vesktop/settings/quickCss.css"
        pass "Vesktop quickCss.css"
        applied=$((applied + 1))
    fi

    # Update widget profile if sfwbar config exists
    local ocws_config="$HOME/.config/ocws/ocws.config"
    if [[ -f "$ocws_config" ]]; then
        sed -i "s|include(\"widget-sets/.*\.set\")|include(\"widget-sets/${profile}.set\")|g" "$ocws_config"
        pass "Widget profile set to: $profile"
        applied=$((applied + 1))
    fi
    # Live Reloading and Integration
    echo ""
    echo -e "${BOLD}Applying live updates...${NC}"

    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
        pass "Libadwaita set to prefer-dark"
    fi

    if command -v labwc >/dev/null 2>&1 && pgrep labwc >/dev/null; then
        labwc reconfigure
        pass "Live reloaded labwc"
    fi

    if command -v makoctl >/dev/null 2>&1 && pgrep mako >/dev/null; then
        makoctl reload
        pass "Live reloaded mako"
    fi

    if pgrep sfwbar >/dev/null; then
        killall -SIGUSR1 sfwbar 2>/dev/null || true
        pass "Live reloaded sfwbar"
    fi

    if command -v spicetify >/dev/null 2>&1; then
        spicetify apply >/dev/null 2>&1 || true
        pass "Live reloaded Spicetify"
    fi
    
    fi # !labwc_only

    echo ""
    pass "Theme $theme_name applied successfully (${applied} files generated/updated)"
}

cmd_preview() {
    local theme_file="$1"
    [[ -f "$theme_file" ]] || fail "Theme not found: $theme_file"

    parse_ini "$theme_file"
    expand_vars

    echo -e "${BOLD}Preview for: $(basename "$theme_file" .ini)${NC}"
    echo ""

    for tmpl_file in "$TEMPLATES_DIR"/*.tmpl; do
        [[ -f "$tmpl_file" ]] || continue
        local name
        name=$(basename "$tmpl_file")
        echo "=== $name ==="
        render_template "$tmpl_file"
        echo "---"
    done
}

cmd_export() {
    local theme_file="$1"
    [[ -f "$theme_file" ]] || fail "Theme not found: $theme_file"

    parse_ini "$theme_file"
    expand_vars

    local theme_name="$(basename "$theme_file" .ini)"
    echo -e "${BOLD}Exporting theme $theme_name to dotfiles/${NC}"
    echo ""

    # Generate all files
    for tmpl_file in "$TEMPLATES_DIR"/*.tmpl; do
        [[ -f "$tmpl_file" ]] || continue
        local name
        name=$(basename "$tmpl_file")
        local content
        content=$(render_template "$tmpl_file")

        if [[ -n "$content" ]]; then
            local dest
            dest="${OUTPUT_MAP[$name]:-}"
            if [[ -n "$dest" ]]; then
                # Convert $HOME/.config to $DOTFILES_DIR
                dest="${dest/$HOME\/.config/$DOTFILES_DIR}"
                mkdir -p "$(dirname "$dest")"
                echo "$content" > "$dest"
                pass "$name → ${dest#$PROJECT_DIR/}"
            else
                warn "No output destination for $name"
            fi
        fi
    done

    # Also export tokens into the GTK dirs so gtk.css @import resolves
    if [[ -f "$TEMPLATES_DIR/tokens.css.tmpl" ]]; then
        local gtk_tokens_export
        gtk_tokens_export="$(render_template "$TEMPLATES_DIR/tokens.css.tmpl")"
        if [[ -n "$gtk_tokens_export" ]]; then
            for d in gtk-3.0 gtk-4.0; do
                local gd="$DOTFILES_DIR/$d"
                mkdir -p "$gd"
                echo "$gtk_tokens_export" > "$gd/tokens.css"
                pass "tokens.css → $d/"
            done
        fi
    fi

    info "Theme files exported to dotfiles/"
}

# ============================================================
# Profile switching
# ============================================================

cmd_profile() {
    local profile="${1:-}"
    local profiles_dir="$DOTFILES_DIR/ocws/widget-sets"

    if [[ -z "$profile" ]]; then
        echo -e "${BOLD}Available profiles:${NC}"
        echo ""
        for f in "$profiles_dir"/*.set; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f" .set)
            local count
            count=$(grep -c '^include(' "$f" 2>/dev/null || echo 0)
            printf "  ${CYAN}%-15s${NC} %d widgets\n" "$name" "$count"
        done
        echo ""
        echo "Usage: $0 profile <name>"
        return
    fi

    local profile_file="$profiles_dir/${profile}.set"
    [[ -f "$profile_file" ]] || fail "Profile not found: $profile_file"

    # Symlink or copy the profile as plugins.config
    local plugins_config="$DOTFILES_DIR/ocws/plugins.config"
    cp "$profile_file" "$plugins_config"
    pass "Switched to profile: $profile ($(grep -c '^include(' "$profile_file") widgets)"
}

# ============================================================
# Main
# ============================================================

if [[ "$#" -lt 1 ]]; then
    echo "Usage: $0 {apply|preview|list|current|export|profile} [args]"
    echo ""
    echo "Commands:"
    echo "  apply <theme.ini>       Apply theme (generate + install)"
    echo "    --labwc-only          Only generate labwc outputs (themerc-override, environment, rc.xml)"
    echo "    --profile <name>      Set widget profile (standard|full)"
    echo "  preview <theme.ini>     Show what would be generated"
    echo "  list                    List available themes"
    echo "  current                 Show active theme"
    echo "  export <theme.ini>      Export generated files to dotfiles/"
    echo "  profile <standard|full> Switch widget set profile"
    echo "  extract <image> [name]  Extract color palette from wallpaper"
    exit 1
fi

cmd="$1"
shift

cmd_extract() {
    local image_path="$1"
    local output_name="${2:-wallpaper-auto}"
    
    [[ -n "$image_path" ]] || fail "Usage: $0 extract <wallpaper.jpg> [theme_name]"
    [[ -f "$image_path" ]] || fail "Image not found: $image_path"
    
    echo -e "${BOLD}Extracting palette from: $image_path${NC}"
    
    local out_file="$THEMES_DIR/${output_name}.ini"
    
    if command -v wal >/dev/null 2>&1; then
        wal -i "$image_path" -n -q
        if [[ -f "$HOME/.cache/wal/colors.sh" ]]; then
            # We must load variables carefully
            (
                source "$HOME/.cache/wal/colors.sh"
                cat > "$out_file" <<EOF
[meta]
name = Auto-generated from wallpaper
description = Generated via pywal
author = theme-engine

[colors]
bg = $background
fg = $foreground
accent = $color4
surface = $color0
border = $color8
urgent = $color1
ok = $color2
muted = $color7

[ocws]
blur = 5
border = 1
radius = 8
shadow = 4
EOF
            )
            pass "Generated $out_file using pywal!"
            return 0
        fi
    fi
    
    warn "No compatible extraction tool found (pywal recommended). Outputting default template."
}

case "$cmd" in
    apply)
        cmd_apply "$@"
        ;;
    extract)
        cmd_extract "$@"
        ;;
    preview)
        cmd_preview "$@"
        ;;
    list)
        cmd_list
        ;;
    current)
        cmd_current
        ;;
    export)
        cmd_export "$@"
        ;;
    profile)
        cmd_profile "$@"
        ;;
    *)
        echo "Unknown command: $cmd"
        echo "Usage: $0 {apply|preview|list|current|export|profile} [args]"
        exit 1
        ;;
esac
