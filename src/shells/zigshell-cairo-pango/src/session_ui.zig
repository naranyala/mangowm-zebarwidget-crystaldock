const std = @import("std");
const c = @import("c.zig").c;
const panel_mod = @import("panel.zig");
const main = @import("main_shell.zig");

pub const SESSION_W: i32 = 220;
pub const SESSION_ROW_H: i32 = 36;

pub const SessionAction = struct {
    label: []const u8,
    glyph: []const u8,
    cmd: []const u8,
};

pub const SESSION_ACTIONS = [_]SessionAction{
    .{ .label = "Lock", .glyph = "🔒", .cmd = "swaylock -f -c 000000 &" },
    .{ .label = "Logout", .glyph = "⏏", .cmd = "loginctl terminate-user $USER &" },
    .{ .label = "Switch User", .glyph = "👤", .cmd = "loginctl switch-user &" },
    .{ .label = "Suspend", .glyph = "🌙", .cmd = "systemctl suspend &" },
    .{ .label = "Hibernate", .glyph = "❄", .cmd = "systemctl hibernate &" },
    .{ .label = "Freeze", .glyph = "🧊", .cmd = "systemctl suspend-then-hibernate &" },
    .{ .label = "Reboot", .glyph = "🔄", .cmd = "systemctl reboot &" },
    .{ .label = "Reboot (Firmware)", .glyph = "⚙", .cmd = "systemctl reboot --firmware-setup &" },
    .{ .label = "Reboot (Recovery)", .glyph = "🔧", .cmd = "systemctl reboot --recovery &" },
    .{ .label = "Emergency", .glyph = "⚠", .cmd = "systemctl emergency &" },
    .{ .label = "Shutdown", .glyph = "⏻", .cmd = "systemctl poweroff &" },
};

// Geometry of the popup card (anchored bottom-right under the panel top bar).
pub fn sessionRect() main.SettingsRect {
    return .{
        .x = main.panel_surface.width - SESSION_W - 12,
        .y = main.SET_CARD_Y,
        .w = SESSION_W,
        .h = @as(i32, @intCast(SESSION_ACTIONS.len)) * SESSION_ROW_H + 50,
    };
}

pub fn drawSessionMenu(cr: *c.cairo_t, _: i32, _: i32) void {
    const r = sessionRect();

    // Card background
    c.cairo_set_source_rgba(cr, 0.06, 0.06, 0.09, 0.96);
    main.roundedRect(cr, @floatFromInt(r.x), @floatFromInt(r.y), @floatFromInt(r.w), @floatFromInt(r.h), 12.0);
    c.cairo_fill(cr);
    c.cairo_set_source_rgba(cr, 0.3, 0.5, 1.0, 0.25);
    c.cairo_set_line_width(cr, 1.5);
    main.roundedRect(cr, @floatFromInt(r.x), @floatFromInt(r.y), @floatFromInt(r.w), @floatFromInt(r.h), 12.0);
    c.cairo_stroke(cr);

    // Title
    c.cairo_save(cr);
    c.cairo_translate(cr, 0.0, @floatFromInt(r.y + 12));
    _ = panel_mod.widgetText(cr, "Session", r.x + 14, 24, "Inter Bold 13", 0.98, 0.98, 1.0);
    c.cairo_restore(cr);

    var i: usize = 0;
    while (i < SESSION_ACTIONS.len) : (i += 1) {
        const a = SESSION_ACTIONS[i];
        const ry = r.y + 12 + @as(i32, @intCast(i)) * SESSION_ROW_H + 34; // Added title offset
        const hover = main.pointer_on_panel and main.pointer_x >= r.x + 6 and main.pointer_x < r.x + r.w - 6 and main.pointer_y >= ry and main.pointer_y < ry + SESSION_ROW_H - 4;
        if (hover) {
            c.cairo_set_source_rgba(cr, 0.2, 0.45, 0.95, 0.16);
            main.roundedRect(cr, @floatFromInt(r.x + 6), @floatFromInt(ry), @floatFromInt(r.w - 12), @floatFromInt(SESSION_ROW_H - 4), 7.0);
            c.cairo_fill(cr);
        }
        c.cairo_save(cr);
        c.cairo_translate(cr, 0.0, @floatFromInt(ry));
        _ = panel_mod.widgetText(cr, @ptrCast(a.glyph.ptr), r.x + 14, SESSION_ROW_H - 4, "Inter 13", 0.9, 0.9, 0.95);
        _ = panel_mod.widgetText(cr, @ptrCast(a.label.ptr), r.x + 40, SESSION_ROW_H - 4, "Inter 12", 0.92, 0.92, 0.95);
        c.cairo_restore(cr);
    }
}

pub fn handleSessionClick(x: i32, y: i32, _: u32) bool {
    const r = sessionRect();
    // Click outside the card closes it; return false so the click falls through.
    if (x < r.x or x > r.x + r.w or y < r.y or y > r.y + r.h) {
        panel_mod.session_open = false;
        main.applyPanelSurfaceHeight();
        return false;
    }
    // Click on an action row runs its command and closes.
    var i: usize = 0;
    while (i < SESSION_ACTIONS.len) : (i += 1) {
        const ry = r.y + 12 + @as(i32, @intCast(i)) * SESSION_ROW_H + 34;
        if (y >= ry and y < ry + SESSION_ROW_H - 4 and x >= r.x + 6 and x < r.x + r.w - 6) {
            const a = SESSION_ACTIONS[i];
            _ = panel_mod.spawnCmd(@ptrCast(a.cmd.ptr));
            panel_mod.session_open = false;
            main.applyPanelSurfaceHeight();
            return true;
        }
    }
    return false;
}
