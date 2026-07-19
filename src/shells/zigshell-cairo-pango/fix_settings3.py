import re

with open('src/settings_ui.zig', 'r') as f:
    content = f.read()

content = re.sub(r'(?<![a-zA-Z0-9_\.])config_dirty(?![a-zA-Z0-9_])', 'main.config_dirty', content)
content = re.sub(r'(?<![a-zA-Z0-9_\.])SET_ROW_H(?![a-zA-Z0-9_])', 'main.SET_ROW_H', content)

with open('src/settings_ui.zig', 'w') as f:
    f.write(content)

with open('src/main_shell.zig', 'r') as f:
    main_content = f.read()

# find drawToggleRow and move it to settings_ui.zig
match = re.search(r'fn drawToggleRow\([\s\S]*?\n}\n', main_content)
if match:
    code = match.group(0)
    main_content = main_content.replace(code, "")
    
    code = re.sub(r'^fn ', 'pub fn ', code)
    code = re.sub(r'(?<![a-zA-Z0-9_\.])roundedRect(?![a-zA-Z0-9_])', 'main.roundedRect', code)
    
    with open('src/settings_ui.zig', 'a') as f:
        f.write("\n" + code)

with open('src/main_shell.zig', 'w') as f:
    f.write(main_content)

print("Fixed settings_ui.zig again")
