const std = @import("std");
const c = @import("c.zig").c;
const toplevel = @import("toplevel.zig");
const panel_mod = @import("panel.zig");
const dock_mod = @import("dock.zig");
const icon = @import("icon.zig");

const PANEL_HEIGHT = 36;
const DOCK_HEIGHT = 48;
const MAX_TOPLEVELS = 64;
const MAX_WIDGETS = 64;

// ---- wayland globals (shared) ----
var display: ?*c.wl_display = null;
var compositor: ?*c.wl_compositor = null;
var shm: ?*c.wl_shm = null;
var layer_shell: ?*c.zwlr_layer_shell_v1 = null;
var toplevel_manager: ?*c.zwlr_foreign_toplevel_manager_v1 = null;
var registry: ?*c.wl_registry = null;
var seat: ?*c.wl_seat = null;
var pointer: ?*c.wl_pointer = null;

// ---- surface state ----
const SurfaceState = struct {
    surface: ?*c.wl_surface = null,
    layer_surface: ?*c.zwlr_layer_surface_v1 = null,
    width: i32 = 0,
    height: i32 = 0,
    scale: u32 = 1,
    frame_cb: ?*c.wl_callback = null,
    cairo_surface: ?*c.cairo_surface_t = null,
    cairo_cr: ?*c.cairo_t = null,
    shm_data: ?[*]u8 = null,
    buffer: ?*c.wl_buffer = null,
    buf_width: i32 = 0,
    buf_height: i32 = 0,
    buf_size: usize = 0,
};

var panel_surface = SurfaceState{ .height = PANEL_HEIGHT };
var dock_surface = SurfaceState{ .height = DOCK_HEIGHT };
var dirty = true;
var running = true;
var timer_fd: i32 = -1;

