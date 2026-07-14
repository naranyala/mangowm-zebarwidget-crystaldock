const std = @import("std");
const c = @import("c.zig").c;

const toplevel = @import("toplevel.zig");
const dock = @import("dock.zig");
const icon = @import("icon.zig");

const DOCK_HEIGHT: i32 = 48;
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

// ---- dock state ----
const DockState = struct {
    surface: ?*c.wl_surface = null,
    layer_surface: ?*c.zwlr_layer_surface_v1 = null,
    width: i32 = 0,
    height: i32 = DOCK_HEIGHT,
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
    hover_idx: i32 = -1,
};

var dock_state = DockState{};

// ---- toplevel tracking ----
var toplevels: [MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
var toplevel_count: i32 = 0;

// ---- toplevel callbacks ----
fn toplevelHandleTitle(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, title: [*c]const u8) callconv(.c) void {
    _ = handle;
    const info: *toplevel.ToplevelInfo = @ptrCast(@alignCast(data orelse return));
    const title_str = std.mem.sliceTo(title, 0);
    const len = @min(title_str.len, info.title.len - 1);
    @memcpy(info.title[0..len], title_str[0..len]);
    info.title[len] = 0;
    dock_state.dirty = true;
}

fn toplevelHandleAppId(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, app_id: [*c]const u8) callconv(.c) void {
    _ = handle;
    const info: *toplevel.ToplevelInfo = @ptrCast(@alignCast(data orelse return));
    const id_str = std.mem.sliceTo(app_id, 0);
    const len = @min(id_str.len, info.app_id.len - 1);
    @memcpy(info.app_id[0..len], id_str[0..len]);
    info.app_id[len] = 0;
    dock_state.dirty = true;
}

fn toplevelHandleOutputEnter(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, output: ?*c.wl_output) callconv(.c) void {
    _ = data;
    _ = handle;
    _ = output;
}

fn toplevelHandleOutputLeave(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, output: ?*c.wl_output) callconv(.c) void {
    _ = data;
    _ = handle;
    _ = output;
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
            if (states[i] == c.ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MAXIMIZED) info.maximized = true;
        }
    }
    dock_state.dirty = true;
}

fn toplevelHandleDone(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    _ = handle;
    dock_state.dirty = true;
    if (dock_state.surface != null and dock_state.layer_surface != null) {
        c.zwlr_layer_surface_v1_set_size(dock_state.layer_surface, 0, @intCast(dock_state.height));
        c.wl_surface_commit(dock_state.surface);
    }
}

