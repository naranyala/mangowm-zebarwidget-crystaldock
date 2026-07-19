const std = @import("std");
const c = @import("c.zig").c;

const toplevel = @import("shellcore").toplevel;
const icon = @import("icon.zig");
const theme = @import("theme.zig");

const PAD = 8;
const FOCUS_BAR_H = 3;

pub var DOCK_ICON_SIZE: i32 = 28;

pub const pinned_apps = [_][]const u8{ "foot", "firefox", "nemo" };

pub var persistent_order: [100][128]u8 = std.mem.zeroes([100][128]u8);
pub var persistent_count: usize = 0;
pub var order_initialized: bool = false;

pub fn initOrder() void {
    if (order_initialized) return;
    for (pinned_apps) |app| {
        @memcpy(persistent_order[persistent_count][0..app.len], app);
        persistent_order[persistent_count][app.len] = 0;
        persistent_count += 1;
    }
    order_initialized = true;
}

pub fn launchPinned(index: usize) void {
    if (index < persistent_count) {
        const app = std.mem.sliceTo(&persistent_order[index], 0);
        var buf: [512]u8 = undefined;
        const cmd = std.fmt.bufPrintZ(&buf, "{s} &", .{app}) catch |err| {
            std.log.err("app exec format error: {}", .{err});
            return;
        };
        const rc = c.system(cmd.ptr);
    if (rc != 0) std.log.warn("dock: '{s}' exited with code {d}", .{ app, rc });
    }
}

