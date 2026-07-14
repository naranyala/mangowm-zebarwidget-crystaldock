const std = @import("std");
const c = @import("c.zig").c;
const toplevel = @import("toplevel.zig");
const panel_mod = @import("panel.zig");

const PANEL_HEIGHT = 36;
const MAX_TOPLEVELS = 64;

// ---- wayland globals ----
var display: ?*c.wl_display = null;
var compositor: ?*c.wl_compositor = null;
var shm: ?*c.wl_shm = null;
var layer_shell: ?*c.zwlr_layer_shell_v1 = null;
var toplevel_manager: ?*c.zwlr_foreign_toplevel_manager_v1 = null;
var registry: ?*c.wl_registry = null;
var seat: ?*c.wl_seat = null;
var pointer: ?*c.wl_pointer = null;

// ---- panel state ----
const PanelState = struct {
    surface: ?*c.wl_surface = null,
    layer_surface: ?*c.zwlr_layer_surface_v1 = null,
    width: i32 = 0,
    height: i32 = PANEL_HEIGHT,
    scale: u32 = 1,
    frame_cb: ?*c.wl_callback = null,
    dirty: bool = false,
    running: bool = true,
    cairo_surface: ?*c.cairo_surface_t = null,
    cairo_cr: ?*c.cairo_t = null,
    shm_data: ?[*]u8 = null,
    buffer: ?*c.wl_buffer = null,
    buf_width: i32 = 0,
    buf_height: i32 = 0,
    buf_size: usize = 0,
    timer_fd: i32 = -1,
};

