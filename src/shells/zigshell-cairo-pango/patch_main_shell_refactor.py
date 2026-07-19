import re

with open('src/main_shell.zig', 'r') as f:
    content = f.read()

# Add import for session_ui
content = re.sub(r'const panel_mod = @import\("panel\.zig"\);', r'const panel_mod = @import("panel.zig");\nconst session_ui = @import("session_ui.zig");', content)

# Make necessary globals/functions public
content = re.sub(r'var panel_surface = SurfaceState\{ \.height = 24 \};', r'pub var panel_surface = SurfaceState{ .height = 24 };', content)
content = re.sub(r'var pointer_x: i32 = 0;', r'pub var pointer_x: i32 = 0;', content)
content = re.sub(r'var pointer_y: i32 = 0;', r'pub var pointer_y: i32 = 0;', content)
content = re.sub(r'var pointer_on_panel = false;', r'pub var pointer_on_panel = false;', content)
content = re.sub(r'fn applyPanelSurfaceHeight\(\) void', r'pub fn applyPanelSurfaceHeight() void', content)
content = re.sub(r'const SET_CARD_Y = 52;', r'pub const SET_CARD_Y = 52;', content)
content = re.sub(r'fn roundedRect\(', r'pub fn roundedRect(', content)
content = re.sub(r'const SettingsRect = struct \{', r'pub const SettingsRect = struct {', content)

# Replace drawSessionMenu calls
content = re.sub(r'drawSessionMenu\(cr, w, ph\);', r'session_ui.drawSessionMenu(cr, w, ph);', content)

# Replace handleSessionClick calls
content = re.sub(r'handleSessionClick\(pointer_x, pointer_y, button\);', r'session_ui.handleSessionClick(pointer_x, pointer_y, button);', content)

# Remove the session logic definitions from main_shell.zig
start_str = "const SESSION_W: i32 = 220;"
end_str = "fn drawSettingsMenu(cr: *c.cairo_t, _: i32, _: i32) void {"

idx_start = content.find(start_str)
idx_end = content.find(end_str)

if idx_start != -1 and idx_end != -1:
    content = content[:idx_start] + content[idx_end:]
else:
    print("Could not find session logic block to remove")

with open('src/main_shell.zig', 'w') as f:
    f.write(content)

print("Patched main_shell.zig successfully")