pub fn draw(
    cr: *c.cairo_t,
    w: i32,
    h: i32,
    tops: []toplevel.ToplevelInfo,
    top_count: i32,
    hover_idx: i32,
    mouse_x: f64,
) void {
    // Map hover_idx to items array index for visual feedback
    var hovered_g: i32 = -1;
    if (hover_idx >= 1000) {
        hovered_g = @intCast(hover_idx - 1000);
    }
    initOrder();
    
    // Background gradient
    const t = &theme.current;
    const grad = c.cairo_pattern_create_linear(0, 0, 0, @floatFromInt(h));
    c.cairo_pattern_add_color_stop_rgba(grad, 0, t.bg_color[0], t.bg_color[1], t.bg_color[2], t.bg_color[3]);
    c.cairo_pattern_add_color_stop_rgba(grad, 1, t.bg_gradient_end[0], t.bg_gradient_end[1], t.bg_gradient_end[2], t.bg_gradient_end[3]);
    c.cairo_set_source(cr, grad);
    c.cairo_paint(cr);
    c.cairo_pattern_destroy(grad);

    // Top border line
    theme.setSource(cr, t.border_color);
    c.cairo_set_line_width(cr, 1);
    c.cairo_move_to(cr, 0, 0.5);
    c.cairo_line_to(cr, @floatFromInt(w), 0.5);
    c.cairo_stroke(cr);

    // ===== running-app icons (centered) =====
    const DockItem = struct {
        app_id: []const u8,
        top_idx: ?usize,
        count: u32,
        focused: bool,
    };

    var items: [100]DockItem = undefined;
    var num_items: usize = 0;

    for (0..persistent_count) |i| {
        if (num_items >= items.len) break;
        items[num_items] = .{
            .app_id = std.mem.sliceTo(&persistent_order[i], 0),
            .top_idx = null,
            .count = 0,
            .focused = false,
        };
        num_items += 1;
    }

    // Grouping by app_id
    for (0..@intCast(top_count)) |i| {
        const app_id = tops[i].app_id[0..std.mem.indexOfScalar(u8, &tops[i].app_id, 0) orelse tops[i].app_id.len];
        var found = false;
        for (0..num_items) |g| {
            if (std.mem.eql(u8, app_id, items[g].app_id) or 
                (std.mem.eql(u8, app_id, "foot-term") and std.mem.eql(u8, items[g].app_id, "foot"))) // hack for foot
            {
                if (items[g].count == 0) items[g].top_idx = i;
                items[g].count += 1;
                if (tops[i].focused) items[g].focused = true;
                found = true;
                break;
            }
        }
        if (!found) {
            // Running app not in the pinned order: show it in the dock for this
            // frame, but do NOT mutate persistent_order — otherwise simply
            // launching an app would permanently pin it (#58). Pinning is an
            // explicit user action (pinApp/unpinAt), not a side effect of draw.
            if (num_items < items.len) {
                items[num_items] = .{
                    .app_id = app_id,
                    .top_idx = i,
                    .count = 1,
                    .focused = tops[i].focused,
                };
                num_items += 1;
            }
        }
    }

    // Parabolic magnification sizing
    var widths = std.mem.zeroes([100]f64);
    var total_w: f64 = 0;
    const slot: f64 = DOCK_ICON_SIZE + PAD;
    const unscaled_total: f64 = if (num_items > 0) @as(f64, @floatFromInt(num_items)) * slot - PAD else 0;
    const toggles_w: f64 = PAD * 4.0 + @as(f64, @floatFromInt(DOCK_ICON_SIZE * 3));
    const unscaled_block_w = unscaled_total + toggles_w;
    const unscaled_start_x: f64 = @max(0, (@as(f64, @floatFromInt(w)) - unscaled_block_w) / 2.0);

    for (0..num_items) |g| {
        const unscaled_x = unscaled_start_x + @as(f64, @floatFromInt(g)) * slot + (@as(f64, @floatFromInt(DOCK_ICON_SIZE)) / 2.0);
        var scale: f64 = 1.0;
        if (mouse_x >= 0) {
            const dist = mouse_x - unscaled_x;
            scale += 1.0 * std.math.exp(-(dist * dist) / 4000.0);
        }
        widths[g] = DOCK_ICON_SIZE * scale;
        total_w += widths[g] + PAD;
    }
    if (num_items > 0) total_w -= PAD;

    const block_w = total_w + toggles_w;
    const current_x = @max(0, (@as(f64, @floatFromInt(w)) - block_w) / 2.0);

    var app_x = current_x;

    for (0..num_items) |g| {
        const item = items[g];
        // Clamp the drawn icon so the parabolic magnification never overflows
        // the dock height (issue #22). The zoom feel is preserved up to the
        // dock's available space, then capped.
        const max_icon: f64 = @as(f64, @floatFromInt(h)) - 6.0;
        const icon_w = @min(widths[g], max_icon);
        const x = app_x;
        const icon_y = @as(f64, @floatFromInt(h)) - icon_w - 6.0;

        const name_slice = if (item.top_idx) |idx|
            if (tops[idx].app_id[0] != 0) tops[idx].app_id[0..std.mem.indexOfScalar(u8, &tops[idx].app_id, 0) orelse tops[idx].app_id.len] else tops[idx].title[0..std.mem.indexOfScalar(u8, &tops[idx].title, 0) orelse tops[idx].title.len]
        else item.app_id;

        // Copy into a null-terminated buffer before handing to icon.load so we
        // never rely on the backing buffer being NUL-terminated (issue #21).
        var name_buf: [256]u8 = std.mem.zeroes([256]u8);
        const name_z = std.fmt.bufPrintZ(&name_buf, "{s}", .{name_slice}) catch "unknown";
        const icon_surf = icon.load(name_z, 128);

        c.cairo_save(cr);
        c.cairo_translate(cr, x, icon_y);
        const scale_factor = icon_w / 128.0;
        c.cairo_scale(cr, scale_factor, scale_factor);
        c.cairo_set_source_surface(cr, icon_surf, 0, 0);
        c.cairo_paint(cr);
        c.cairo_restore(cr);

        // Hover highlight: translucent glow behind the hovered icon
        if (hovered_g >= 0 and @as(i32, @intCast(g)) == hovered_g) {
            c.cairo_set_source_rgba(cr, t.accent_color[0], t.accent_color[1], t.accent_color[2], 0.15);
            c.cairo_arc(cr, x + icon_w / 2.0, icon_y + icon_w / 2.0, icon_w / 2.0 + 4.0, 0, 2.0 * std.math.pi);
            c.cairo_fill(cr);
        }

        // Multi-Window Indicators (Dots/Pill)
        const count = item.count;
        if (count > 0) {
            const dot_spacing = 8.0;
            const has_focused = item.focused;
            
            // A focused app gets a wide "pill" (takes space of 2 dots)
            const pill_width = 10.0;
            const extra_width = if (has_focused) @as(f64, pill_width - 3.0) else @as(f64, 0.0);
            const total_dots_w = @as(f64, @floatFromInt(count - 1)) * dot_spacing + extra_width;
            var current_dot_x = x + icon_w / 2.0 - total_dots_w / 2.0;

            for (0..count) |d| {
                const is_active_dot = has_focused and d == 0; // represent active window with first indicator
                if (is_active_dot) {
                    c.cairo_set_source_rgba(cr, t.accent_color[0], t.accent_color[1], t.accent_color[2], 0.9);
                    c.cairo_new_sub_path(cr);
                    c.cairo_arc(cr, current_dot_x, @as(f64, @floatFromInt(h)) - 3.0, 1.5, std.math.pi / 2.0, 3.0 * std.math.pi / 2.0);
                    c.cairo_arc(cr, current_dot_x + pill_width - 3.0, @as(f64, @floatFromInt(h)) - 3.0, 1.5, -std.math.pi / 2.0, std.math.pi / 2.0);
                    c.cairo_close_path(cr);
                    current_dot_x += dot_spacing + (pill_width - 3.0);
                } else {
                    c.cairo_set_source_rgba(cr, 0.8, 0.8, 0.8, 0.6);
                    c.cairo_arc(cr, current_dot_x, @as(f64, @floatFromInt(h)) - 3.0, 1.5, 0, 2.0 * std.math.pi);
                    current_dot_x += dot_spacing;
                }
                c.cairo_fill(cr);
            }
        }

        app_x += icon_w + PAD;
    }

    // ---- Separated bar: settings + app-launcher toggles ----
    // A vertical divider separates the running-app icons from the fixed
    // toggles, which are then placed like pinned icons on the right.
    const icon_right = current_x + total_w;
    const toggle_start = icon_right + PAD;
    const divider_x = icon_right + PAD / 2.0;
    theme.setSource(cr, t.border_color);
    c.cairo_set_line_width(cr, 1);
    c.cairo_move_to(cr, divider_x, 6.0);
    c.cairo_line_to(cr, divider_x, @as(f64, @floatFromInt(h)) - 6.0);
    c.cairo_stroke(cr);

    const tcy = h - DOCK_ICON_SIZE - 6;

    // Settings toggle
    const settings_x = toggle_start;
    const settings_surf = icon.load("preferences-system", DOCK_ICON_SIZE);
    c.cairo_set_source_surface(cr, settings_surf, settings_x, @floatFromInt(tcy));
    c.cairo_paint(cr);

    // App-launcher toggle (Plank/Crystal-Dock equivalent): opens the system
    // app launcher so any installed application can be launched even if it is
    // not pinned. Placed to the right of the settings toggle.
    const launcher_x = settings_x + DOCK_ICON_SIZE + PAD;
    const launcher_surf = icon.load("view-app-grid-symbolic", DOCK_ICON_SIZE);
    c.cairo_set_source_surface(cr, launcher_surf, launcher_x, @floatFromInt(tcy));
    c.cairo_paint(cr);

    // Home toggle — shows the full app grid in a floating panel above the dock.
    const home_x = launcher_x + DOCK_ICON_SIZE + PAD;
    const home_surf = icon.load("applications-other", DOCK_ICON_SIZE);
    c.cairo_set_source_surface(cr, home_surf, home_x, @floatFromInt(tcy));
    c.cairo_paint(cr);
}

