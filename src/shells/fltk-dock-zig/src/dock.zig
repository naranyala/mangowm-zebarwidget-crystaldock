const std = @import("std");
const c = @import("c.zig").c;

const toplevel = @import("toplevel.zig");
const icon = @import("icon.zig");

const PAD = 8;
const FOCUS_BAR_H = 3;

pub const DOCK_ICON_SIZE = 28;

fn iconX(slot_idx: i32, start_x: i32) i32 {
    return start_x + slot_idx * (DOCK_ICON_SIZE + PAD);
}

pub fn draw(
    cr: *c.cairo_t,
    w: i32,
    h: i32,
    tops: []toplevel.ToplevelInfo,
    top_count: i32,
    hover_idx: i32,
) void {
    // Background gradient
    const grad = c.cairo_pattern_create_linear(0, 0, 0, h);
    c.cairo_pattern_add_color_stop_rgba(grad, 0, 0.08, 0.08, 0.10, 1);
    c.cairo_pattern_add_color_stop_rgba(grad, 1, 0.05, 0.05, 0.07, 1);
    c.cairo_set_source(cr, grad);
    c.cairo_paint(cr);
    c.cairo_pattern_destroy(grad);

    // Top border line
    c.cairo_set_source_rgb(cr, 0.25, 0.25, 0.27);
    c.cairo_set_line_width(cr, 1);
    c.cairo_move_to(cr, 0, 0.5);
    c.cairo_line_to(cr, w, 0.5);
    c.cairo_stroke(cr);

    const cy = @divTrunc(h - DOCK_ICON_SIZE, 2);

    // Center the running-apps icon row horizontally
    const slot = DOCK_ICON_SIZE + PAD;
    const total_w: i32 = if (top_count > 0) top_count * slot - PAD else 0;
    var start_x = @divTrunc(w - total_w, 2);
    if (start_x < 0) start_x = 0;

    for (0..@intCast(top_count)) |i| {
        const x = iconX(@intCast(i), start_x);
        const icon_y = cy;

        const app_id_slice = tops[i].app_id[0..std.mem.indexOfScalar(u8, &tops[i].app_id, 0) orelse tops[i].app_id.len];
        const title_slice = tops[i].title[0..std.mem.indexOfScalar(u8, &tops[i].title, 0) orelse tops[i].title.len];
        const name = if (app_id_slice.len > 0) app_id_slice else title_slice;

        const icon_surf = icon.load(@ptrCast(name.ptr), DOCK_ICON_SIZE) orelse
            icon.fallback(@ptrCast(name.ptr), DOCK_ICON_SIZE);

        const surf = icon_surf;

        // Hover highlight
        if (@as(i32, @intCast(i)) == hover_idx) {
            c.cairo_set_source_rgba(cr, 1, 1, 1, 0.12);
            c.cairo_rectangle(cr, x - 4, icon_y - 4, DOCK_ICON_SIZE + 8, DOCK_ICON_SIZE + 8);
            c.cairo_fill(cr);
        }

        // Draw the icon
        c.cairo_set_source_surface(cr, surf, x, icon_y);
        c.cairo_paint(cr);

        // Focus indicator bar
        if (tops[i].focused) {
            c.cairo_set_source_rgb(cr, 0.3, 0.5, 0.9);
            c.cairo_rectangle(cr, x + 2, cy - FOCUS_BAR_H, DOCK_ICON_SIZE - 4, FOCUS_BAR_H);
            c.cairo_fill(cr);
        }
    }
}

pub fn iconAt(w: i32, _: i32, _: []toplevel.ToplevelInfo, top_count: i32, mouse_x: i32) i32 {
    const slot = DOCK_ICON_SIZE + PAD;
    const total_w: i32 = if (top_count > 0) top_count * slot - PAD else 0;
    var start_x = @divTrunc(w - total_w, 2);
    if (start_x < 0) start_x = 0;

    for (0..@intCast(top_count)) |i| {
        const x = iconX(@intCast(i), start_x);
        if (mouse_x >= x and mouse_x < x + DOCK_ICON_SIZE + PAD) return @intCast(i);
    }
    return -1;
}
