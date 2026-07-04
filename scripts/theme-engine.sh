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
#   [rofi], [sfwbar], [zebar], [mako], [foot], [qt6ct], [kvantum], [cursor], [ocws]
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
[[ -d "$PROJECT_DIR/themes" ]] || PROJECT_DIR="/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar"
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

            # Replace ${section.key} references
            local regex='\$\{([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)\}'
            while [[ "$new_val" =~ $regex ]]; do
                local ref_section="${BASH_REMATCH[1]}"
                local ref_key="${BASH_REMATCH[2]}"
                local ref_val="${INI_VALUES[${ref_section}.${ref_key}]:-}"

                if [[ -n "$ref_val" ]]; then
                    new_val="${new_val//\$${ref_section}.${ref_key}/$ref_val}"
                    changed=true
                else
                    warn "Undefined reference: \${${ref_section}.${ref_key}} in $key"
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
                    THEME_NAME)      var_value=$(ini_get "meta.name" "$(basename "$theme_file" .ini)" ) ;;
                    COLOR_BG)        var_value=$(ini_get "colors.bg" "#1e1e2e") ;;
                    COLOR_FG)        var_value=$(ini_get "colors.fg" "#cdd6f4") ;;
                    COLOR_SURFACE)   var_value=$(ini_get "colors.surface" "#1e1e2e") ;;
                    COLOR_BORDER)    var_value=$(ini_get "colors.border" "#45475a") ;;
                    COLOR_ACCENT)    var_value=$(ini_get "colors.accent" "#89b4fa") ;;
                    COLOR_URGENT)     var_value=$(ini_get "colors.urgent" "#f38ba8") ;;
                    COLOR_OK)        var_value=$(ini_get "colors.ok" "#a6e3a1") ;;
                    OCWS_BLUR)       var_value=$(ini_get "ocws.blur" "5") ;;
                    OCWS_BORDER)     var_value=$(ini_get "ocws.border" "1") ;;
                    OCWS_RADIUS)     var_value=$(ini_get "ocws.radius" "8") ;;
                    OCWS_SHADOW)     var_value=$(ini_get "ocws.shadow" "4") ;;
                    ICON_THEME)      var_value=$(ini_get "icons.theme" "") ;;
                    FONT_MONO)       var_value=$(ini_get "fonts.mono" "Noto Sans Mono CJK SC:hilight=Filled") ;;
                    *) warn "Unknown template variable: {{$var_name}}" ;;
        esac

        # Always replace to prevent infinite loops on empty/unknown variables
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
    [gtk3-settings.ini.tmpl]="$HOME/.config/gtk-3.0/settings.ini"
    [gtk4-settings.ini.tmpl]="$HOME/.config/gtk-4.0/settings.ini"
    [themerc-override.tmpl]="$HOME/.config/labwc/themerc-override"
    [environment.tmpl]="$HOME/.config/labwc/environment"
    [sfwbar.css.tmpl]="$HOME/.config/ocws/theme.css"
    [rofi.rasi.tmpl]="$HOME/.config/rofi/config.rasi"
    [mako.ini.tmpl]="$HOME/.config/mako/config"
    [foot.ini.tmpl]="$HOME/.config/foot/foot.ini"
    [qt6ct.conf.tmpl]="$HOME/.config/qt6ct/qt6ct.conf"
    [fuzzel.ini.tmpl]="$HOME/.config/fuzzel/fuzzel.ini"
    [ocws.css.tmpl]="$HOME/.config/ocws/ocws.css"
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

    # Environment
    local environment
    environment=$(render_template "$TEMPLATES_DIR/environment.tmpl")
    if [[ -n "$environment" ]]; then
        echo "$environment" > "$HOME/.config/labwc/environment"
        pass "labwc environment"
        ((applied++))
    fi

    # SFWBar CSS
    local sfwbar_css
    sfwbar_css=$(render_template "$TEMPLATES_DIR/sfwbar.css.tmpl")
    if [[ -n "$sfwbar_css" ]]; then
        echo "$sfwbar_css" > "$HOME/.config/ocws/theme.css"
        pass "theme.css"
        ((applied++))
    fi

    # OCWS Glass CSS
    local ocws_css
    ocws_css=$(render_template "$TEMPLATES_DIR/ocws.css.tmpl")
    if [[ -n "$ocws_css" ]]; then
        echo "$ocws_css" > "$HOME/.config/ocws/ocws.css"
        pass "ocws.css"
        ((applied++))
    fi

    # Rofi
    local rofi_css
    rofi_css=$(render_template "$TEMPLATES_DIR/rofi.rasi.tmpl")
    if [[ -n "$rofi_css" ]]; then
        echo "$rofi_css" > "$HOME/.config/rofi/config.rasi"
        pass "rofi.rasi"
        ((applied++))
    fi

    # Mako
    local mako_ini
    mako_ini=$(render_template "$TEMPLATES_DIR/mako.ini.tmpl")
    if [[ -n "$mako_ini" ]]; then
        echo "$mako_ini" > "$HOME/.config/mako/config"
        pass "mako.ini"
        ((applied++))
    fi

    # Foot
    local foot_ini
    foot_ini=$(render_template "$TEMPLATES_DIR/foot.ini.tmpl")
    if [[ -n "$foot_ini" ]]; then
        echo "$foot_ini" > "$HOME/.config/foot/foot.ini"
        pass "foot.ini"
        ((applied++))
    fi

    # Qt
    local qt_conf
    qt_conf=$(render_template "$TEMPLATES_DIR/qt6ct.conf.tmpl")
    if [[ -n "$qt_conf" ]]; then
        echo "$qt_conf" > "$HOME/.config/qt6ct/qt6ct.conf"
        pass "qt6ct.conf"
        ((applied++))
    fi

    # Fuzzel
    local fuzzel_ini
    fuzzel_ini=$(render_template "$TEMPLATES_DIR/fuzzel.ini.tmpl")
    if [[ -n "$fuzzel_ini" ]]; then
        echo "$fuzzel_ini" > "$HOME/.config/fuzzel/fuzzel.ini"
        pass "fuzzel.ini"
        ((applied++))
    fi

    echo ""
    pass "Theme $theme_name applied successfully (${applied} files generated)"
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

    # Handle Zebar
    if [[ -f "$TEMPLATES_DIR/zebar.css.tmpl" ]]; then
        local zebar_content
        zebar_content=$(render_template "$TEMPLATES_DIR/zebar.css.tmpl")
        if [[ -n "$zebar_content" ]]; then
            local zebar_dest="${ZEBAR_MAP[zebar.css.tmpl]}"
            mkdir -p "$(dirname "$zebar_dest")"
            echo "$zebar_content" > "$zebar_dest"
            pass "zebar.css.tmpl → ${zebar_dest#$HOME/}"
        fi
    fi

    info "Theme files exported to dotfiles/"
}

# ============================================================
# Main
# ============================================================

if [[ "$#" -lt 1 ]]; then
    echo "Usage: $0 {apply|preview|list|current|export} <theme.ini>"
    exit 1
fi

cmd="$1"
shift

case "$cmd" in
    apply)
        cmd_apply "$@"
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
    *)
        echo "Unknown command: $cmd"
        echo "Usage: $0 {apply|preview|list|current|export} <theme.ini>"
        exit 1
        ;;
esac