pub fn iconAt(w: i32, _: i32, tops: []toplevel.ToplevelInfo, top_count: i32, mouse_x: i32) i32 {
    const mx: f64 = @floatFromInt(mouse_x);
    initOrder();
    
    const DockItem = struct {
        app_id: []const u8,
        top_idx: ?usize,
    };
    var items: [100]DockItem = undefined;
    var num_items: usize = 0;
    
    for (0..persistent_count) |i| {
        items[num_items] = .{ .app_id = std.mem.sliceTo(&persistent_order[i], 0), .top_idx = null };
        num_items += 1;
    }
    
    for (0..@intCast(top_count)) |i| {
        const app_id = tops[i].app_id[0..std.mem.indexOfScalar(u8, &tops[i].app_id, 0) orelse tops[i].app_id.len];
        var found = false;
        for (0..num_items) |g| {
            if (std.mem.eql(u8, app_id, items[g].app_id) or 
                (std.mem.eql(u8, app_id, "foot-term") and std.mem.eql(u8, items[g].app_id, "foot")))
            {
                if (items[g].top_idx == null) items[g].top_idx = i;
                found = true;
                break;
            }
        }
        if (!found) {
            // Running app not in the pinned order: register it for this hit-test
            // only. Do NOT append to persistent_order (#58) — pinning is an
            // explicit user action, not a side effect of iconAt.
            items[num_items] = .{ .app_id = app_id, .top_idx = i };
            num_items += 1;
        }
    }

    var widths = std.mem.zeroes([100]f64);
    var total_w: f64 = 0;
    const slot: f64 = DOCK_ICON_SIZE + PAD;
    const unscaled_total: f64 = if (num_items > 0) @as(f64, @floatFromInt(num_items)) * slot - PAD else 0;
    const toggles_w: f64 = PAD * 4.0 + @as(f64, @floatFromInt(DOCK_ICON_SIZE * 3));
    const unscaled_block_w = unscaled_total + toggles_w;
    const unscaled_start_x: f64 = @max(0, (@as(f64, @floatFromInt(w)) - unscaled_block_w) / 2.0);

    for (0..num_items) |g| {
        const unscaled_x = unscaled_start_x + @as(f64, @floatFromInt(g)) * slot + (@as(f64, @floatFromInt(DOCK_ICON_SIZE)) / 2.0);
        var scale: f64 = 1.0;
        if (mx >= 0) {
            const dist = mx - unscaled_x;
            scale += 1.0 * std.math.exp(-(dist * dist) / 4000.0);
        }
        widths[g] = DOCK_ICON_SIZE * scale;
        total_w += widths[g] + PAD;
    }
    if (num_items > 0) total_w -= PAD;

    const block_w = total_w + toggles_w;
    const icon_right = @max(0, (@as(f64, @floatFromInt(w)) - block_w) / 2.0) + total_w;
    const toggle_start = icon_right + PAD;
    const settings_x = toggle_start;
    const launcher_x = settings_x + @as(f64, @floatFromInt(DOCK_ICON_SIZE)) + PAD;
    const home_x = launcher_x + @as(f64, @floatFromInt(DOCK_ICON_SIZE)) + PAD;

    // Check the settings toggle, placed to the right of the running apps,
    // matching the draw() geometry.
    if (mx >= settings_x and mx < settings_x + @as(f64, @floatFromInt(DOCK_ICON_SIZE))) {
        return -2; // settings toggle
    }

    // Check the app-launcher toggle (Plank/Crystal-Dock equivalent): opens
    // the system-wide launcher so unpinned apps can be launched.
    if (mx >= launcher_x and mx < launcher_x + @as(f64, @floatFromInt(DOCK_ICON_SIZE))) {
        return -4; // app-launcher toggle
    }

    // Check the home toggle: opens the full app grid in a floating launcher.
    if (mx >= home_x and mx < home_x + @as(f64, @floatFromInt(DOCK_ICON_SIZE))) {
        return -5; // home / app-grid toggle
    }

    var app_x = @max(0, (@as(f64, @floatFromInt(w)) - block_w) / 2.0);
    for (0..num_items) |g| {
        const icon_w = widths[g];
        const half_w = icon_w / 2.0;
        const icon_center = app_x + half_w;

        // If the mouse is within bounds of this icon slot
        if (mx >= icon_center - half_w and mx <= icon_center + half_w) {
            if (items[g].top_idx) |idx| {
                return @intCast(idx); // return valid toplevel index
            } else {
                return @as(i32, @intCast(g)) + 1000; // special code: 1000 + group index
            }
        }

        app_x += icon_w + PAD;
    }

    return -1;
}

