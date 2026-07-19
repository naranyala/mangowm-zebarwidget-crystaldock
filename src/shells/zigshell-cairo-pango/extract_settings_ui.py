import re

with open('src/main_shell.zig', 'r') as f:
    content = f.read()

# Define the start and end of the block we want to extract
start_str = "fn handleSettingsClick("
end_str = "fn renderPanel(cr: *c.cairo_t, w: i32, ph: i32) void {"

idx_start = content.find(start_str)
idx_end = content.find(end_str)

if idx_start == -1 or idx_end == -1:
    print("Could not find bounds for settings_ui")
    exit(1)

settings_code = content[idx_start:idx_end]

# Variables and functions to prefix with main.
main_refs = [
    'settings_open', 'settings_tab', 'settings_scroll', 'settings_drag_idx', 'settings_add_menu',
    'widget_count', 'widgets', 'widget_x', 'autohide_dock', 'autohide_panel', 'font_scale', 'panel_height',
    'panel_surface', 'pointer_on_panel', 'pointer_x', 'pointer_y',
    'applyPanelSurfaceHeight', 'markDirty', 'setDockAutohide', 'setPanelAutohide', 'changeFontScale',
    'setPanelHeight', 'wireWidgetPriv', 'settingsRect', 'roundedRect', 'FONT_SCALE_STEP', 'SET_ROW_H', 'SET_TAB_H', 'SET_LIST_Y'
]

# Config refs
config_refs = [
    'saveConfig', 'syncConfigFromRuntime', 'applyConfigToRuntime'
]

# Do the regex replacement carefully
for ref in main_refs:
    settings_code = re.sub(r'(?<![a-zA-Z0-9_\.])' + ref + r'(?![a-zA-Z0-9_])', 'main.' + ref, settings_code)

for ref in config_refs:
    settings_code = re.sub(r'(?<![a-zA-Z0-9_\.])' + ref + r'(?![a-zA-Z0-9_])', 'config.' + ref, settings_code)

# We need to make all functions public
settings_code = re.sub(r'^fn ', 'pub fn ', settings_code, flags=re.MULTILINE)

# Remove the block from main_shell.zig
new_content = content[:idx_start] + content[idx_end:]

# Add imports
new_content = re.sub(r'const config_manager = @import\("config_manager\.zig"\);', r'const config_manager = @import("config_manager.zig");\nconst settings_ui = @import("settings_ui.zig");', new_content)

# Replace the two usages
new_content = re.sub(r'handleSettingsClick\(', r'settings_ui.handleSettingsClick(', new_content)
new_content = re.sub(r'drawSettingsMenu\(', r'settings_ui.drawSettingsMenu(', new_content)

# Make sure main variables are pub
for ref in main_refs:
    new_content = re.sub(r'var ' + ref + r'(:| |=)', r'pub var ' + ref + r'\1', new_content)
    new_content = re.sub(r'const ' + ref + r'(:| |=)', r'pub const ' + ref + r'\1', new_content)
    new_content = re.sub(r'fn ' + ref + r'\(', r'pub fn ' + ref + r'(', new_content)

with open('src/settings_ui.zig', 'w') as f:
    f.write('const std = @import("std");\n')
    f.write('const c = @import("c.zig").c;\n')
    f.write('const panel_mod = @import("panel.zig");\n')
    f.write('const dock_mod = @import("dock.zig");\n')
    f.write('const main = @import("main_shell.zig");\n')
    f.write('const config = @import("config_manager.zig");\n\n')
    f.write(settings_code)

with open('src/main_shell.zig', 'w') as f:
    f.write(new_content)

print("Extracted settings_ui.zig")
