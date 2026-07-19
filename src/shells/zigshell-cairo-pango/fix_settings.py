import re

with open('src/settings_ui.zig', 'r') as f:
    content = f.read()

content = content.replace('config_manager.', 'config.')
content = content.replace('g_widget_list', 'main.g_widget_list')
content = re.sub(r'(?<!\.)SettingsRect', 'main.SettingsRect', content)

with open('src/settings_ui.zig', 'w') as f:
    f.write(content)

with open('src/main_shell.zig', 'r') as f:
    main_content = f.read()

# export g_widget_list
main_content = main_content.replace('var g_widget_list:', 'pub var g_widget_list:')

# find drawListBtn and move it to settings_ui.zig
match = re.search(r'fn drawListBtn\([\s\S]*?\n}\n', main_content)
if match:
    draw_list_btn_code = match.group(0)
    main_content = main_content.replace(match.group(0), "")
    
    # replace refs
    draw_list_btn_code = re.sub(r'^fn ', 'pub fn ', draw_list_btn_code)
    draw_list_btn_code = re.sub(r'(?<![a-zA-Z0-9_\.])roundedRect(?![a-zA-Z0-9_])', 'main.roundedRect', draw_list_btn_code)
    
    with open('src/settings_ui.zig', 'a') as f:
        f.write("\n" + draw_list_btn_code)

# fix widgetListRef call in main_shell.zig
main_content = main_content.replace('widgetListRef()', 'settings_ui.widgetListRef()')

with open('src/main_shell.zig', 'w') as f:
    f.write(main_content)

print("Fixed settings_ui.zig and main_shell.zig")