pub fn groupAt(w: i32, mouse_x: i32) i32 {
    const mx: f64 = @floatFromInt(mouse_x);
    if (persistent_count == 0) return -1;

    var widths = std.mem.zeroes([100]f64);
    var total_w: f64 = 0;
    const slot: f64 = DOCK_ICON_SIZE + PAD;
    const unscaled_total: f64 = @as(f64, @floatFromInt(persistent_count)) * slot - PAD;
    const toggles_w: f64 = PAD * 4.0 + @as(f64, @floatFromInt(DOCK_ICON_SIZE * 3));
    const unscaled_block_w = unscaled_total + toggles_w;
    const unscaled_start_x: f64 = @max(0, (@as(f64, @floatFromInt(w)) - unscaled_block_w) / 2.0);

    for (0..persistent_count) |g| {
        const unscaled_x = unscaled_start_x + @as(f64, @floatFromInt(g)) * slot + (@as(f64, @floatFromInt(DOCK_ICON_SIZE)) / 2.0);
        var scale: f64 = 1.0;
        if (mx >= 0) {
            const dist = mx - unscaled_x;
            scale += 1.0 * std.math.exp(-(dist * dist) / 4000.0);
        }
        widths[g] = DOCK_ICON_SIZE * scale;
        total_w += widths[g] + PAD;
    }
    total_w -= PAD;

    const block_w = total_w + toggles_w;
    var current_x = @max(0, (@as(f64, @floatFromInt(w)) - block_w) / 2.0);

    for (0..persistent_count) |g| {
        const icon_w = widths[g];
        const half_w = icon_w / 2.0;
        const icon_center = current_x + half_w;

        if (mx >= icon_center - half_w and mx <= icon_center + half_w) {
            return @intCast(g);
        }
        current_x += icon_w + PAD;
    }
    return -1;
}