// ---- shared toplevel tracking ----
var toplevels: [MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
var toplevel_count: i32 = 0;

// ---- panel widgets ----
var widgets: [MAX_WIDGETS]panel_mod.Widget = undefined;
var widget_count: i32 = 0;
var widget_x: [MAX_WIDGETS]i32 = undefined;
var pctx: panel_mod.PanelCtx = undefined;

// ---- dock state ----
var dock_hover_idx: i32 = -1;

// ---- pointer state ----
var pointer_x: i32 = 0;
var pointer_y: i32 = 0;
var pointer_on_panel = false;
var pointer_on_dock = false;

// ---- settings state ----
var settings_open = false;
var settings_scroll: i32 = 0;

// ==== WAYLAND CALLBACKS ====

fn toplevelHandleTitle(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, title: [*c]const u8) callconv(.c) void {
    _ = handle;
    const info: *toplevel.ToplevelInfo = @ptrCast(@alignCast(data orelse return));
    const title_str = std.mem.sliceTo(title, 0);
    const len = @min(title_str.len, info.title.len - 1);
    @memcpy(info.title[0..len], title_str[0..len]);
    info.title[len] = 0;
    dirty = true;
}

fn toplevelHandleAppId(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, app_id: [*c]const u8) callconv(.c) void {
    _ = handle;
    const info: *toplevel.ToplevelInfo = @ptrCast(@alignCast(data orelse return));
    const id_str = std.mem.sliceTo(app_id, 0);
    const len = @min(id_str.len, info.app_id.len - 1);
    @memcpy(info.app_id[0..len], id_str[0..len]);
    info.app_id[len] = 0;
    dirty = true;
}

fn toplevelHandleState(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, state: ?*c.wl_array) callconv(.c) void {
    _ = handle;
    const info: *toplevel.ToplevelInfo = @ptrCast(@alignCast(data orelse return));
    info.focused = false;
    info.minimized = false;
    info.maximized = false;
    if (state) |s| {
        const states: [*]u32 = @ptrCast(@alignCast(s.*.data));
        const count = s.*.size / @sizeOf(u32);
        for (0..count) |i| {
            if (states[i] == c.ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED) info.focused = true;
            if (states[i] == c.ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MINIMIZED) info.minimized = true;
        }
    }
    dirty = true;
}

fn toplevelHandleDone(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    _ = handle;
    dirty = true;
}

fn toplevelHandleClosed(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    const idx = toplevel.findIndex(&toplevels, toplevel_count, @ptrCast(handle orelse return));
    if (idx >= 0) {
        toplevel.removeAt(&toplevels, &toplevel_count, idx);
        dirty = true;
    }
}

fn toplevelHandleParent(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, parent: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    _ = handle;
    _ = parent;
}

const toplevel_handle_listener = c.zwlr_foreign_toplevel_handle_v1_listener{
    .title = toplevelHandleTitle,
    .app_id = toplevelHandleAppId,
    .output_enter = struct { fn f(_: ?*anyopaque, _: ?*c.zwlr_foreign_toplevel_handle_v1, _: ?*c.wl_output) callconv(.c) void {} }.f,
    .output_leave = struct { fn f(_: ?*anyopaque, _: ?*c.zwlr_foreign_toplevel_handle_v1, _: ?*c.wl_output) callconv(.c) void {} }.f,
    .state = toplevelHandleState,
    .done = toplevelHandleDone,
    .closed = toplevelHandleClosed,
    .parent = toplevelHandleParent,
};

fn toplevelManagerToplevel(data: ?*anyopaque, manager: ?*c.zwlr_foreign_toplevel_manager_v1, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    _ = manager;
    const idx = toplevel.add(&toplevels, &toplevel_count, @ptrCast(handle orelse return));
    _ = c.zwlr_foreign_toplevel_handle_v1_add_listener(handle, &toplevel_handle_listener, &toplevels[idx]);
    dirty = true;
}

const toplevel_manager_listener = c.zwlr_foreign_toplevel_manager_v1_listener{
    .toplevel = toplevelManagerToplevel,
    .finished = struct { fn f(_: ?*anyopaque, _: ?*c.zwlr_foreign_toplevel_manager_v1) callconv(.c) void {} }.f,
};

// ---- registry ----
fn registryGlobal(data: ?*anyopaque, reg: ?*c.wl_registry, name: u32, iface: [*c]const u8, version: u32) callconv(.c) void {
    _ = data;
    _ = version;
    const iface_str = std.mem.sliceTo(iface, 0);
    if (std.mem.eql(u8, iface_str, "wl_compositor"))
        compositor = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_compositor_interface, 4))
    else if (std.mem.eql(u8, iface_str, "wl_shm"))
        shm = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_shm_interface, 1))
    else if (std.mem.eql(u8, iface_str, "zwlr_layer_shell_v1"))
        layer_shell = @ptrCast(c.wl_registry_bind(reg, name, &c.zwlr_layer_shell_v1_interface, 1))
    else if (std.mem.eql(u8, iface_str, "zwlr_foreign_toplevel_manager_v1")) {
        toplevel_manager = @ptrCast(c.wl_registry_bind(reg, name, &c.zwlr_foreign_toplevel_manager_v1_interface, 3));
        _ = c.zwlr_foreign_toplevel_manager_v1_add_listener(toplevel_manager, &toplevel_manager_listener, null);
    } else if (std.mem.eql(u8, iface_str, "wl_seat"))
        seat = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_seat_interface, 7));
}

const registry_listener = c.wl_registry_listener{
    .global = registryGlobal,
    .global_remove = struct { fn f(_: ?*anyopaque, _: ?*c.wl_registry, _: u32) callconv(.c) void {} }.f,
};

// ---- pointer ----
fn pointerEnter(data: ?*anyopaque, p: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface, x: c.wl_fixed_t, y: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = p;
    _ = serial;
    pointer_x = c.wl_fixed_to_int(x);
    pointer_y = c.wl_fixed_to_int(y);
    pointer_on_panel = (surface == panel_surface.surface);
    pointer_on_dock = (surface == dock_surface.surface);
    if (pointer_on_dock) {
        dock_hover_idx = dock_mod.iconAt(dock_surface.width, dock_surface.height, &toplevels, toplevel_count, pointer_x);
    }
    dirty = true;
}

