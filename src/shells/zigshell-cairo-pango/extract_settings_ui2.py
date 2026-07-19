import re

with open('src/main_shell.zig', 'r') as f:
    content = f.read()

funcs = [
    r'fn handleSettingsClick\([\s\S]*?\n}\n',
    r'fn handleWidgetListClick\([\s\S]*?\n}\n',
    r'fn widgetListRef\([\s\S]*?\n}\n',
    r'fn handleDockClick\([\s\S]*?\n}\n',
    r'fn drawSettingsMenu\([\s\S]*?\n}\n',
    r'fn drawTab\([\s\S]*?\n}\n',
    r'fn drawWidgetManager\([\s\S]*?\n}\n',
    r'fn drawDockManager\([\s\S]*?\n}\n',
    r'fn drawFontScaleRow\([\s\S]*?\n}\n'
]

extracted_code = ""

for func_regex in funcs:
    match = re.search(func_regex, content)
    if match:
        extracted_code += match.group(0) + "\n"
        content = content.replace(match.group(0), "")
    else:
        print(f"Could not find function matching: {func_regex[:30]}")

# Variables and functions to prefix with main.
main_refs = [
    'settings_open', 'settings_tab', 'settings_scroll', 'settings_drag_idx', 'settings_add_menu',
    'widget_count', 'widgets', 'widget_x', 'autohide_dock', 'autohide_panel', 'font_scale', 'panel_height',
    'panel_surface', 'pointer_on_panel', 'pointer_x', 'pointer_y',
    'applyPanelSurfaceHeight', 'markDirty', 'setDockAutohide', 'setPanelAutohide', 'changeFontScale',
    'setPanelHeight', 'wireWidgetPriv', 'settingsRect', 'roundedRect', 'FONT_SCALE_STEP', 'SET_ROW_H', 'SET_TAB_H', 'SET_LIST_Y'
]

config_refs = [
    'saveConfig', 'syncConfigFromRuntime', 'applyConfigToRuntime'
]

for ref in main_refs:
    extracted_code = re.sub(r'(?<![a-zA-Z0-9_\.])' + ref + r'(?![a-zA-Z0-9_])', 'main.' + ref, extracted_code)

for ref in config_refs:
    extracted_code = re.sub(r'(?<![a-zA-Z0-9_\.])' + ref + r'(?![a-zA-Z0-9_])', 'config.' + ref, extracted_code)

extracted_code = re.sub(r'^fn ', 'pub fn ', extracted_code, flags=re.MULTILINE)

new_content = content
new_content = re.sub(r'const config_manager = @import\("config_manager\.zig"\);', r'const config_manager = @import("config_manager.zig");\nconst settings_ui = @import("settings_ui.zig");', new_content)

new_content = re.sub(r'(?<![a-zA-Z0-9_\.])handleSettingsClick\(', r'settings_ui.handleSettingsClick(', new_content)
new_content = re.sub(r'(?<![a-zA-Z0-9_\.])drawSettingsMenu\(', r'settings_ui.drawSettingsMenu(', new_content)

for ref in main_refs:
    new_content = re.sub(r'var ' + ref + r'(:| |=)', r'pub var ' + ref + r'\1', new_content)
    new_content = re.sub(r'const ' + ref + r'(:| |=)', r'pub const ' + ref + r'\1', new_content)
    new_content = re.sub(r'fn ' + ref + r'\(', r'pub fn ' + ref + r'(', new_content)

with open('src/settings_ui.zig', 'w') as f:
    f.write('const std = @import("std");\n')
    f.write('const c = @import("c.zig").c;\n')
    f.write('const panel_mod = @import("panel.zig");\n')
    f.write('const dock_mod = @import("dock.zig");\n')
    f.write('const icon = @import("icon.zig");\n')
    f.write('const main = @import("main_shell.zig");\n')
    f.write('const config = @import("config_manager.zig");\n\n')
    f.write(extracted_code)

with open('src/main_shell.zig', 'w') as f:
    f.write(new_content)

print("Extracted settings_ui.zig using targeted functions")