pub fn swapGroups(idxA: usize, idxB: usize) void {
    if (idxA >= persistent_count or idxB >= persistent_count) return;
    var tmp: [128]u8 = std.mem.zeroes([128]u8);
    @memcpy(&tmp, &persistent_order[idxA]);
    @memcpy(&persistent_order[idxA], &persistent_order[idxB]);
    @memcpy(&persistent_order[idxB], &tmp);
}

// ---- Runtime pinned-app management (settings panel) ----

/// Pin an app by name. Returns true if added (false if already present or full).
pub fn pinApp(app: []const u8) bool {
    if (app.len == 0 or app.len >= 128) return false;
    initOrder();
    for (0..persistent_count) |i| {
        if (std.mem.eql(u8, std.mem.sliceTo(&persistent_order[i], 0), app)) return false;
    }
    if (persistent_count >= persistent_order.len) return false;
    @memcpy(persistent_order[persistent_count][0..app.len], app);
    persistent_order[persistent_count][app.len] = 0;
    persistent_count += 1;
    return true;
}

/// Unpin the group at index `idx`. Returns true on success.
pub fn unpinAt(idx: usize) bool {
    if (idx >= persistent_count) return false;
    var i = idx;
    while (i + 1 < persistent_count) : (i += 1) {
        @memcpy(&persistent_order[i], &persistent_order[i + 1]);
    }
    persistent_count -= 1;
    return true;
}