fn pointerLeave(data: ?*anyopaque, p: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = p;
    _ = serial;
    _ = surface;
    pointer_on_panel = false;
    pointer_on_dock = false;
    dock_hover_idx = -1;
    dirty = true;
}

fn pointerMotion(data: ?*anyopaque, p: ?*c.wl_pointer, time: u32, x: c.wl_fixed_t, y: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = p;
    _ = time;
    pointer_x = c.wl_fixed_to_int(x);
    pointer_y = c.wl_fixed_to_int(y);
    if (pointer_on_dock) {
        const new_idx = dock_mod.iconAt(dock_surface.width, dock_surface.height, &toplevels, toplevel_count, pointer_x);
        if (new_idx != dock_hover_idx) {
            dock_hover_idx = new_idx;
            dirty = true;
        }
    }
}

fn pointerButton(data: ?*anyopaque, p: ?*c.wl_pointer, serial: u32, time: u32, button: u32, state_w: u32) callconv(.c) void {
    _ = data;
    _ = p;
    _ = serial;
    _ = time;
    if (state_w != c.WL_POINTER_BUTTON_STATE_PRESSED) return;

    // Dock click — activate/minimize window
    if (pointer_on_dock) {
        if (dock_hover_idx >= 0 and dock_hover_idx < toplevel_count) {
            const info = &toplevels[@intCast(dock_hover_idx)];
            const handle: ?*c.zwlr_foreign_toplevel_handle_v1 = @ptrCast(@alignCast(info.handle));
            if (info.focused) {
                c.zwlr_foreign_toplevel_handle_v1_set_minimized(handle);
            } else {
                c.zwlr_foreign_toplevel_handle_v1_activate(handle, seat);
            }
            dirty = true;
        }
        return;
    }

    // Panel click — handle widget clicks
    if (pointer_on_panel) {
        // Settings button click (gear icon at far right)
        const settings_x = panel_surface.width - 32;
        if (pointer_x >= settings_x and pointer_x < settings_x + 28) {
            settings_open = !settings_open;
            dirty = true;
            return;
        }

        // Settings menu clicks
        if (settings_open) {
            handleSettingsClick(pointer_x, pointer_y);
            dirty = true;
            return;
        }

        // Widget clicks
        for (0..@intCast(widget_count)) |i| {
            if (pointer_x >= widget_x[i] and pointer_x < widget_x[i] + widgets[i].cached_w) {
                if (widgets[i].click_fn) |fn_ptr| {
                    _ = fn_ptr(&widgets[i], button, pointer_x - widget_x[i], pointer_y);
                }
                dirty = true;
                return;
            }
        }
    }
}

fn handleSettingsClick(x: i32, y: i32) void {
    // Settings menu items
    const menu_items = [_]struct { label: []const u8, action: []const u8 }{
        .{ .label = "Toggle Auto-Hide Dock", .action = "autohide" },
        .{ .label = "Icon Size: Small", .action = "icon_small" },
        .{ .label = "Icon Size: Medium", .action = "icon_medium" },
        .{ .label = "Icon Size: Large", .action = "icon_large" },
        .{ .label = "Restart Shell", .action = "restart" },
        .{ .label = "Quit Shell", .action = "quit" },
    };

    const menu_x: i32 = panel_surface.width - 200;
    const menu_y: i32 = 40;
    const item_h: i32 = 28;

    for (menu_items, 0..) |item, i| {
        const iy = menu_y + @as(i32, @intCast(i)) * item_h;
        if (x >= menu_x and x < menu_x + 190 and y >= iy and y < iy + item_h) {
            executeSettingsAction(item.action);
            return;
        }
    }
}

