import re

with open('src/main_shell.zig', 'r') as f:
    content = f.read()

# Add import for config_manager
content = re.sub(r'const session_ui = @import\("session_ui\.zig"\);', r'const session_ui = @import("session_ui.zig");\nconst config_manager = @import("config_manager.zig");', content)

# Make necessary globals/functions public
globals_to_pub = ['config_path', 'config_dirty', 'panel_height', 'font_scale', 'autohide_dock', 'autohide_panel', 'widget_count', 'widgets']
for g in globals_to_pub:
    content = re.sub(r'var ' + g + r'(:| |=)', r'pub var ' + g + r'\1', content)
    # in case it was 'const' or something (it shouldn't be for most of these)

functions_to_pub = ['setDockAutohide', 'setPanelAutohide', 'applyFontScale', 'setPanelHeight', 'wireWidgetPriv']
for fn in functions_to_pub:
    content = re.sub(r'fn ' + fn + r'\(', r'pub fn ' + fn + r'(', content)

# Replace function calls
content = re.sub(r'resolveConfigPath\(', r'config_manager.resolveConfigPath(', content)
content = re.sub(r'saveConfig\(', r'config_manager.saveConfig(', content)
content = re.sub(r'syncConfigFromRuntime\(', r'config_manager.syncConfigFromRuntime(', content)
content = re.sub(r'applyConfigToRuntime\(', r'config_manager.applyConfigToRuntime(', content)

# Remove the config logic definitions from main_shell.zig
start_str = "// Resolve the config file path:"
end_str = "// Launch the out-of-process GTK settings app."

idx_start = content.find(start_str)
idx_end = content.find(end_str)

if idx_start != -1 and idx_end != -1:
    content = content[:idx_start] + content[idx_end:]

start_str2 = "// Persist the current panel + dock configuration to disk"
end_str2 = "// P6: apply a new panel height at runtime."

idx_start2 = content.find(start_str2)
idx_end2 = content.find(end_str2)

if idx_start2 != -1 and idx_end2 != -1:
    content = content[:idx_start2] + content[idx_end2:]

with open('src/main_shell.zig', 'w') as f:
    f.write(content)

print("Patched main_shell.zig successfully")