/// True if `app` is currently pinned.
pub fn isPinned(app: []const u8) bool {
    for (0..persistent_count) |i| {
        if (std.mem.eql(u8, std.mem.sliceTo(&persistent_order[i], 0), app)) return true;
    }
    return false;
}

/// Serialize the pinned-app order into `buf` as newline-separated names.
/// Returns the number of bytes written (excluding a trailing nul).
// Null-terminated name of the pinned app at `idx` (for UI display).
pub fn pinnedName(idx: usize) [*:0]const u8 {
    if (idx >= persistent_count) return @ptrCast("");
    return @ptrCast(&persistent_order[idx]);
}

pub fn writePinned(buf: []u8) usize {
    var len: usize = 0;
    for (0..persistent_count) |i| {
        const name = std.mem.sliceTo(&persistent_order[i], 0);
        if (len > 0) {
            if (len >= buf.len) break;
            buf[len] = '\n';
            len += 1;
        }
        const n = @min(name.len, buf.len - len);
        @memcpy(buf[len .. len + n], name[0..n]);
        len += n;
    }
    return len;
}

/// Replace the pinned order from a newline-separated name list.
pub fn loadPinned(list: []const u8) void {
    persistent_count = 0;
    order_initialized = true;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= list.len) : (i += 1) {
        const eof = i == list.len;
        if (eof or list[i] == '\n') {
            const name = list[start..i];
            if (name.len > 0 and name.len < 128 and persistent_count < persistent_order.len) {
                @memcpy(persistent_order[persistent_count][0..name.len], name);
                persistent_order[persistent_count][name.len] = 0;
                persistent_count += 1;
            }
            start = i + 1;
        }
    }
}

// Replicate iconAt's layout math to derive the on-screen positions of a given
// number of dock icons plus the separated-bar settings/launcher toggles, for a
// specified probe position `mx`. Mirrors the geometry in iconAt() exactly.
fn testDockLayout(w: i32, num_items: usize, mx: f64) struct {
    widths: [100]f64,
    app_start: f64,
    settings_x: f64,
} {
    var widths = std.mem.zeroes([100]f64);
    var total_w: f64 = 0;
    const slot: f64 = DOCK_ICON_SIZE + PAD;
    const unscaled_total: f64 = if (num_items > 0) @as(f64, @floatFromInt(num_items)) * slot - PAD else 0;
    const toggles_w: f64 = PAD * 4.0 + @as(f64, @floatFromInt(DOCK_ICON_SIZE * 3));
    const unscaled_block_w = unscaled_total + toggles_w;
    const unscaled_start_x: f64 = @max(0, (@as(f64, @floatFromInt(w)) - unscaled_block_w) / 2.0);
    for (0..num_items) |g| {
        const unscaled_x = unscaled_start_x + @as(f64, @floatFromInt(g)) * slot + (@as(f64, @floatFromInt(DOCK_ICON_SIZE)) / 2.0);
        var scale: f64 = 1.0;
        if (mx >= 0) {
            const dist = mx - unscaled_x;
            scale += 1.0 * std.math.exp(-(dist * dist) / 4000.0);
        }
        widths[g] = DOCK_ICON_SIZE * scale;
        total_w += widths[g] + PAD;
    }
    if (num_items > 0) total_w -= PAD;
    const block_w = total_w + toggles_w;
    const app_start = @max(0, (@as(f64, @floatFromInt(w)) - block_w) / 2.0);
    const icon_right = app_start + total_w;
    const toggle_start = icon_right + PAD;
    return .{
        .widths = widths,
        .app_start = app_start,
        .settings_x = toggle_start,
    };
}

test "dock iconAt miss" {
    persistent_count = 0;
    order_initialized = true; // suppress initOrder seeding
    @memcpy(&persistent_order[0], "foot" ++ ("\x00" ** 124));
    @memcpy(&persistent_order[1], "firefox" ++ ("\x00" ** 121));
    persistent_count = 2;

    var tops: [10]toplevel.ToplevelInfo = undefined;
    for (0..10) |i| tops[i] = .{};

    const w = 1920;
    // Far left of the centered dock is a miss.
    try std.testing.expectEqual(@as(i32, -1), iconAt(w, 48, &tops, 0, 0));
}