fn toplevelHandleClosed(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    const idx = toplevel.findIndex(&toplevels, toplevel_count, @ptrCast(handle orelse return));
    if (idx >= 0) {
        toplevel.removeAt(&toplevels, &toplevel_count, idx);
        dock_state.dirty = true;
        if (dock_state.surface != null and dock_state.layer_surface != null) {
            c.zwlr_layer_surface_v1_set_size(dock_state.layer_surface, 0, @intCast(dock_state.height));
            c.wl_surface_commit(dock_state.surface);
        }
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
    .output_enter = toplevelHandleOutputEnter,
    .output_leave = toplevelHandleOutputLeave,
    .state = toplevelHandleState,
    .done = toplevelHandleDone,
    .closed = toplevelHandleClosed,
    .parent = toplevelHandleParent,
};

fn toplevelManagerToplevel(data: ?*anyopaque, manager: ?*c.zwlr_foreign_toplevel_manager_v1, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    _ = manager;
    const idx = toplevel.add(&toplevels, &toplevel_count, @ptrCast(handle orelse return));
    const info = &toplevels[idx];
    _ = c.zwlr_foreign_toplevel_handle_v1_add_listener(handle, &toplevel_handle_listener, info);
    dock_state.dirty = true;
    if (dock_state.surface != null and dock_state.layer_surface != null) {
        c.zwlr_layer_surface_v1_set_size(dock_state.layer_surface, 0, @intCast(dock_state.height));
        c.wl_surface_commit(dock_state.surface);
    }
}

fn toplevelManagerFinished(data: ?*anyopaque, manager: ?*c.zwlr_foreign_toplevel_manager_v1) callconv(.c) void {
    _ = data;
    _ = manager;
}

const toplevel_manager_listener = c.zwlr_foreign_toplevel_manager_v1_listener{
    .toplevel = toplevelManagerToplevel,
    .finished = toplevelManagerFinished,
};

// ---- pointer input ----
fn pointerEnter(data: ?*anyopaque, wl_pointer: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface, surface_x: c.wl_fixed_t, surface_y: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = wl_pointer;
    _ = serial;
    _ = surface;
    _ = surface_y;
    dock_state.hover_idx = dock.iconAt(dock_state.width, dock_state.height, &toplevels, toplevel_count, c.wl_fixed_to_int(surface_x));
    dock_state.dirty = true;
}

fn pointerLeave(data: ?*anyopaque, wl_pointer: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = wl_pointer;
    _ = serial;
    _ = surface;
    dock_state.hover_idx = -1;
    dock_state.dirty = true;
}

fn pointerMotion(data: ?*anyopaque, wl_pointer: ?*c.wl_pointer, time: u32, surface_x: c.wl_fixed_t, surface_y: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = wl_pointer;
    _ = time;
    _ = surface_y;
    const idx = dock.iconAt(dock_state.width, dock_state.height, &toplevels, toplevel_count, c.wl_fixed_to_int(surface_x));
    if (idx != dock_state.hover_idx) {
        dock_state.hover_idx = idx;
        dock_state.dirty = true;
    }
}

fn pointerButton(data: ?*anyopaque, wl_pointer: ?*c.wl_pointer, serial: u32, time: u32, button: u32, state_w: u32) callconv(.c) void {
    _ = data;
    _ = wl_pointer;
    _ = serial;
    _ = time;
    _ = button;
    if (state_w != c.WL_POINTER_BUTTON_STATE_PRESSED) return;
    if (dock_state.hover_idx < 0 or dock_state.hover_idx >= toplevel_count) return;
    if (seat == null) return;

    const info = &toplevels[@intCast(dock_state.hover_idx)];
    const handle: ?*c.zwlr_foreign_toplevel_handle_v1 = @ptrCast(@alignCast(info.handle));

    if (info.focused) {
        c.zwlr_foreign_toplevel_handle_v1_set_minimized(handle);
    } else {
        c.zwlr_foreign_toplevel_handle_v1_activate(handle, seat);
    }
}

fn pointerAxis(data: ?*anyopaque, wl_pointer: ?*c.wl_pointer, time: u32, axis: u32, value: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = wl_pointer;
    _ = time;
    _ = axis;
    _ = value;
}

fn pointerFrame(data: ?*anyopaque, wl_pointer: ?*c.wl_pointer) callconv(.c) void {
    _ = data;
    _ = wl_pointer;
}

fn pointerAxisSource(data: ?*anyopaque, wl_pointer: ?*c.wl_pointer, axis_source: u32) callconv(.c) void {
    _ = data;
    _ = wl_pointer;
    _ = axis_source;
}

fn pointerAxisStop(data: ?*anyopaque, wl_pointer: ?*c.wl_pointer, time: u32, axis: u32) callconv(.c) void {
    _ = data;
    _ = wl_pointer;
    _ = time;
    _ = axis;
}

fn pointerAxisDiscrete(data: ?*anyopaque, wl_pointer: ?*c.wl_pointer, axis: u32, discrete: i32) callconv(.c) void {
    _ = data;
    _ = wl_pointer;
    _ = axis;
    _ = discrete;
}

const pointer_listener = c.wl_pointer_listener{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
    .frame = pointerFrame,
    .axis_source = pointerAxisSource,
    .axis_stop = pointerAxisStop,
    .axis_discrete = pointerAxisDiscrete,
};

fn seatCapabilities(data: ?*anyopaque, wl_seat: ?*c.wl_seat, capabilities: u32) callconv(.c) void {
    _ = data;
    if ((capabilities & c.WL_SEAT_CAPABILITY_POINTER) != 0 and pointer == null) {
        pointer = c.wl_seat_get_pointer(wl_seat);
        c.wl_pointer_add_listener(pointer, &pointer_listener, null);
    } else if ((capabilities & c.WL_SEAT_CAPABILITY_POINTER) == 0 and pointer != null) {
        c.wl_pointer_destroy(pointer);
        pointer = null;
    }
}

fn seatName(data: ?*anyopaque, wl_seat: ?*c.wl_seat, name: [*:0]const u8) callconv(.c) void {
    _ = data;
    _ = wl_seat;
    _ = name;
}

const seat_listener = c.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

// ---- registry ----
fn registryGlobal(data: ?*anyopaque, reg: ?*c.wl_registry, name: u32, iface: [*c]const u8, version: u32) callconv(.c) void {
    _ = data;
    const iface_str = std.mem.sliceTo(iface, 0);

    if (std.mem.eql(u8, iface_str, "wl_compositor")) {
        compositor = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_compositor_interface, 4));
    } else if (std.mem.eql(u8, iface_str, "wl_shm")) {
        shm = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_shm_interface, 1));
    } else if (std.mem.eql(u8, iface_str, "zwlr_layer_shell_v1")) {
        layer_shell = @ptrCast(c.wl_registry_bind(reg, name, &c.zwlr_layer_shell_v1_interface, 1));
    } else if (std.mem.eql(u8, iface_str, "zwlr_foreign_toplevel_manager_v1")) {
        toplevel_manager = @ptrCast(c.wl_registry_bind(reg, name, &c.zwlr_foreign_toplevel_manager_v1_interface, 3));
        _ = c.zwlr_foreign_toplevel_manager_v1_add_listener(toplevel_manager, &toplevel_manager_listener, null);
    } else if (std.mem.eql(u8, iface_str, "wl_seat")) {
        seat = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_seat_interface, 7));
    }
    _ = version;
}