var panel_state = PanelState{};
var toplevels: [MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
var toplevel_count: i32 = 0;
var widgets: [64]panel_mod.Widget = undefined;
var widget_count: i32 = 0;
var widget_x: [64]i32 = undefined;
var pctx: panel_mod.PanelCtx = undefined;
var pointer_x: i32 = 0;
var pointer_y: i32 = 0;

// ---- toplevel callbacks ----
fn toplevelHandleTitle(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, title: [*c]const u8) callconv(.c) void {
    _ = handle;
    const info: *toplevel.ToplevelInfo = @ptrCast(@alignCast(data orelse return));
    const title_str = std.mem.sliceTo(title, 0);
    const len = @min(title_str.len, info.title.len - 1);
    @memcpy(info.title[0..len], title_str[0..len]);
    info.title[len] = 0;
    panel_state.dirty = true;
}

fn toplevelHandleAppId(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, app_id: [*c]const u8) callconv(.c) void {
    _ = handle;
    const info: *toplevel.ToplevelInfo = @ptrCast(@alignCast(data orelse return));
    const id_str = std.mem.sliceTo(app_id, 0);
    const len = @min(id_str.len, info.app_id.len - 1);
    @memcpy(info.app_id[0..len], id_str[0..len]);
    info.app_id[len] = 0;
    panel_state.dirty = true;
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
    panel_state.dirty = true;
}

fn toplevelHandleDone(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    _ = handle;
    panel_state.dirty = true;
}

fn toplevelHandleClosed(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    const idx = toplevel.findIndex(&toplevels, toplevel_count, @ptrCast(handle orelse return));
    if (idx >= 0) {
        toplevel.removeAt(&toplevels, &toplevel_count, idx);
        panel_state.dirty = true;
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
    panel_state.dirty = true;
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
    _ = surface;
    pointer_x = c.wl_fixed_to_int(x);
    pointer_y = c.wl_fixed_to_int(y);
}

fn pointerLeave(data: ?*anyopaque, p: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = p;
    _ = serial;
    _ = surface;
}

fn pointerMotion(data: ?*anyopaque, p: ?*c.wl_pointer, time: u32, x: c.wl_fixed_t, y: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = p;
    _ = time;
    pointer_x = c.wl_fixed_to_int(x);
    pointer_y = c.wl_fixed_to_int(y);
}

fn pointerButton(data: ?*anyopaque, p: ?*c.wl_pointer, serial: u32, time: u32, button: u32, state_w: u32) callconv(.c) void {
    _ = data;
    _ = p;
    _ = serial;
    _ = time;
    if (state_w != c.WL_POINTER_BUTTON_STATE_PRESSED) return;
    for (0..@intCast(widget_count)) |i| {
        if (pointer_x >= widget_x[i] and pointer_x < widget_x[i] + widgets[i].cached_w) {
            if (widgets[i].click_fn) |fn_ptr| {
                _ = fn_ptr(&widgets[i], button, pointer_x - widget_x[i], pointer_y);
            }
            panel_state.dirty = true;
            return;
        }
    }
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

// ---- rendering ----
fn renderPanel(d: *PanelState) void {
    const w = d.width * @as(i32, @intCast(d.scale));
    const h = d.height * @as(i32, @intCast(d.scale));
    if (w <= 0 or h <= 0) return;

    const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, w);
    const size: usize = @intCast(@as(i64, stride) * @as(i64, h));

    if (d.buffer != null and (d.buf_width != w or d.buf_height != h)) {
        c.wl_buffer_destroy(d.buffer);
        d.buffer = null;
        c.cairo_destroy(d.cairo_cr);
        d.cairo_cr = null;
        c.cairo_surface_destroy(d.cairo_surface);
        d.cairo_surface = null;
        _ = c.munmap(d.shm_data, d.buf_size);
        d.shm_data = null;
    }

    if (d.buffer == null) {
        const fd = createShmFd(size) orelse return;
        const data_ptr = c.mmap(null, size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
        if (data_ptr == c.MAP_FAILED) {
            _ = c.close(fd);
            return;
        }
        d.shm_data = @ptrCast(data_ptr);
        const pool = c.wl_shm_create_pool(shm, fd, @intCast(size));
        d.buffer = c.wl_shm_pool_create_buffer(pool, 0, w, h, stride, c.WL_SHM_FORMAT_ARGB8888);
        c.wl_shm_pool_destroy(pool);
        _ = c.close(fd);
        d.cairo_surface = c.cairo_image_surface_create_for_data(d.shm_data, c.CAIRO_FORMAT_ARGB32, w, h, stride);
        d.cairo_cr = c.cairo_create(d.cairo_surface);
        d.buf_width = w;
        d.buf_height = h;
        d.buf_size = size;
    }

    const cr = d.cairo_cr orelse return;

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

    // Left block
    var x: i32 = x0;
    for (0..@intCast(widget_count)) |i| {
        if (widgets[i].side == 1) continue;
        widget_x[i] = x;
        x += widgets[i].cached_w + pad;
    }

    // Right block
    var rx: i32 = w - x0 - right_w;
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

    c.cairo_surface_flush(d.cairo_surface);
}

// ---- layer-surface callbacks ----
fn layerSurfaceConfigure(data: ?*anyopaque, surface: ?*c.zwlr_layer_surface_v1, serial: u32, w: u32, h: u32) callconv(.c) void {
    _ = data;
    const wi: i32 = @intCast(w);
    const hi: i32 = @intCast(h);
    if (wi != panel_state.width or hi != panel_state.height) {
        panel_state.width = wi;
        panel_state.height = hi;
        panel_state.dirty = true;
    }
    c.zwlr_layer_surface_v1_ack_configure(surface, serial);
    c.zwlr_layer_surface_v1_set_size(surface, 0, @intCast(panel_state.height));
}

fn layerSurfaceClosed(data: ?*anyopaque, surface: ?*c.zwlr_layer_surface_v1) callconv(.c) void {
    _ = data;
    _ = surface;
    panel_state.running = false;
}

const layer_surface_listener = c.zwlr_layer_surface_v1_listener{
    .configure = layerSurfaceConfigure,
    .closed = layerSurfaceClosed,
};

fn frameDone(data: ?*anyopaque, cb: ?*c.wl_callback, time: u32) callconv(.c) void {
    _ = data;
    _ = time;
    c.wl_callback_destroy(cb);
    panel_state.frame_cb = null;
}

const frame_listener = c.wl_callback_listener{
    .done = frameDone,
};

// ---- shared memory helper ----
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

// ---- main ----
pub fn main() !void {
    display = c.wl_display_connect(null) orelse {
        std.log.err("fltk-panel: failed to connect to Wayland display", .{});
        return error.WaylandConnectFailed;
    };

    registry = c.wl_display_get_registry(display);
    _ = c.wl_registry_add_listener(registry, &registry_listener, null);
    _ = c.wl_display_roundtrip(display);
    _ = c.wl_display_roundtrip(display);

    if (compositor == null or shm == null or layer_shell == null) {
        std.log.err("fltk-panel: missing required Wayland globals", .{});
        return error.MissingGlobals;
    }

    if (toplevel_manager != null) {
        _ = c.wl_display_roundtrip(display);
        std.log.info("fltk-panel: toplevel management enabled", .{});
    } else {
        std.log.warn("fltk-panel: no toplevel manager available", .{});
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

    // Create layer surface (TOP)
    panel_state.surface = c.wl_compositor_create_surface(compositor);
    panel_state.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
        layer_shell,
        panel_state.surface,
        null,
        c.ZWLR_LAYER_SHELL_V1_LAYER_TOP,
        "fltk-panel",
    );

    _ = c.zwlr_layer_surface_v1_add_listener(panel_state.layer_surface, &layer_surface_listener, null);

    const anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    c.zwlr_layer_surface_v1_set_anchor(panel_state.layer_surface, anchor);
    c.zwlr_layer_surface_v1_set_size(panel_state.layer_surface, 0, PANEL_HEIGHT);
    c.zwlr_layer_surface_v1_set_exclusive_zone(panel_state.layer_surface, PANEL_HEIGHT);
    c.zwlr_layer_surface_v1_set_keyboard_interactivity(panel_state.layer_surface, 0);
    c.wl_surface_commit(panel_state.surface);

    // Wait for initial configure
    var ret: i32 = 0;
    while (panel_state.width == 0 and ret >= 0 and c.wl_display_get_error(display) == 0) {
        ret = c.wl_display_dispatch(display);
    }

    if (c.wl_display_get_error(display) != 0) {
        std.log.err("fltk-panel: Wayland protocol error during init", .{});
        panel_state.running = false;
    }

    if (panel_state.width == 0) panel_state.width = 1920;
    if (panel_state.height == 0) panel_state.height = PANEL_HEIGHT;

    std.log.info("fltk-panel: layer-surface created ({d}x{d})", .{ panel_state.width, panel_state.height });

    // Timer for clock updates
    panel_state.timer_fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_NONBLOCK);
    if (panel_state.timer_fd >= 0) {
        var ts = std.mem.zeroes(c.struct_itimerspec);
        ts.it_interval.tv_sec = 1;
        ts.it_value.tv_sec = 1;
        _ = c.timerfd_settime(panel_state.timer_fd, 0, &ts, null);
    }

    panel_state.dirty = true;

    const wl_fd = c.wl_display_get_fd(display);
    var pfds: [2]c.struct_pollfd = undefined;

    while (panel_state.running) {
        if (panel_state.dirty) {
            renderPanel(&panel_state);

            c.wl_surface_attach(panel_state.surface, panel_state.buffer, 0, 0);
            c.wl_surface_damage_buffer(panel_state.surface, 0, 0, panel_state.buf_width, panel_state.buf_height);

            if (panel_state.frame_cb) |cb| c.wl_callback_destroy(cb);
            panel_state.frame_cb = c.wl_surface_frame(panel_state.surface);
            _ = c.wl_callback_add_listener(panel_state.frame_cb, &frame_listener, null);

            c.wl_surface_commit(panel_state.surface);
            panel_state.dirty = false;
        }

        _ = c.wl_display_flush(display);

        pfds[0].fd = wl_fd;
        pfds[0].events = c.POLLIN;
        pfds[1].fd = panel_state.timer_fd;
        pfds[1].events = c.POLLIN;

        const poll_ret = c.poll(&pfds, 2, 3000);
        if (poll_ret > 0) {
            if ((pfds[0].revents & c.POLLIN) != 0) {
                _ = c.wl_display_dispatch(display);
            }
            if ((pfds[1].revents & c.POLLIN) != 0) {
                var exp: u64 = 0;
                _ = c.read(panel_state.timer_fd, &exp, @sizeOf(u64));
                panel_mod.widgetListUpdate(widgets[0..@intCast(widget_count)]);
                panel_state.dirty = true;
            }
        } else {
            _ = c.wl_display_dispatch_pending(display);
        }
    }

    // Cleanup
    if (panel_state.buffer) |b| c.wl_buffer_destroy(b);
    if (panel_state.cairo_cr) |cr| c.cairo_destroy(cr);
    if (panel_state.cairo_surface) |s| c.cairo_surface_destroy(s);
    if (panel_state.shm_data) |d| _ = c.munmap(d, panel_state.buf_size);
    if (panel_state.frame_cb) |cb| c.wl_callback_destroy(cb);
    if (panel_state.layer_surface) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (panel_state.surface) |s| c.wl_surface_destroy(s);
    if (display) |d| _ = c.wl_display_disconnect(d);

    std.log.info("fltk-panel: exiting", .{});
}