fn executeSettingsAction(action: []const u8) void {
    if (std.mem.eql(u8, action, "quit")) {
        running = false;
    } else if (std.mem.eql(u8, action, "restart")) {
        running = false;
        // TODO: restart via exec
    } else if (std.mem.eql(u8, action, "autohide")) {
        // Toggle dock visibility
        if (dock_surface.layer_surface) |ls| {
            if (dock_surface.height > 0) {
                c.zwlr_layer_surface_v1_set_size(ls, 0, 0);
                c.zwlr_layer_surface_v1_set_exclusive_zone(ls, 0);
                dock_surface.height = 0;
            } else {
                c.zwlr_layer_surface_v1_set_size(ls, 0, DOCK_HEIGHT);
                c.zwlr_layer_surface_v1_set_exclusive_zone(ls, DOCK_HEIGHT);
                dock_surface.height = DOCK_HEIGHT;
            }
            c.wl_surface_commit(dock_surface.surface);
        }
    }
    settings_open = false;
}

const pointer_listener = c.wl_pointer_listener{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = struct { fn f(_: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: u32, _: c.wl_fixed_t) callconv(.c) void {} }.f,
    .frame = struct { fn f(_: ?*anyopaque, _: ?*c.wl_pointer) callconv(.c) void {} }.f,
    .axis_source = struct { fn f(_: ?*anyopaque, _: ?*c.wl_pointer, _: u32) callconv(.c) void {} }.f,
    .axis_stop = struct { fn f(_: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: u32) callconv(.c) void {} }.f,
    .axis_discrete = struct { fn f(_: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: i32) callconv(.c) void {} }.f,
};

fn seatCapabilities(data: ?*anyopaque, s: ?*c.wl_seat, caps: u32) callconv(.c) void {
    _ = data;
    if ((caps & c.WL_SEAT_CAPABILITY_POINTER) != 0 and pointer == null) {
        pointer = c.wl_seat_get_pointer(s);
        _ = c.wl_pointer_add_listener(pointer, &pointer_listener, null);
    }
}

const seat_listener = c.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = struct { fn f(_: ?*anyopaque, _: ?*c.wl_seat, _: [*c]const u8) callconv(.c) void {} }.f,
};

// ==== LAYER SURFACE CALLBACKS ====

fn layerSurfaceConfigure(data: ?*anyopaque, surface: ?*c.zwlr_layer_surface_v1, serial: u32, w: u32, h: u32) callconv(.c) void {
    _ = data;
    const ss = if (surface == panel_surface.layer_surface) &panel_surface else &dock_surface;
    const wi: i32 = @intCast(w);
    const hi: i32 = @intCast(h);
    if (wi != ss.width or hi != ss.height) {
        ss.width = wi;
        ss.height = hi;
        dirty = true;
    }
    c.zwlr_layer_surface_v1_ack_configure(surface, serial);
    c.zwlr_layer_surface_v1_set_size(surface, 0, @intCast(ss.height));
}

fn layerSurfaceClosed(data: ?*anyopaque, surface: ?*c.zwlr_layer_surface_v1) callconv(.c) void {
    _ = data;
    _ = surface;
    running = false;
}

const panel_layer_listener = c.zwlr_layer_surface_v1_listener{
    .configure = layerSurfaceConfigure,
    .closed = layerSurfaceClosed,
};

const dock_layer_listener = c.zwlr_layer_surface_v1_listener{
    .configure = layerSurfaceConfigure,
    .closed = layerSurfaceClosed,
};

fn frameDone(data: ?*anyopaque, cb: ?*c.wl_callback, time: u32) callconv(.c) void {
    _ = data;
    _ = time;
    // Determine which surface this callback belongs to
    if (cb == panel_surface.frame_cb) {
        c.wl_callback_destroy(cb);
        panel_surface.frame_cb = null;
    } else if (cb == dock_surface.frame_cb) {
        c.wl_callback_destroy(cb);
        dock_surface.frame_cb = null;
    }
}

const frame_listener = c.wl_callback_listener{
    .done = frameDone,
};

// ==== RENDERING ====