fn registryGlobalRemove(data: ?*anyopaque, reg: ?*c.wl_registry, name: u32) callconv(.c) void {
    _ = data;
    _ = reg;
    _ = name;
}

const registry_listener = c.wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

// ---- rendering ----
fn renderDock(d: *DockState) void {
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

    dock.draw(d.cairo_cr.?, w, h, &toplevels, toplevel_count, d.hover_idx);
    c.cairo_surface_flush(d.cairo_surface);
}

// ---- layer-surface callbacks ----
fn layerSurfaceConfigure(data: ?*anyopaque, surface: ?*c.zwlr_layer_surface_v1, serial: u32, w: u32, h: u32) callconv(.c) void {
    _ = data;
    const wi: i32 = @intCast(w);
    const hi: i32 = @intCast(h);
    if (wi != dock_state.width or hi != dock_state.height) {
        dock_state.width = wi;
        dock_state.height = hi;
        dock_state.dirty = true;
    }
    c.zwlr_layer_surface_v1_ack_configure(surface, serial);
    c.zwlr_layer_surface_v1_set_size(surface, 0, @intCast(dock_state.height));
}

fn layerSurfaceClosed(data: ?*anyopaque, surface: ?*c.zwlr_layer_surface_v1) callconv(.c) void {
    _ = data;
    _ = surface;
    dock_state.running = false;
}

const layer_surface_listener = c.zwlr_layer_surface_v1_listener{
    .configure = layerSurfaceConfigure,
    .closed = layerSurfaceClosed,
};

