#!/bin/bash
# -------------------------------------------------------------------
# OCWS Plugin Autoloader
# Scans ~/.config/ocws/plugins/ and generates plugins.config
# -------------------------------------------------------------------

OCWS_DIR="$HOME/.config/ocws"
PLUGIN_DIR="$OCWS_DIR/plugins"
CONFIG_FILE="$OCWS_DIR/plugins.config"

mkdir -p "$PLUGIN_DIR"

echo "# ============================================================" > "$CONFIG_FILE"
echo "# AUTO-GENERATED: OCWS Plugin Autoloader" >> "$CONFIG_FILE"
echo "# Do not edit manually. Drop .widget files in plugins/" >> "$CONFIG_FILE"
echo "# ============================================================" >> "$CONFIG_FILE"
echo "" >> "$CONFIG_FILE"

# Include static widgets (defined in ocws.config)
cat "$OCWS_DIR/ocws-widget-directives" >> "$CONFIG_FILE" 2>/dev/null || true

count=0
if [ -d "$PLUGIN_DIR" ]; then
    for plugin in "$PLUGIN_DIR"/*.widget; do
        if [ -f "$plugin" ]; then
            filename=$(basename "$plugin")
            echo "include(\"plugins/$filename\")" >> "$CONFIG_FILE"
            count=$((count+1))
        fi
    done
fi

echo "OCWS Plugin Loader: Discovered $count plugins."
