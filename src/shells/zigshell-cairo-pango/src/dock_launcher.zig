// dock_launcher.zig — Full-app grid dock launcher
//
// Shows ALL GUI apps from the system app catalog in a scrollable grid,
// rendered in a floating TOP-layer surface above the dock.
// Triggered from a dock icon (home toggle, returns -5 from iconAt).

const std = @import("std");
const c = @import("c.zig").c;
const panel_mod = @import("panel.zig");
const apps_mod = @import("apps");
const icon = @import("icon.zig");
const theme = @import("theme.zig");
const main = @import("main_shell.zig");

pub var launcher_open = false;
pub var launcher_hover_idx: i32 = -1;
pub var launcher_scroll: i32 = 0;

pub const CARD_W: i32 = 520;
pub const CARD_PAD: i32 = 14;
pub const ICON_SIZE: i32 = 48;
pub const ROW_H: i32 = 68;
pub const COLS: i32 = 4;
pub const HEADER_H: i32 = 40;

const MAX_ENTRIES = 256;

const LauncherEntry = struct {
    name: [64]u8 = std.mem.zeroes([64]u8),
    exec: [256]u8 = std.mem.zeroes([256]u8),
    icon_name: [128]u8 = std.mem.zeroes([128]u8),
};

var entries: [MAX_ENTRIES]LauncherEntry = std.mem.zeroes([MAX_ENTRIES]LauncherEntry);
var entry_count: i32 = 0;
var entries_scanned: bool = false;

pub fn ensureEntries() void {
    if (entries_scanned) return;
    entries_scanned = true;
    entry_count = 0;

    const app_list = apps_mod.list();
    for (app_list) |app| {
        if (entry_count >= MAX_ENTRIES) break;
        const app_name = app.name[0..app.name_len];
        const app_exec = app.exec[0..app.exec_len];
        const app_icon = app.icon[0..app.icon_len];
        if (app_name.len == 0 or app_exec.len == 0) continue;

        var e = &entries[@intCast(entry_count)];
        const nlen = @min(app_name.len, e.name.len - 1);
        @memcpy(e.name[0..nlen], app_name[0..nlen]);
        e.name[nlen] = 0;
        const elen = @min(app_exec.len, e.exec.len - 1);
        @memcpy(e.exec[0..elen], app_exec[0..elen]);
        e.exec[elen] = 0;
        const ilen = @min(app_icon.len, e.icon_name.len - 1);
        @memcpy(e.icon_name[0..ilen], app_icon[0..ilen]);
        e.icon_name[ilen] = 0;
        entry_count += 1;
    }
}

pub fn cardHeight(panel_width: i32) i32 {
    _ = panel_width;
    ensureEntries();
    const total_rows = @divTrunc(entry_count + COLS - 1, COLS);
    const max_visible = 6;
    const visible_rows = @min(total_rows, max_visible);
    return HEADER_H + visible_rows * ROW_H + CARD_PAD * 2;
}

