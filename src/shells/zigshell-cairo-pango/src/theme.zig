const std = @import("std");
const c = @import("c.zig").c;

pub const Theme = struct {
    bg_color: [4]f64 = .{ 0.08, 0.08, 0.10, 0.85 }, // blur-friendly background
    bg_gradient_end: [4]f64 = .{ 0.05, 0.05, 0.07, 0.90 },
    
    border_color: [4]f64 = .{ 0.3, 0.3, 0.35, 1.0 },
    accent_color: [4]f64 = .{ 0.20, 0.61, 0.86, 0.9 }, // Focus lines, active elements
    
    text_color: [4]f64 = .{ 0.85, 0.85, 0.88, 1.0 },
    text_dim_color: [4]f64 = .{ 0.6, 0.6, 0.65, 1.0 },
    
    hover_color: [4]f64 = .{ 1.0, 1.0, 1.0, 0.12 },
    
    // Status colors
    success_color: [4]f64 = .{ 0.3, 0.8, 0.5, 1.0 },
    warning_color: [4]f64 = .{ 0.9, 0.7, 0.2, 1.0 },
    danger_color: [4]f64 = .{ 0.9, 0.2, 0.2, 1.0 },
};

pub var current: Theme = .{};

// Helper to apply cairo color
pub fn setSource(cr: *c.cairo_t, color: [4]f64) void {
    c.cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
}

// P14: load theme overrides from a simple key=value file (one slot per line,
// e.g. `accent_color = 0.2,0.61,0.86,0.9`). Unknown keys and malformed values
// are ignored and the default `current` value is kept, so a partial file is
// safe. Slots: bg_color, bg_gradient_end, border_color, accent_color,
// text_color, text_dim_color, hover_color, success_color, warning_color,
// danger_color.
pub fn load(path: []const u8) void {
    var buf: [4096]u8 = undefined;
    const data = readFile(path, &buf) orelse return;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq], " \t");
        const val = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        const slot = slotFor(key) orelse continue;
        const rgba = parseRgba(val) orelse continue;
        slot.* = rgba;
    }
}

fn slotFor(key: []const u8) ?*[4]f64 {
    const t = &current;
    if (std.mem.eql(u8, key, "bg_color")) return &t.bg_color;
    if (std.mem.eql(u8, key, "bg_gradient_end")) return &t.bg_gradient_end;
    if (std.mem.eql(u8, key, "border_color")) return &t.border_color;
    if (std.mem.eql(u8, key, "accent_color")) return &t.accent_color;
    if (std.mem.eql(u8, key, "text_color")) return &t.text_color;
    if (std.mem.eql(u8, key, "text_dim_color")) return &t.text_dim_color;
    if (std.mem.eql(u8, key, "hover_color")) return &t.hover_color;
    if (std.mem.eql(u8, key, "success_color")) return &t.success_color;
    if (std.mem.eql(u8, key, "warning_color")) return &t.warning_color;
    if (std.mem.eql(u8, key, "danger_color")) return &t.danger_color;
    return null;
}

fn parseRgba(val: []const u8) ?[4]f64 {
    var out: [4]f64 = .{ 0, 0, 0, 1 };
    var it = std.mem.tokenizeAny(u8, val, ", ");
    var i: usize = 0;
    while (it.next()) |tok| {
        if (i >= 4) break;
        out[i] = std.fmt.parseFloat(f64, tok) catch return null;
        i += 1;
    }
    if (i < 3) return null;
    if (i == 3) out[3] = 1.0;
    return out;
}

fn readFile(path: []const u8, buf: []u8) ?[]u8 {
    var zpath: [4096]u8 = undefined;
    if (path.len >= zpath.len) return null;
    @memcpy(zpath[0..path.len], path);
    zpath[path.len] = 0;
    const f = c.fopen(@ptrCast(&zpath), "r") orelse return null;
    defer _ = c.fclose(f);
    const n = c.fread(@ptrCast(buf.ptr), 1, buf.len - 1, f);
    if (n <= 0) return null;
    buf[@as(usize, @intCast(n))] = 0;
    return buf[0..@as(usize, @intCast(n))];
}
