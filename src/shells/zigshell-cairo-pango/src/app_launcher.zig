// app_launcher.zig — Fixed menu app launcher popup
//
// Two modes:
//   1. OCWS mode (from dock): shows only OCWS GUI apps
//   2. Generic mode (from panel widget): shows categorized system apps
//
// Clicking an app launches it and closes the menu. Scrolling navigates the grid.

const std = @import("std");
const c = @import("c.zig").c;
const panel_mod = @import("panel.zig");
const apps_mod = @import("apps");
const ocws = @import("ocws_apps.zig");
const icon = @import("icon.zig");
const main = @import("main_shell.zig");

pub var launcher_open = false;
pub var launcher_hover_idx: i32 = -1;
pub var launcher_scroll: i32 = 0;
pub var ocws_mode: bool = false; // true = OCWS apps only, false = generic system apps

const LAUNCHER_W: i32 = 480;
const LAUNCHER_PAD: i32 = 12;
const LAUNCHER_ICON_SIZE: i32 = 32;
const LAUNCHER_ROW_H: i32 = 48;
const LAUNCHER_COLS: i32 = 3;
const LAUNCHER_HEADER_H: i32 = 36;

// Generic launcher entries
const Entry = struct {
    name: [64]u8 = std.mem.zeroes([64]u8),
    exec: [256]u8 = std.mem.zeroes([256]u8),
    icon_name: [128]u8 = std.mem.zeroes([128]u8),
};

const MAX_ENTRIES = 128;
var entries: [MAX_ENTRIES]Entry = std.mem.zeroes([MAX_ENTRIES]Entry);
var entry_count: i32 = 0;
var entries_scanned: bool = false;

// Category definitions for generic mode
const Category = struct {
    name: []const u8,
    candidates: []const []const u8,
};

const CATEGORIES = [_]Category{
    .{ .name = "Terminal", .candidates = &.{ "foot", "kitty", "alacritty", "wezterm", "st" } },
    .{ .name = "Browser", .candidates = &.{ "firefox", "chromium", "google-chrome", "brave", "qutebrowser" } },
    .{ .name = "Files", .candidates = &.{ "pcmanfm", "pcmanfm-qt", "thunar", "nautilus", "dolphin" } },
    .{ .name = "Editor", .candidates = &.{ "code", "codium", "geany", "kate", "gedit", "nano", "vim", "nvim" } },
    .{ .name = "Settings", .candidates = &.{ "pavucontrol", "nm-connection-editor", "blueman-manager" } },
    .{ .name = "System", .candidates = &.{ "htop", "btop", "gnome-system-monitor" } },
};

/// Populate entries based on current mode (OCWS or generic).
pub fn ensureEntries() void {
    if (entries_scanned) return;
    entries_scanned = true;
    entry_count = 0;

    if (ocws_mode) {
        // OCWS mode: hardcoded list
        for (ocws.OCWS_APPS) |app| {
            if (entry_count >= MAX_ENTRIES) return;
            var e = &entries[@intCast(entry_count)];
            setStr(&e.name, app.name);
            setStr(&e.exec, app.exec);
            setStr(&e.icon_name, app.icon);
            entry_count += 1;
        }
    } else {
        // Generic mode: scan system apps
        const app_list = apps_mod.list();
        for (CATEGORIES) |cat| {
            for (cat.candidates) |candidate| {
                for (app_list) |app| {
                    const app_exec = app.exec[0..app.exec_len];
                    if (execMatches(app_exec, candidate)) {
                        if (entry_count >= MAX_ENTRIES) return;
                        var e = &entries[@intCast(entry_count)];
                        setStr(&e.name, app.name[0..app.name_len]);
                        setStr(&e.exec, app_exec);
                        setStr(&e.icon_name, app.icon[0..app.icon_len]);
                        entry_count += 1;
                        break;
                    }
                }
            }
        }
    }
}

fn setStr(buf: anytype, s: []const u8) void {
    const n = @min(s.len, buf.len - 1);
    @memcpy(buf[0..n], s[0..n]);
    buf[n] = 0;
}

fn execMatches(app_exec: []const u8, candidate: []const u8) bool {
    if (std.mem.eql(u8, app_exec, candidate)) return true;
    if (app_exec.len > candidate.len + 1) {
        const suffix = app_exec[app_exec.len - candidate.len ..];
        if (std.mem.eql(u8, suffix, candidate) and app_exec[app_exec.len - candidate.len - 1] == '/') return true;
    }
    return false;
}

pub fn launcherRect(panel_width: i32, panel_height: i32) struct { x: i32, y: i32, w: i32, h: i32 } {
    const rows_per_page = @divTrunc(panel_height - LAUNCHER_HEADER_H - LAUNCHER_PAD * 2, LAUNCHER_ROW_H);
    const total_rows = @divTrunc(entry_count + LAUNCHER_COLS - 1, LAUNCHER_COLS);
    const visible_rows = @max(1, @min(total_rows, rows_per_page));
    const card_h = LAUNCHER_HEADER_H + visible_rows * LAUNCHER_ROW_H + LAUNCHER_PAD * 2;
    return .{
        .x = @divTrunc(panel_width - LAUNCHER_W, 2),
        .y = panel_height + 4,
        .w = LAUNCHER_W,
        .h = card_h,
    };
}