fn createShmFd(size: usize) ?i32 {
    var name_buf: [19]u8 = "/tmp/wl_shm-XXXXXX".* ++ .{0};
    const name_z: [*:0]u8 = @ptrCast(&name_buf);
    const fd = c.mkstemp(name_z);
    if (fd < 0) return null;
    _ = c.unlink(name_z);
    if (c.ftruncate(fd, @intCast(size)) < 0) {
        _ = c.close(fd);
        return null;
    }
    return fd;
}

fn ensureBuffer(ss: *SurfaceState) void {
    const w = ss.width * @as(i32, @intCast(ss.scale));
    const h = ss.height * @as(i32, @intCast(ss.scale));
    if (w <= 0 or h <= 0) return;

    const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, w);
    const size: usize = @intCast(@as(i64, stride) * @as(i64, h));

    if (ss.buffer != null and (ss.buf_width != w or ss.buf_height != h)) {
        c.wl_buffer_destroy(ss.buffer);
        ss.buffer = null;
        c.cairo_destroy(ss.cairo_cr);
        ss.cairo_cr = null;
        c.cairo_surface_destroy(ss.cairo_surface);
        ss.cairo_surface = null;
        _ = c.munmap(ss.shm_data, ss.buf_size);
        ss.shm_data = null;
    }

    if (ss.buffer == null) {
        const fd = createShmFd(size) orelse return;
        const data_ptr = c.mmap(null, size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
        if (data_ptr == c.MAP_FAILED) {
            _ = c.close(fd);
            return;
        }
        ss.shm_data = @ptrCast(data_ptr);
        const pool = c.wl_shm_create_pool(shm, fd, @intCast(size));
        ss.buffer = c.wl_shm_pool_create_buffer(pool, 0, w, h, stride, c.WL_SHM_FORMAT_ARGB8888);
        c.wl_shm_pool_destroy(pool);
        _ = c.close(fd);
        ss.cairo_surface = c.cairo_image_surface_create_for_data(ss.shm_data, c.CAIRO_FORMAT_ARGB32, w, h, stride);
        ss.cairo_cr = c.cairo_create(ss.cairo_surface);
        ss.buf_width = w;
        ss.buf_height = h;
        ss.buf_size = size;
    }
}

fn renderPanel() void {
    ensureBuffer(&panel_surface);
    const cr = panel_surface.cairo_cr orelse return;
    const w = panel_surface.buf_width;
    const h = panel_surface.buf_height;

    // Background gradient
    const grad = c.cairo_pattern_create_linear(0, 0, 0, h);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.0, 0.10, 0.11, 0.15, 0.97);
    c.cairo_pattern_add_color_stop_rgba(grad, 1.0, 0.04, 0.05, 0.07, 0.97);
    c.cairo_set_source(cr, grad);
    c.cairo_paint(cr);
    c.cairo_pattern_destroy(grad);

    // Accent line at bottom
    c.cairo_set_source_rgba(cr, 0.20, 0.61, 0.86, 0.9);
    c.cairo_rectangle(cr, 0, h - 2, w, 2);
    c.cairo_fill(cr);

    // Measure and layout widgets
    const pad: i32 = 12;
    _ = panel_mod.widgetListWidth(widgets[0..@intCast(widget_count)], h, pad);
    const x0: i32 = 10;

    var left_w: i32 = 0;
    var right_w: i32 = 0;
    for (0..@intCast(widget_count)) |i| {
        if (widgets[i].side == 1) right_w += widgets[i].cached_w + pad
        else left_w += widgets[i].cached_w + pad;
    }
    if (left_w > 0) left_w -= pad;
    if (right_w > 0) right_w -= pad;

    // Reserve space for settings button
    const settings_btn_w: i32 = 32;
    var x: i32 = x0;
    for (0..@intCast(widget_count)) |i| {
        if (widgets[i].side == 1) continue;
        widget_x[i] = x;
        x += widgets[i].cached_w + pad;
    }

    var rx: i32 = w - x0 - right_w - settings_btn_w;
    if (rx < x) rx = x;
    for (0..@intCast(widget_count)) |i| {
        if (widgets[i].side != 1) continue;
        widget_x[i] = rx;
        rx += widgets[i].cached_w + pad;
    }

    // Draw widgets
    for (0..@intCast(widget_count)) |i| {
        if (widgets[i].draw_fn) |fn_ptr| fn_ptr(&widgets[i], cr, widget_x[i], 0, h);
    }

    // Draw settings gear icon (always present, cannot be removed)
    drawSettingsButton(cr, w, h);

    // Draw settings menu if open
    if (settings_open) {
        drawSettingsMenu(cr, w, h);
    }

    c.cairo_surface_flush(panel_surface.cairo_surface);
}

