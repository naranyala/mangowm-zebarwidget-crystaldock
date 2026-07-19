const std = @import("std");
const c = @import("c.zig").c;
const panel_mod = @import("panel.zig");
const dock_mod = @import("dock.zig");

/// Persistent configuration for the panel + dock, serialized to an INI file.
///
/// Format:
///   [panel]
///   height = 24
///   autohide_dock = false
///
///   [dock]
///   icon_size = 28
///
///   [dock.pins]
///   foot
///   firefox
///
///   [workspaces]
///   side = left
///   ...
///   (one section per widget, in display order)
pub const Config = struct {
    did_read: bool = false,
    panel_height: i32 = 24,
    font_scale: f32 = 1.0,
    autohide_dock: bool = false,
    autohide_panel: bool = false,
    dock_icon_size: i32 = 28,
    pins: [256]u8 = std.mem.zeroes([256]u8),
    pins_len: usize = 0,
    widgets: [panel_mod.MAX_WIDGETS]panel_mod.Widget = undefined,
    widget_count: i32 = 0,

    const Self = @This();

    /// Load config from `path`. Missing file falls back to `defaults`.
    /// Sets the process-wide `global`. Returns true if a file was read.
    pub fn load(alloc: std.mem.Allocator, path: []const u8, defaults: panel_mod.WidgetList) bool {
        const cfg = loadInto(alloc, path, defaults);
        global = cfg;
        return cfg.did_read;
    }

    pub fn loadInto(alloc: std.mem.Allocator, path: []const u8, defaults: panel_mod.WidgetList) Self {
        var cfg: Self = .{};
        cfg.widget_count = defaults.count.*;
        for (0..@intCast(defaults.count.*)) |i| cfg.widgets[i] = defaults.widgets[i];

        const path_z = alloc.dupeZ(u8, path) catch return cfg;
        defer alloc.free(path_z);
        const f = c.fopen(path_z, "r") orelse return cfg;
        defer _ = c.fclose(f);
        cfg.did_read = true;

        var cur_type: [64]u8 = std.mem.zeroes([64]u8);
        var opts: [1024]u8 = std.mem.zeroes([1024]u8);
        var opts_len: usize = 0;

        // Reset widget list; repopulate from file in order.
        cfg.widget_count = 0;
        cfg.pins_len = 0;

        var line_buf: [1024]u8 = std.mem.zeroes([1024]u8);
        while (c.fgets(&line_buf, line_buf.len, f) != null) {
            const raw = std.mem.sliceTo(&line_buf, 0);
            const trimmed = std.mem.trimStart(u8, raw, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            if (trimmed[0] == '[') {
                finalizeSection(&cfg, &cur_type, &opts, opts_len);
                opts_len = 0;
                const end = std.mem.indexOfScalar(u8, trimmed, ']') orelse {
                    cur_type[0] = 0;
                    continue;
                };
                const name = trimmed[1..end];
                if (std.mem.eql(u8, name, "panel")) {
                    @memcpy(cur_type[0..5], "panel");
                    cur_type[5] = 0;
                } else if (std.mem.eql(u8, name, "dock")) {
                    @memcpy(cur_type[0..4], "dock");
                    cur_type[4] = 0;
                } else if (std.mem.eql(u8, name, "dock.pins")) {
                    @memcpy(cur_type[0..9], "dock.pins");
                    cur_type[9] = 0;
                } else {
                    const n = @min(name.len, 63);
                    @memcpy(cur_type[0..n], name[0..n]);
                    cur_type[n] = 0;
                }
            } else {
                if (opts_len > 0 and opts_len < opts.len - 1) {
                    opts[opts_len] = '\n';
                    opts_len += 1;
                }
                const copy_len = @min(trimmed.len, opts.len - opts_len - 1);
                @memcpy(opts[opts_len .. opts_len + copy_len], trimmed[0..copy_len]);
                opts_len += copy_len;
                opts[opts_len] = 0;
            }
        }
        finalizeSection(&cfg, &cur_type, &opts, opts_len);
        return cfg;
    }

    fn finalizeSection(cfg: *Self, cur_type: *[64]u8, opts: *[1024]u8, opts_len: usize) void {
        const section = std.mem.sliceTo(cur_type, 0);
        if (section.len == 0) return;

        if (std.mem.eql(u8, section, "panel")) {
            cfg.panel_height = parseI32(opts[0..opts_len], "height", cfg.panel_height);
            cfg.font_scale = parseF32(opts[0..opts_len], "font_scale", cfg.font_scale);
            cfg.autohide_dock = parseBool(opts[0..opts_len], "autohide_dock", cfg.autohide_dock);
            cfg.autohide_panel = parseBool(opts[0..opts_len], "autohide_panel", cfg.autohide_panel);
        } else if (std.mem.eql(u8, section, "dock")) {
            cfg.dock_icon_size = parseI32(opts[0..opts_len], "icon_size", cfg.dock_icon_size);
        } else if (std.mem.eql(u8, section, "dock.pins")) {
            cfg.pins_len = 0;
            var it = std.mem.tokenizeScalar(u8, opts[0..opts_len], '\n');
            while (it.next()) |line| {
                const name = std.mem.trim(u8, line, " \t\r");
                if (name.len == 0 or name.len >= 256) continue;
                if (cfg.pins_len > 0 and cfg.pins_len < cfg.pins.len) {
                    cfg.pins[cfg.pins_len] = '\n';
                    cfg.pins_len += 1;
                }
                const n = @min(name.len, cfg.pins.len - cfg.pins_len);
                @memcpy(cfg.pins[cfg.pins_len .. cfg.pins_len + n], name[0..n]);
                cfg.pins_len += n;
            }
        } else {
            const wtype = panel_mod.parseWidgetType(section) orelse return;
            if (cfg.widget_count >= panel_mod.MAX_WIDGETS) return;
            var w = panel_mod.createWidget(wtype);
            if (parseBool(opts[0..opts_len], "side", false)) w.side = 1;
            if (parseBool(opts[0..opts_len], "hidden", false)) w.hidden = true;
            cfg.widgets[@intCast(cfg.widget_count)] = w;
            cfg.widget_count += 1;
        }
    }

    /// Persist the current process-wide config to `path`.
    pub fn save(alloc: std.mem.Allocator, path: []const u8) bool {
        const path_z = alloc.dupeZ(u8, path) catch return false;
        defer alloc.free(path_z);
        const f = c.fopen(path_z, "w") orelse return false;
        defer _ = c.fclose(f);

        _ = c.fprintf(f, "[panel]\n");
        _ = c.fprintf(f, "height = %d\n", global.panel_height);
        _ = c.fprintf(f, "font_scale = %.3f\n", global.font_scale);
        _ = c.fprintf(f, "autohide_dock = %s\n", @as([*:0]const u8, @ptrCast(if (global.autohide_dock) "true" else "false")));
        _ = c.fprintf(f, "autohide_panel = %s\n", @as([*:0]const u8, @ptrCast(if (global.autohide_panel) "true" else "false")));
        _ = c.fprintf(f, "\n[dock]\n");
        _ = c.fprintf(f, "icon_size = %d\n", global.dock_icon_size);
        _ = c.fprintf(f, "\n[dock.pins]\n");
        _ = c.fprintf(f, "%.*s\n", @as(c_int, @intCast(global.pins_len)), @as([*]const u8, @ptrCast(&global.pins)));
        _ = c.fprintf(f, "\n");

        for (0..@intCast(global.widget_count)) |i| {
            const w = global.widgets[i];
            const name = widgetTypeToName(w.wtype) orelse continue;
            _ = c.fprintf(f, "[%s]\n", name.ptr);
            if (w.side == 1) _ = c.fprintf(f, "side = right\n");
            if (w.hidden) _ = c.fprintf(f, "hidden = true\n");
            if (w.wtype == .spacer) _ = c.fprintf(f, "width = %d\n", w.spacer_w);
            if (w.wtype == .customcommand and w.cmd[0] != 0)
                _ = c.fprintf(f, "command = %s\n", @as([*]const u8, @ptrCast(&w.cmd)));
            _ = c.fprintf(f, "\n");
        }
        return true;
    }
};

/// Process-wide current config, set by load() and mutated by the settings UI.
pub var global: Config = .{};

fn parseI32(opts: []const u8, key: []const u8, default: i32) i32 {
    var it = std.mem.tokenizeScalar(u8, opts, '\n');
    while (it.next()) |line| {
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const k = std.mem.trim(u8, line[0..eq], " \t");
        if (!std.mem.eql(u8, k, key)) continue;
        const v = std.mem.trim(u8, line[eq + 1 ..], " \t");
        return std.fmt.parseInt(i32, v, 10) catch default;
    }
    return default;
}

fn parseF32(opts: []const u8, key: []const u8, default: f32) f32 {
    var it = std.mem.tokenizeScalar(u8, opts, '\n');
    while (it.next()) |line| {
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const k = std.mem.trim(u8, line[0..eq], " \t");
        if (!std.mem.eql(u8, k, key)) continue;
        const v = std.mem.trim(u8, line[eq + 1 ..], " \t");
        return std.fmt.parseFloat(f32, v) catch default;
    }
    return default;
}

fn parseBool(opts: []const u8, key: []const u8, default: bool) bool {
    var it = std.mem.tokenizeScalar(u8, opts, '\n');
    while (it.next()) |line| {
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const k = std.mem.trim(u8, line[0..eq], " \t");
        if (!std.mem.eql(u8, k, key)) continue;
        const v = std.mem.trim(u8, line[eq + 1 ..], " \t");
        return std.mem.eql(u8, v, "true") or std.mem.eql(u8, v, "1");
    }
    return default;
}

fn widgetTypeToName(wtype: panel_mod.WidgetType) ?[]const u8 {
    const map = [_]struct { n: []const u8, t: panel_mod.WidgetType }{
        .{ .n = "workspaces", .t = .workspaces },
        .{ .n = "toplevel", .t = .toplevel_task },
        .{ .n = "launcher", .t = .launcher },
        .{ .n = "cpu", .t = .cpu },
        .{ .n = "mem", .t = .mem },
        .{ .n = "temp", .t = .temp },
        .{ .n = "disk", .t = .disk },
        .{ .n = "battery", .t = .battery },
        .{ .n = "volume", .t = .volume },
        .{ .n = "network", .t = .network },
        .{ .n = "media", .t = .media },
        .{ .n = "clock", .t = .clock },
        .{ .n = "power", .t = .power },
        .{ .n = "spacer", .t = .spacer },
        .{ .n = "kbindicator", .t = .kbindicator },
        .{ .n = "customcommand", .t = .customcommand },
        .{ .n = "showdesktop", .t = .showdesktop },
        .{ .n = "worldclock", .t = .worldclock },
        .{ .n = "backlight", .t = .backlight },
        .{ .n = "session", .t = .session },
        .{ .n = "versions", .t = .versions },
    };
    for (map) |e| if (e.t == wtype) return e.n;
    return null;
}

test "config font_scale round-trips through save/load" {
    const path = "/tmp/zigshell_test_fontscale.ini";
    const f = c.fopen(path, "w") orelse return;
    _ = c.fputs("[panel]\nheight = 24\nfont_scale = 1.250\nautohide_dock = false\n\n[dock]\nicon_size = 28\n", f);
    _ = c.fclose(f);
    defer _ = c.remove(path);

    var defaults: [panel_mod.MAX_WIDGETS]panel_mod.Widget = undefined;
    var dcount: i32 = 0;
    const dl = panel_mod.WidgetList{ .widgets = &defaults, .count = &dcount };
    const cfg = Config.loadInto(std.testing.allocator, path, dl);
    try std.testing.expect(cfg.did_read);
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), cfg.font_scale, 0.001);
}