pub fn draw(cr: *c.cairo_t, panel_width: i32, panel_height: i32, pointer_x: i32, pointer_y: i32) void {
    ensureEntries();
    if (entry_count == 0) return;

    const r = launcherRect(panel_width, panel_height);

    // Dark backdrop
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.4);
    c.cairo_rectangle(cr, 0, @floatFromInt(panel_height), @floatFromInt(panel_width), @floatFromInt(r.h + 8));
    c.cairo_fill(cr);

    // Card background
    c.cairo_set_source_rgba(cr, 0.06, 0.06, 0.09, 0.97);
    main.roundedRect(cr, @floatFromInt(r.x), @floatFromInt(r.y), @floatFromInt(r.w), @floatFromInt(r.h), 14.0);
    c.cairo_fill(cr);

    // Border glow
    c.cairo_set_source_rgba(cr, 0.25, 0.45, 0.9, 0.2);
    c.cairo_set_line_width(cr, 1.5);
    main.roundedRect(cr, @floatFromInt(r.x), @floatFromInt(r.y), @floatFromInt(r.w), @floatFromInt(r.h), 14.0);
    c.cairo_stroke(cr);

    // Title
    const title = if (ocws_mode) "OCWS Apps" else "Applications";
    _ = panel_mod.widgetText(cr, title, r.x + LAUNCHER_PAD, r.y + LAUNCHER_HEADER_H - 6, "Inter Bold 14", 0.95, 0.95, 0.98);

    // App grid
    const cell_w = @divTrunc(r.w - LAUNCHER_PAD * 2, LAUNCHER_COLS);
    const first = launcher_scroll * LAUNCHER_COLS;
    var idx: i32 = 0;
    while (idx < entry_count) : (idx += 1) {
        const abs_idx = first + idx;
        if (abs_idx >= entry_count) break;
        const col = @mod(abs_idx, LAUNCHER_COLS);
        const row = @divTrunc(abs_idx, LAUNCHER_COLS) - launcher_scroll;
        if (row < 0) continue;

        const cx = r.x + LAUNCHER_PAD + col * cell_w;
        const cy = r.y + LAUNCHER_HEADER_H + row * LAUNCHER_ROW_H;

        if (cy + LAUNCHER_ROW_H > r.y + r.h) break;

        const e = &entries[@intCast(abs_idx)];

        // Hover highlight
        const is_hover = pointer_x >= cx and pointer_x < cx + cell_w and
            pointer_y >= cy and pointer_y < cy + LAUNCHER_ROW_H;
        if (is_hover) {
            c.cairo_set_source_rgba(cr, 0.25, 0.45, 0.9, 0.15);
            main.roundedRect(cr, @floatFromInt(cx + 2), @floatFromInt(cy + 2), @floatFromInt(cell_w - 4), @floatFromInt(LAUNCHER_ROW_H - 4), 8.0);
            c.cairo_fill(cr);
            launcher_hover_idx = abs_idx;
        }

        // App icon
        const icon_surf = icon.load(@ptrCast(&e.icon_name), LAUNCHER_ICON_SIZE);
        c.cairo_set_source_surface(cr, icon_surf, @floatFromInt(cx + @divTrunc(cell_w - LAUNCHER_ICON_SIZE, 2)), @floatFromInt(cy + 4));
        c.cairo_paint(cr);

        // App name
        const name_ptr: [*:0]const u8 = @ptrCast(&e.name);
        _ = panel_mod.widgetText(cr, name_ptr, cx + 4, cy + LAUNCHER_ROW_H - 4, "Inter 9", 0.85, 0.85, 0.88);
    }
}

pub fn handleClick(x: i32, y: i32, panel_width: i32, panel_height: i32) bool {
    const r = launcherRect(panel_width, panel_height);

    if (x < r.x or x > r.x + r.w or y < r.y or y > r.y + r.h) {
        launcher_open = false;
        return true;
    }

    const cell_w = @divTrunc(r.w - LAUNCHER_PAD * 2, LAUNCHER_COLS);
    const col = @divTrunc(x - r.x - LAUNCHER_PAD, cell_w);
    const row = @divTrunc(y - r.y - LAUNCHER_HEADER_H, LAUNCHER_ROW_H);
    if (col < 0 or col >= LAUNCHER_COLS or row < 0) return false;

    const abs_idx = launcher_scroll * LAUNCHER_COLS + row * LAUNCHER_COLS + col;
    if (abs_idx < 0 or abs_idx >= entry_count) return false;

    const e = &entries[@intCast(abs_idx)];
    var cmd: [280]u8 = std.mem.zeroes([280]u8);
    _ = std.fmt.bufPrintZ(&cmd, "{s} &", .{std.mem.sliceTo(&e.exec, 0)}) catch return false;
    _ = panel_mod.spawnCmd(@ptrCast(&cmd));
    launcher_open = false;
    return true;
}

pub fn handleScroll(delta: i32) void {
    const total_rows = @divTrunc(entry_count + LAUNCHER_COLS - 1, LAUNCHER_COLS);
    if (delta > 0) {
        launcher_scroll = @max(0, launcher_scroll - 1);
    } else if (delta < 0) {
        launcher_scroll = @min(@max(0, total_rows - 1), launcher_scroll + 1);
    }
}

/// Toggle the launcher in OCWS mode (from dock button).
pub fn toggleOcws() void {
    ocws_mode = true;
    entries_scanned = false;
    entry_count = 0;
    launcher_open = !launcher_open;
    if (launcher_open) {
        ensureEntries();
        launcher_hover_idx = -1;
        launcher_scroll = 0;
    }
}

/// Toggle the launcher in generic mode (from panel widget).
pub fn toggleGeneric() void {
    ocws_mode = false;
    entries_scanned = false;
    entry_count = 0;
    launcher_open = !launcher_open;
    if (launcher_open) {
        ensureEntries();
        launcher_hover_idx = -1;
        launcher_scroll = 0;
    }
}