fn drawSettingsButton(cr: *c.cairo_t, w: i32, h: i32) void {
    const btn_x = w - 32;
    const btn_y: i32 = 0;

    // Button background
    c.cairo_set_source_rgba(cr, 0.3, 0.3, 0.35, 0.8);
    c.cairo_rectangle(cr, btn_x, btn_y, 28, h);
    c.cairo_fill(cr);

    // Gear icon (Unicode cog)
    const layout = c.pango_cairo_create_layout(cr);
    defer c.g_object_unref(layout);
    const font = c.pango_font_description_from_string("Sans 14");
    defer c.pango_font_description_free(font);
    c.pango_layout_set_font_description(layout, font);
    c.pango_layout_set_text(layout, "⚙", -1);
    var tw: c_int = 0;
    var th: c_int = 0;
    c.pango_layout_get_pixel_size(layout, &tw, &th);
    c.cairo_set_source_rgb(cr, 0.85, 0.85, 0.88);
    c.cairo_move_to(cr, btn_x + @divTrunc(28 - tw, 2), @divTrunc(h - th, 2));
    c.pango_cairo_show_layout(cr, layout);
}

fn drawSettingsMenu(cr: *c.cairo_t, w: i32, _: i32) void {
    const menu_items = [_][]const u8{
        "Toggle Auto-Hide Dock",
        "Icon Size: Small",
        "Icon Size: Medium",
        "Icon Size: Large",
        "Restart Shell",
        "Quit Shell",
    };

    const menu_x: i32 = w - 200;
    const menu_y: i32 = 40;
    const item_h: i32 = 28;
    const menu_w: i32 = 190;
    const menu_h: i32 = @as(i32, @intCast(menu_items.len)) * item_h + 8;

    // Menu background
    c.cairo_set_source_rgba(cr, 0.12, 0.12, 0.15, 0.95);
    c.cairo_rectangle(cr, menu_x, menu_y, menu_w, menu_h);
    c.cairo_fill(cr);

    // Menu border
    c.cairo_set_source_rgba(cr, 0.3, 0.3, 0.35, 1.0);
    c.cairo_set_line_width(cr, 1);
    c.cairo_rectangle(cr, menu_x, menu_y, menu_w, menu_h);
    c.cairo_stroke(cr);

    // Menu items
    for (menu_items, 0..) |item, i| {
        const iy = menu_y + 4 + @as(i32, @intCast(i)) * item_h;

        // Hover highlight
        if (pointer_x >= menu_x and pointer_x < menu_x + menu_w and
            pointer_y >= iy and pointer_y < iy + item_h)
        {
            c.cairo_set_source_rgba(cr, 0.25, 0.25, 0.30, 1.0);
            c.cairo_rectangle(cr, menu_x + 2, iy, menu_w - 4, item_h);
            c.cairo_fill(cr);
        }

        // Item text
        const layout = c.pango_cairo_create_layout(cr);
        defer c.g_object_unref(layout);
        const font = c.pango_font_description_from_string("Sans 10");
        defer c.pango_font_description_free(font);
        c.pango_layout_set_font_description(layout, font);
        c.pango_layout_set_text(layout, @ptrCast(item.ptr), @intCast(item.len));
        var tw: c_int = 0;
        var th: c_int = 0;
        c.pango_layout_get_pixel_size(layout, &tw, &th);
        c.cairo_set_source_rgb(cr, 0.85, 0.85, 0.88);
        c.cairo_move_to(cr, menu_x + 10, iy + @divTrunc(item_h - th, 2));
        c.pango_cairo_show_layout(cr, layout);
    }
}