test "dock iconAt hits pinned groups" {
    persistent_count = 0;
    order_initialized = true;
    @memcpy(&persistent_order[0], "foot" ++ ("\x00" ** 124));
    @memcpy(&persistent_order[1], "firefox" ++ ("\x00" ** 121));
    persistent_count = 2;

    var tops: [10]toplevel.ToplevelInfo = undefined;
    for (0..10) |i| tops[i] = .{};

    const w = 1920;

    // Probe the center of group 0 (no running window => 1000 + group).
    const l0 = testDockLayout(w, 2, -1); // unscaled centers
    const c0: i32 = @intFromFloat(l0.app_start + l0.widths[0] / 2.0);
    try std.testing.expectEqual(@as(i32, 1000), iconAt(w, 48, &tops, 0, c0));

    const c1: i32 = @intFromFloat(l0.app_start + l0.widths[0] + PAD + l0.widths[1] / 2.0);
    try std.testing.expectEqual(@as(i32, 1001), iconAt(w, 48, &tops, 0, c1));
}

test "dock iconAt maps running window" {
    persistent_count = 0;
    order_initialized = true;
    @memcpy(&persistent_order[0], "foot" ++ ("\x00" ** 124));
    persistent_count = 1;

    var tops: [10]toplevel.ToplevelInfo = undefined;
    for (0..10) |i| tops[i] = .{};
    @memcpy(tops[0].app_id[0..4], "foot");

    const w = 1920;
    const l = testDockLayout(w, 1, -1);
    const c0: i32 = @intFromFloat(l.app_start + l.widths[0] / 2.0);
    // "foot" is running as tops[0], so it maps to toplevel index 0.
    try std.testing.expectEqual(@as(i32, 0), iconAt(w, 48, &tops, 1, c0));
}

test "dock iconAt settings and launcher toggles" {
    persistent_count = 0;
    order_initialized = true;
    @memcpy(&persistent_order[0], "foot" ++ ("\x00" ** 124));
    @memcpy(&persistent_order[1], "firefox" ++ ("\x00" ** 121));
    persistent_count = 2;

    var tops: [10]toplevel.ToplevelInfo = undefined;
    for (0..10) |i| tops[i] = .{};

    const w = 1920;

    // Settings toggle center: probe with mx at the settings icon center.
    // Because widths depend on mx (gaussian), solve iteratively: the toggles are
    // far from the apps so scaling there is ~1.0 regardless.
    const l = testDockLayout(w, 2, 100000.0); // mx far away => all scales ~1.0
    const settings_probe: i32 = @intFromFloat(l.settings_x + @as(f64, @floatFromInt(DOCK_ICON_SIZE)) / 2.0);
    try std.testing.expectEqual(@as(i32, -2), iconAt(w, 48, &tops, 0, settings_probe));
}

test "dock groupAt logic" {
    persistent_count = 0;
    
    // Add 3 persistent groups
    @memcpy(&persistent_order[0], "foot" ++ ("\x00" ** 124));
    @memcpy(&persistent_order[1], "firefox" ++ ("\x00" ** 121));
    @memcpy(&persistent_order[2], "geary" ++ ("\x00" ** 123));
    persistent_count = 3;

    const w: i32 = 1920;
    const icon_sz: f64 = @floatFromInt(DOCK_ICON_SIZE);
    const slot: f64 = icon_sz + PAD;
    const toggles_w: f64 = PAD * 4.0 + @as(f64, @floatFromInt(DOCK_ICON_SIZE * 3));
    const unscaled_total: f64 = 3.0 * slot - PAD + toggles_w;
    const start_x: f64 = @max(0, (@as(f64, @floatFromInt(w)) - unscaled_total) / 2.0);

    // Hit group 0 (its unscaled center).
    const c0: i32 = @intFromFloat(start_x + icon_sz / 2.0);
    try std.testing.expectEqual(@as(i32, 0), groupAt(w, c0));

    // Hit group 1 (its unscaled center).
    const c1: i32 = @intFromFloat(start_x + slot + icon_sz / 2.0);
    try std.testing.expectEqual(@as(i32, 1), groupAt(w, c1));

    // Far to the left of the centered dock is a miss.
    try std.testing.expectEqual(@as(i32, -1), groupAt(w, 0));
}