pub fn draw(cr: *c.cairo_t, surf_w: i32, surf_h: i32, pointer_x: i32, pointer_y: i32) void {
    ensureEntries();
    if (entry_count == 0) return;

    const t = &theme.current;
    const card_w = @min(CARD_W, surf_w - 20);
    const card_h = surf_h;
    const cx = @divTrunc(surf_w - card_w, 2);
    const cy: i32 = 0;

    // Dark backdrop behind the card
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.25);
    c.cairo_paint(cr);

    // Card background
    c.cairo_set_source_rgba(cr, 0.06, 0.06, 0.09, 0.97);
    main.roundedRect(cr, @floatFromInt(cx), @floatFromInt(cy), @floatFromInt(card_w), @floatFromInt(card_h), 14.0);
    c.cairo_fill(cr);

    // Border glow
    c.cairo_set_source_rgba(cr, t.accent_color[0], t.accent_color[1], t.accent_color[2], 0.25);
    c.cairo_set_line_width(cr, 1.5);
    main.roundedRect(cr, @floatFromInt(cx), @floatFromInt(cy), @floatFromInt(card_w), @floatFromInt(card_h), 14.0);
    c.cairo_stroke(cr);

    // Title
    _ = panel_mod.widgetText(cr, "OCWS Homepage", cx + CARD_PAD, cy + HEADER_H - 6, "Inter Bold 15", 0.95, 0.95, 0.98);

    // App grid
    const cell_w = @divTrunc(card_w - CARD_PAD * 2, COLS);
    const first_visible = launcher_scroll * COLS;
    var abs_idx: i32 = 0;
    abs_idx = first_visible;
    while (abs_idx < entry_count) : (abs_idx += 1) {
        const col = @mod(abs_idx, COLS);
        const row = @divTrunc(abs_idx, COLS) - launcher_scroll;
        if (row < 0) continue;

        const gx = cx + CARD_PAD + col * cell_w;
        const gy = cy + HEADER_H + row * ROW_H;
        if (gy + ROW_H > cy + card_h) break;

        const e = &entries[@intCast(abs_idx)];

        const is_hover = pointer_x >= gx and pointer_x < gx + cell_w and
            pointer_y >= gy and pointer_y < gy + ROW_H;
        if (is_hover) {
            c.cairo_set_source_rgba(cr, t.accent_color[0], t.accent_color[1], t.accent_color[2], 0.15);
            main.roundedRect(cr, @floatFromInt(gx + 2), @floatFromInt(gy + 2), @floatFromInt(cell_w - 4), @floatFromInt(ROW_H - 4), 8.0);
            c.cairo_fill(cr);
            launcher_hover_idx = abs_idx;
        }

        const icon_surf = icon.load(@ptrCast(&e.icon_name), ICON_SIZE);
        c.cairo_set_source_surface(cr, icon_surf, @floatFromInt(gx + @divTrunc(cell_w - ICON_SIZE, 2)), @floatFromInt(gy + 4));
        c.cairo_paint(cr);

        const name_ptr: [*:0]const u8 = @ptrCast(&e.name);
        _ = panel_mod.widgetText(cr, name_ptr, gx + 2, gy + ROW_H - 4, "Inter 9", t.text_color[0], t.text_color[1], t.text_color[2]);
    }
}

pub fn handleClick(x: i32, y: i32, surf_w: i32, surf_h: i32) bool {
    ensureEntries();
    if (entry_count == 0) return false;

    const card_w = @min(CARD_W, surf_w - 20);
    const card_h = surf_h;
    const cx = @divTrunc(surf_w - card_w, 2);
    const cy: i32 = 0;

    // Click outside the card → close
    if (x < cx or x > cx + card_w or y < cy or y > cy + card_h) {
        launcher_open = false;
        return true;
    }

    const cell_w = @divTrunc(card_w - CARD_PAD * 2, COLS);
    const col = @divTrunc(x - cx - CARD_PAD, cell_w);
    const row = @divTrunc(y - cy - HEADER_H, ROW_H);
    if (col < 0 or col >= COLS or row < 0) return false;

    const abs_idx = launcher_scroll * COLS + row * COLS + col;
    if (abs_idx < 0 or abs_idx >= entry_count) return false;

    const e = &entries[@intCast(abs_idx)];
    var cmd: [280]u8 = std.mem.zeroes([280]u8);
    _ = std.fmt.bufPrintZ(&cmd, "{s} &", .{std.mem.sliceTo(&e.exec, 0)}) catch return false;
    _ = panel_mod.spawnCmd(@ptrCast(&cmd));
    launcher_open = false;
    return true;
}

pub fn handleScroll(delta: i32) void {
    ensureEntries();
    const total_rows = @divTrunc(entry_count + COLS - 1, COLS);
    const max_visible = 6;
    if (delta > 0) {
        launcher_scroll = @max(0, launcher_scroll - 1);
    } else if (delta < 0) {
        launcher_scroll = @min(@max(0, total_rows - max_visible), launcher_scroll + 1);
    }
}

pub fn toggle() void {
    launcher_open = !launcher_open;
    if (launcher_open) {
        ensureEntries();
        launcher_hover_idx = -1;
        launcher_scroll = 0;
    }
}