fn renderDock() void {
    if (dock_surface.height <= 0) return;
    ensureBuffer(&dock_surface);
    dock_mod.draw(
        dock_surface.cairo_cr orelse return,
        dock_surface.buf_width,
        dock_surface.buf_height,
        &toplevels,
        toplevel_count,
        dock_hover_idx,
    );
    c.cairo_surface_flush(dock_surface.cairo_surface);
}

fn submitSurface(ss: *SurfaceState) void {
    c.wl_surface_attach(ss.surface, ss.buffer, 0, 0);
    c.wl_surface_damage_buffer(ss.surface, 0, 0, ss.buf_width, ss.buf_height);
    if (ss.frame_cb) |cb| c.wl_callback_destroy(cb);
    ss.frame_cb = c.wl_surface_frame(ss.surface);
    _ = c.wl_callback_add_listener(ss.frame_cb, &frame_listener, null);
    c.wl_surface_commit(ss.surface);
}

// ==== MAIN ====

pub fn main() !void {
    display = c.wl_display_connect(null) orelse {
        std.log.err("fltk-zig-shell: failed to connect to Wayland display", .{});
        return error.WaylandConnectFailed;
    };

    registry = c.wl_display_get_registry(display);
    _ = c.wl_registry_add_listener(registry, &registry_listener, null);
    _ = c.wl_display_roundtrip(display);
    _ = c.wl_display_roundtrip(display);

    if (compositor == null or shm == null or layer_shell == null) {
        std.log.err("fltk-zig-shell: missing required Wayland globals", .{});
        return error.MissingGlobals;
    }

    if (toplevel_manager != null) {
        _ = c.wl_display_roundtrip(display);
        std.log.info("fltk-zig-shell: toplevel management enabled", .{});
    }

    if (seat) |s| {
        _ = c.wl_seat_add_listener(s, &seat_listener, null);
    }

    // Load default widgets
    const defaults = panel_mod.widgetCreateDefault();
    for (0..@intCast(defaults.count)) |i| {
        widgets[i] = defaults.widgets[i];
    }
    widget_count = defaults.count;

    pctx = .{
        .toplevels = &toplevels,
        .count = &toplevel_count,
        .seat = seat,
    };

    // Create panel surface (TOP)
    panel_surface.surface = c.wl_compositor_create_surface(compositor);
    panel_surface.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
        layer_shell, panel_surface.surface, null,
        c.ZWLR_LAYER_SHELL_V1_LAYER_TOP, "fltk-panel",
    );
    _ = c.zwlr_layer_surface_v1_add_listener(panel_surface.layer_surface, &panel_layer_listener, null);

    const panel_anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    c.zwlr_layer_surface_v1_set_anchor(panel_surface.layer_surface, panel_anchor);
    c.zwlr_layer_surface_v1_set_size(panel_surface.layer_surface, 0, PANEL_HEIGHT);
    c.zwlr_layer_surface_v1_set_exclusive_zone(panel_surface.layer_surface, PANEL_HEIGHT);
    c.zwlr_layer_surface_v1_set_keyboard_interactivity(panel_surface.layer_surface, 0);
    c.wl_surface_commit(panel_surface.surface);

    // Create dock surface (BOTTOM)
    dock_surface.surface = c.wl_compositor_create_surface(compositor);
    dock_surface.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
        layer_shell, dock_surface.surface, null,
        c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, "fltk-dock",
    );
    _ = c.zwlr_layer_surface_v1_add_listener(dock_surface.layer_surface, &dock_layer_listener, null);

    const dock_anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    c.zwlr_layer_surface_v1_set_anchor(dock_surface.layer_surface, dock_anchor);
    c.zwlr_layer_surface_v1_set_size(dock_surface.layer_surface, 0, DOCK_HEIGHT);
    c.zwlr_layer_surface_v1_set_exclusive_zone(dock_surface.layer_surface, DOCK_HEIGHT);
    c.zwlr_layer_surface_v1_set_keyboard_interactivity(dock_surface.layer_surface, 0);
    c.wl_surface_commit(dock_surface.surface);

    // Wait for initial configure
    var ret: i32 = 0;
    while (panel_surface.width == 0 and ret >= 0 and c.wl_display_get_error(display) == 0) {
        ret = c.wl_display_dispatch(display);
    }

    if (c.wl_display_get_error(display) != 0) {
        std.log.err("fltk-zig-shell: Wayland protocol error during init", .{});
        running = false;
    }

    if (panel_surface.width == 0) panel_surface.width = 1920;
    if (panel_surface.height == 0) panel_surface.height = PANEL_HEIGHT;
    if (dock_surface.width == 0) dock_surface.width = panel_surface.width;
    if (dock_surface.height == 0) dock_surface.height = DOCK_HEIGHT;

    std.log.info("fltk-zig-shell: panel ({d}x{d}) dock ({d}x{d})", .{
        panel_surface.width, panel_surface.height,
        dock_surface.width, dock_surface.height,
    });

    // Timer for clock updates
    timer_fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_NONBLOCK);
    if (timer_fd >= 0) {
        var ts = std.mem.zeroes(c.struct_itimerspec);
        ts.it_interval.tv_sec = 1;
        ts.it_value.tv_sec = 1;
        _ = c.timerfd_settime(timer_fd, 0, &ts, null);
    }

    dirty = true;

    const wl_fd = c.wl_display_get_fd(display);
    var pfds: [2]c.struct_pollfd = undefined;

    // Main event loop
    while (running) {
        if (dirty) {
            renderPanel();
            submitSurface(&panel_surface);

            renderDock();
            submitSurface(&dock_surface);

            dirty = false;
        }

        _ = c.wl_display_flush(display);

        pfds[0].fd = wl_fd;
        pfds[0].events = c.POLLIN;
        pfds[1].fd = timer_fd;
        pfds[1].events = c.POLLIN;

        const poll_ret = c.poll(&pfds, 2, 3000);
        if (poll_ret > 0) {
            if ((pfds[0].revents & c.POLLIN) != 0) {
                _ = c.wl_display_dispatch(display);
            }
            if ((pfds[1].revents & c.POLLIN) != 0) {
                var exp: u64 = 0;
                _ = c.read(timer_fd, &exp, @sizeOf(u64));
                panel_mod.widgetListUpdate(widgets[0..@intCast(widget_count)]);
                dirty = true;
            }
        } else {
            _ = c.wl_display_dispatch_pending(display);
        }
    }

    // Cleanup
    if (panel_surface.buffer) |b| c.wl_buffer_destroy(b);
    if (panel_surface.cairo_cr) |cr| c.cairo_destroy(cr);
    if (panel_surface.cairo_surface) |s| c.cairo_surface_destroy(s);
    if (panel_surface.shm_data) |d| _ = c.munmap(d, panel_surface.buf_size);
    if (panel_surface.frame_cb) |cb| c.wl_callback_destroy(cb);
    if (panel_surface.layer_surface) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (panel_surface.surface) |s| c.wl_surface_destroy(s);

    if (dock_surface.buffer) |b| c.wl_buffer_destroy(b);
    if (dock_surface.cairo_cr) |cr| c.cairo_destroy(cr);
    if (dock_surface.cairo_surface) |s| c.cairo_surface_destroy(s);
    if (dock_surface.shm_data) |d| _ = c.munmap(d, dock_surface.buf_size);
    if (dock_surface.frame_cb) |cb| c.wl_callback_destroy(cb);
    if (dock_surface.layer_surface) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (dock_surface.surface) |s| c.wl_surface_destroy(s);

    icon.clearCache();
    if (display) |d| _ = c.wl_display_disconnect(d);

    std.log.info("fltk-zig-shell: exiting", .{});
}