// ---- frame callback ----
fn frameDone(data: ?*anyopaque, cb: ?*c.wl_callback, time: u32) callconv(.c) void {
    _ = data;
    _ = time;
    c.wl_callback_destroy(cb);
    dock_state.frame_cb = null;
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
    // Connect to Wayland
    display = c.wl_display_connect(null) orelse {
        std.log.err("fltk-dock: failed to connect to Wayland display", .{});
        return error.WaylandConnectFailed;
    };

    registry = c.wl_display_get_registry(display);
    _ = c.wl_registry_add_listener(registry, &registry_listener, null);
    _ = c.wl_display_roundtrip(display);
    _ = c.wl_display_roundtrip(display);

    if (compositor == null or shm == null or layer_shell == null or seat == null) {
        std.log.err("fltk-dock: missing required Wayland globals", .{});
        return error.MissingGlobals;
    }

    if (toplevel_manager != null) {
        _ = c.wl_display_roundtrip(display);
        std.log.info("fltk-dock: toplevel management enabled", .{});
    } else {
        std.log.warn("fltk-dock: no toplevel manager available", .{});
    }

    dock_state.surface = c.wl_compositor_create_surface(compositor);
    dock_state.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
        layer_shell,
        dock_state.surface,
        null,
        c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM,
        "fltk-dock",
    );

    _ = c.zwlr_layer_surface_v1_add_listener(dock_state.layer_surface, &layer_surface_listener, null);

    const anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    c.zwlr_layer_surface_v1_set_anchor(dock_state.layer_surface, anchor);
    c.zwlr_layer_surface_v1_set_size(dock_state.layer_surface, 0, DOCK_HEIGHT);
    c.zwlr_layer_surface_v1_set_exclusive_zone(dock_state.layer_surface, DOCK_HEIGHT);
    c.zwlr_layer_surface_v1_set_keyboard_interactivity(dock_state.layer_surface, 0);
    c.wl_surface_commit(dock_state.surface);

    // Wait for initial configure
    var ret: i32 = 0;
    while (dock_state.width == 0 and ret >= 0 and c.wl_display_get_error(display) == 0) {
        ret = c.wl_display_dispatch(display);
    }

    if (c.wl_display_get_error(display) != 0) {
        std.log.err("fltk-dock: Wayland protocol error during init", .{});
        dock_state.running = false;
    }

    if (dock_state.width == 0) dock_state.width = 1920;
    if (dock_state.height == 0) dock_state.height = DOCK_HEIGHT;

    std.log.info("fltk-dock: layer-surface created ({d}x{d})", .{ dock_state.width, dock_state.height });

    // Timer for clock updates
    dock_state.timer_fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_NONBLOCK);
    if (dock_state.timer_fd >= 0) {
        var ts = std.mem.zeroes(c.struct_itimerspec);
        ts.it_interval.tv_sec = 1;
        ts.it_value.tv_sec = 1;
        _ = c.timerfd_settime(dock_state.timer_fd, 0, &ts, null);
    }

    dock_state.dirty = true;

    const wl_fd = c.wl_display_get_fd(display);
    var pfds: [2]c.struct_pollfd = undefined;

    // Main event loop
    while (dock_state.running) {
        if (dock_state.dirty) {
            renderDock(&dock_state);

            c.wl_surface_attach(dock_state.surface, dock_state.buffer, 0, 0);
            c.wl_surface_damage_buffer(dock_state.surface, 0, 0, dock_state.buf_width, dock_state.buf_height);

            if (dock_state.frame_cb != null) c.wl_callback_destroy(dock_state.frame_cb);
            dock_state.frame_cb = c.wl_surface_frame(dock_state.surface);
            _ = c.wl_callback_add_listener(dock_state.frame_cb, &frame_listener, null);

            c.wl_surface_commit(dock_state.surface);
            dock_state.dirty = false;
        }

        _ = c.wl_display_flush(display);

        pfds[0].fd = wl_fd;
        pfds[0].events = c.POLLIN;
        pfds[1].fd = dock_state.timer_fd;
        pfds[1].events = c.POLLIN;

        const poll_ret = c.poll(&pfds, 2, 3000);
        if (poll_ret > 0) {
            if ((pfds[0].revents & c.POLLIN) != 0) {
                _ = c.wl_display_dispatch(display);
            }
            if ((pfds[1].revents & c.POLLIN) != 0) {
                var exp: u64 = 0;
                _ = c.read(dock_state.timer_fd, &exp, @sizeOf(u64));
                dock_state.dirty = true;
            }
        } else {
            _ = c.wl_display_dispatch_pending(display);
        }
    }

    // Cleanup
    icon.clearCache();

    if (dock_state.buffer) |b| c.wl_buffer_destroy(b);
    if (dock_state.cairo_cr) |cr| c.cairo_destroy(cr);
    if (dock_state.cairo_surface) |s| c.cairo_surface_destroy(s);
    if (dock_state.shm_data) |d| _ = c.munmap(d, dock_state.buf_size);
    if (dock_state.frame_cb) |cb| c.wl_callback_destroy(cb);
    if (dock_state.layer_surface) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (dock_state.surface) |s| c.wl_surface_destroy(s);
    if (display) |d| _ = c.wl_display_disconnect(d);

    std.log.info("fltk-dock: exiting", .{});
}