test "dock swapGroups logic" {
    persistent_count = 0;
    @memcpy(&persistent_order[0], "A" ++ ("\x00" ** 127));
    @memcpy(&persistent_order[1], "B" ++ ("\x00" ** 127));
    @memcpy(&persistent_order[2], "C" ++ ("\x00" ** 127));
    persistent_count = 3;

    swapGroups(0, 2);
    try std.testing.expectEqualStrings("C", std.mem.sliceTo(&persistent_order[0], 0));
    try std.testing.expectEqualStrings("B", std.mem.sliceTo(&persistent_order[1], 0));
    try std.testing.expectEqualStrings("A", std.mem.sliceTo(&persistent_order[2], 0));

    // Invalid swap should not crash
    swapGroups(0, 999);
}

test "dock initOrder logic" {
    persistent_count = 0;
    order_initialized = false;
    
    initOrder();
    
    try std.testing.expectEqual(@as(usize, 3), persistent_count);
    try std.testing.expectEqualStrings("foot", std.mem.sliceTo(&persistent_order[0], 0));
    try std.testing.expectEqualStrings("firefox", std.mem.sliceTo(&persistent_order[1], 0));
    try std.testing.expectEqualStrings("nemo", std.mem.sliceTo(&persistent_order[2], 0));
}

test "dock draw/iconAt must not persist running apps (#58)" {
    persistent_count = 0;
    order_initialized = true;
    @memcpy(&persistent_order[0], "foot" ++ ("\x00" ** 124));
    persistent_count = 1;

    var tops: [10]toplevel.ToplevelInfo = undefined;
    for (0..10) |i| tops[i] = .{};
    // A running window for an app that is NOT pinned.
    @memcpy(tops[0].app_id[0..8], "unpinned");

    // iconAt sees the running window (returns its toplevel index 0)...
    const w: i32 = 1920;
    const l = testDockLayout(w, 2, -1);
    const probe: i32 = @intFromFloat(l.app_start + l.widths[0] + 8 + l.widths[1] / 2.0);
    _ = iconAt(w, 48, &tops, 1, probe);

    // ...but the persistent pinned set must be unchanged.
    try std.testing.expectEqual(@as(usize, 1), persistent_count);
    try std.testing.expectEqualStrings("foot", std.mem.sliceTo(&persistent_order[0], 0));
}

test "dock pin/unpin roundtrip" {
    persistent_count = 0;
    order_initialized = true;

    try std.testing.expectEqual(false, isPinned("geary"));
    try std.testing.expectEqual(true, pinApp("geary"));
    try std.testing.expectEqual(true, isPinned("geary"));
    // Duplicate pin ignored.
    try std.testing.expectEqual(false, pinApp("geary"));

    var buf: [512]u8 = std.mem.zeroes([512]u8);
    const n = writePinned(&buf);
    try std.testing.expectEqualStrings("geary", buf[0..n]);

    // Reload from serialized form.
    loadPinned("geary\nfoot");
    try std.testing.expectEqual(@as(usize, 2), persistent_count);
    try std.testing.expectEqualStrings("geary", std.mem.sliceTo(&persistent_order[0], 0));
    try std.testing.expectEqual(true, unpinAt(0));
    try std.testing.expectEqual(@as(usize, 1), persistent_count);
    try std.testing.expectEqualStrings("foot", std.mem.sliceTo(&persistent_order[0], 0));
}
