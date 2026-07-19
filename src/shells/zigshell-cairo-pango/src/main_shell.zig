const std = @import("std");
const c = @import("c.zig").c;
const theme = @import("theme.zig");
const toplevel = @import("shellcore").toplevel;
const panel_mod = @import("panel.zig");
const session_ui = @import("session_ui.zig");
const app_launcher = @import("app_launcher.zig");
const dock_launcher = @import("dock_launcher.zig");
const config_manager = @import("config_manager.zig");
const settings_ui = @import("settings_ui.zig");
const dock_mod = @import("dock.zig");
const icon = @import("icon.zig");
const pcfg = @import("panel_config.zig");
const modal_mod = @import("modal.zig");
const damage = @import("shellcore").damage;
const shlog = @import("log");

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = shlog.logFn,
};

// Runtime panel height (P6): was a comptime const; now configurable via the
// `height =` key in panel.conf and applied on load/reload.
pub var panel_height: i32 = 24;
const PANEL_SETTINGS_HEIGHT = 560;
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
var keyboard: ?*c.wl_keyboard = null;

// ---- keyboard state ----
// We don't link xkbcommon, so we only map the keymap (required by the
// wl_keyboard protocol) without parsing it.
var keyboard_keymap_fd: c_int = -1;
var keyboard_keymap_size: usize = 0;
var keyboard_keymap_mapped: ?[*]align(1) u8 = null;

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
    dirty_region: damage.Region = damage.Region.init(),
    // Per-surface repaint flag. Each surface owns its own dirty bit so that,
    // e.g., hovering the dock never forces the panel surface to repaint.
    dirty: bool = true,
};

pub var panel_surface = SurfaceState{ .height = 24 };
var dock_surface = SurfaceState{ .height = DOCK_HEIGHT };
var launcher_surface = SurfaceState{ .height = 0 };
var modal_surface = SurfaceState{ .height = 0 };

// Mark all surfaces for repaint. Panel-affecting changes use this; the
// high-frequency dock-hover path uses `dock_surface.dirty = true` alone so the
// panel is not needlessly repainted (which caused the panel to blink while
// hovering the dock).
pub fn markDirty() void {
    panel_surface.dirty = true;
    dock_surface.dirty = true;
    launcher_surface.dirty = true;
    modal_surface.dirty = true;
}
var running = true;
var timer_fd: i32 = -1;
var reload_config: bool = false;
pub var config_path: ?[]const u8 = null;

// Global panel font-scale factor (1.0 = no scaling). Mirrors pcfg.global.font_scale
// and is pushed into the C text renderer so the whole bar rescales. Kept separate
// from panel_height so layout math stays in raw pixels.
pub var font_scale: f64 = 1.0;
pub var autohide_dock: bool = false;
pub var autohide_panel: bool = false;

// ---- shared toplevel tracking ----
var toplevels: [MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
var toplevel_count: i32 = 0;

// ---- panel widgets ----
pub var widgets: [MAX_WIDGETS]panel_mod.Widget = undefined;
pub var widget_count: i32 = 0;
pub var widget_x: [MAX_WIDGETS]i32 = undefined;
// ---- dock state ----
var dock_hover_idx: i32 = -1;
var drag_dock_group: i32 = -1;

// ---- pointer state ----
pub var pointer_x: i32 = 0;
pub var pointer_y: i32 = 0;
pub var pointer_on_panel = false;
var pointer_on_dock = false;
var pointer_on_launcher = false;
var pointer_on_modal = false;
var keyboard_focus_surface: ?*c.wl_surface = null;
var hovered_widget: i32 = -1; // index of widget under pointer, -1 if none

// ---- settings state ----
pub var settings_open = false;
// Settings panel tab: 0 = Widgets, 1 = Dock
pub var settings_tab: u32 = 0;
// Settings list scroll offset (per-tab row index)
pub var settings_scroll: i32 = 0;
// Drag-move state for the widgets list (index being moved, -1 if none)
pub var settings_drag_idx: i32 = -1;
// Selected widget index for the add menu (-1 none)
pub var settings_add_menu: bool = false;
// Tracks whether a save is pending after an edit
pub var config_dirty: bool = false;

// ---- app launcher state ----
var launcher_open = false;
var launcher_hover_idx: i32 = -1;
var launcher_scroll: i32 = 0;

// ---- global modal state ----
var modal_open = false;
var modal_state: modal_mod.ModalState = .{};
var modal_title: [128]u8 = std.mem.zeroes([128]u8);
var modal_title_len: usize = 0;

// ==== WAYLAND CALLBACKS ====

fn toplevelHandleTitle(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, title: [*c]const u8) callconv(.c) void {
    _ = handle;
    const info: *toplevel.ToplevelInfo = @ptrCast(@alignCast(data orelse return));
    const title_str = std.mem.sliceTo(title, 0);
    const len = @min(title_str.len, info.title.len - 1);
    @memcpy(info.title[0..len], title_str[0..len]);
    info.title[len] = 0;
    markDirty();
}

fn toplevelHandleAppId(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1, app_id: [*c]const u8) callconv(.c) void {
    _ = handle;
    const info: *toplevel.ToplevelInfo = @ptrCast(@alignCast(data orelse return));
    const id_str = std.mem.sliceTo(app_id, 0);
    const len = @min(id_str.len, info.app_id.len - 1);
    @memcpy(info.app_id[0..len], id_str[0..len]);
    info.app_id[len] = 0;
    markDirty();
}

fn checkMaximizedWindows() void {
    // Auto-hide-on-maximize disabled — dock visibility is now controlled
    // only by the explicit autohide toggle in settings.
    _ = &toplevels;
    _ = toplevel_count;
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
    checkMaximizedWindows();
    markDirty();
}

fn toplevelHandleDone(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    _ = handle;
    markDirty();
}

fn toplevelHandleClosed(data: ?*anyopaque, handle: ?*c.zwlr_foreign_toplevel_handle_v1) callconv(.c) void {
    _ = data;
    const idx = toplevel.findIndex(&toplevels, toplevel_count, @ptrCast(handle orelse return));
    if (idx >= 0) {
        toplevel.removeAt(&toplevels, &toplevel_count, idx);
        markDirty();
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
    if (idx != std.math.maxInt(usize)) {
        _ = c.zwlr_foreign_toplevel_handle_v1_add_listener(handle, &toplevel_handle_listener, &toplevels[idx]);
        markDirty();
    }
}

const toplevel_manager_listener = c.zwlr_foreign_toplevel_manager_v1_listener{
    .toplevel = toplevelManagerToplevel,
    .finished = struct { fn f(_: ?*anyopaque, _: ?*c.zwlr_foreign_toplevel_manager_v1) callconv(.c) void {} }.f,
};

// ---- registry ----
fn registryGlobal(data: ?*anyopaque, reg: ?*c.wl_registry, name: u32, iface: [*c]const u8, version: u32) callconv(.c) void {
    _ = data;
    const iface_str = std.mem.sliceTo(iface, 0);
    if (std.mem.eql(u8, iface_str, "wl_compositor")) {
        compositor = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_compositor_interface, 4));
        panel_mod.global_wayland_ver = version;
    }
    else if (std.mem.eql(u8, iface_str, "wl_shm"))
        shm = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_shm_interface, 1))
    else if (std.mem.eql(u8, iface_str, "zwlr_layer_shell_v1"))
        layer_shell = @ptrCast(c.wl_registry_bind(reg, name, &c.zwlr_layer_shell_v1_interface, 1))
    else if (std.mem.eql(u8, iface_str, "zwlr_foreign_toplevel_manager_v1")) {
        toplevel_manager = @ptrCast(c.wl_registry_bind(reg, name, &c.zwlr_foreign_toplevel_manager_v1_interface, 3));
        _ = c.zwlr_foreign_toplevel_manager_v1_add_listener(toplevel_manager, &toplevel_manager_listener, null);
    } else if (std.mem.eql(u8, iface_str, "wl_seat")) {
        seat = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_seat_interface, 7));
        _ = c.wl_seat_add_listener(seat, &seat_listener, null);
    } else if (std.mem.eql(u8, iface_str, "wl_output")) {
        const out: ?*c.wl_output = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_output_interface, 2));
        _ = c.wl_output_add_listener(out, &output_listener, null);
    }
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
    pointer_on_launcher = (surface == launcher_surface.surface);
    pointer_on_modal = (surface == modal_surface.surface);
    if (autohide_dock and pointer_on_dock) {
        if (dock_surface.layer_surface) |ls| {
            c.zwlr_layer_surface_v1_set_size(ls, 0, DOCK_HEIGHT);
            c.zwlr_layer_surface_v1_set_exclusive_zone(ls, DOCK_HEIGHT);
            dock_surface.height = DOCK_HEIGHT;
            c.wl_surface_commit(dock_surface.surface);
        }
    }
    if (autohide_panel and pointer_on_panel) {
        if (panel_surface.layer_surface) |ls| {
            c.zwlr_layer_surface_v1_set_size(ls, 0, @intCast(panel_height));
            c.zwlr_layer_surface_v1_set_exclusive_zone(ls, @intCast(panel_height));
            panel_surface.height = panel_height;
            c.wl_surface_commit(panel_surface.surface);
        }
    }
    if (pointer_on_dock) {
        dock_hover_idx = dock_mod.iconAt(dock_surface.width, dock_surface.height, &toplevels, toplevel_count, pointer_x);
    }
    checkMaximizedWindows();
    dock_surface.dirty = true;
}

fn pointerLeave(data: ?*anyopaque, p: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = p;
    _ = serial;
    _ = surface;
    pointer_on_panel = false;
    pointer_on_dock = false;
    pointer_on_launcher = false;
    pointer_on_modal = false;
    hovered_widget = -1;
    dock_hover_idx = -1;
    if (autohide_dock) {
        if (dock_surface.layer_surface) |ls| {
            c.zwlr_layer_surface_v1_set_size(ls, 0, 1);
            c.zwlr_layer_surface_v1_set_exclusive_zone(ls, 0);
            dock_surface.height = 1;
            c.wl_surface_commit(dock_surface.surface);
        }
    }
    if (autohide_panel) {
        if (panel_surface.layer_surface) |ls| {
            c.zwlr_layer_surface_v1_set_size(ls, 0, 1);
            c.zwlr_layer_surface_v1_set_exclusive_zone(ls, 0);
            panel_surface.height = 1;
            c.wl_surface_commit(panel_surface.surface);
        }
    }
    checkMaximizedWindows();
    dock_surface.dirty = true;
}

fn pointerMotion(data: ?*anyopaque, p: ?*c.wl_pointer, time: u32, x: c.wl_fixed_t, y: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = p;
    _ = time;
    pointer_x = c.wl_fixed_to_int(x);
    pointer_y = c.wl_fixed_to_int(y);
    if (pointer_on_dock) {
        if (drag_dock_group >= 0) {
            const hover_group = dock_mod.groupAt(dock_surface.width, pointer_x);
            if (hover_group >= 0 and hover_group != drag_dock_group) {
                dock_mod.swapGroups(@intCast(drag_dock_group), @intCast(hover_group));
                drag_dock_group = hover_group;
            }
        }
        const new_idx = dock_mod.iconAt(dock_surface.width, dock_surface.height, &toplevels, toplevel_count, pointer_x);
        if (new_idx != dock_hover_idx) {
            dock_hover_idx = new_idx;
        }
        dock_surface.dirty = true;
    }

    // Track which panel widget the pointer is over
    if (pointer_on_panel and !settings_open) {
        var found_hover: i32 = -1;
        for (0..@intCast(@max(0, widget_count))) |i| {
            if (widgets[i].hidden) continue;
            if (pointer_x >= widget_x[i] and pointer_x < widget_x[i] + widgets[i].cached_w) {
                found_hover = @intCast(i);
                break;
            }
        }
        if (found_hover != hovered_widget) {
            hovered_widget = found_hover;
            panel_surface.dirty = true;
        }
    } else if (!pointer_on_panel) {
        if (hovered_widget != -1) {
            hovered_widget = -1;
            panel_surface.dirty = true;
        }
    }

    if (pointer_on_modal and modal_open) {
        const was = modal_state.close_hover;
        modal_state.close_hover = modal_mod.hitClose(modal_state, pointer_x, pointer_y);
        if (was != modal_state.close_hover) modal_surface.dirty = true;
    }
    if (pointer_on_panel and settings_open and settings_drag_idx >= 0) {
        const r = settingsRect();
        if (settings_tab == 1) {
            // Dock pinned-app drag reorder.
            const ah_y = SET_LIST_Y;
            const is_y = ah_y + SET_ROW_H + 10;
            const pins_start = is_y + SET_ROW_H + 14 + SET_ROW_H;
            if (pointer_y >= pins_start and pointer_y < r.y + r.h - 8) {
                const row = @divTrunc(pointer_y - pins_start, SET_ROW_H);
                if (row >= 0 and row < dock_mod.persistent_count and row != settings_drag_idx) {
                    dock_mod.swapGroups(@intCast(settings_drag_idx), @intCast(row));
                    settings_drag_idx = row;
                    // P12: defer syncConfigFromRuntime to button-release save; only
                    // reorder live state during motion.
                    config_dirty = true;
                    markDirty();
                }
            }
        } else if (settings_tab == 0) {
            // Widget list drag reorder.
            const list_x = r.x + 8;
            const list_w = r.w - 16;
            const first = settings_scroll;
            if (pointer_y >= SET_LIST_Y and pointer_y < r.y + r.h - 34) {
                const row = @divTrunc(pointer_y - SET_LIST_Y, SET_ROW_H);
                const idx = first + row;
                if (idx >= 0 and idx < widget_count and idx != settings_drag_idx) {
                    if (idx > settings_drag_idx) {
                        panel_mod.widgetListMove(settings_ui.widgetListRef(), @intCast(settings_drag_idx), 1);
                        settings_drag_idx += 1;
                    } else {
                        panel_mod.widgetListMove(settings_ui.widgetListRef(), @intCast(settings_drag_idx), -1);
                        settings_drag_idx -= 1;
                    }
                    // P12: defer syncConfigFromRuntime to button-release save.
                    config_dirty = true;
                    markDirty();
                }
            }
            _ = list_x;
            _ = list_w;
        }
    }
}

fn pointerButton(data: ?*anyopaque, p: ?*c.wl_pointer, serial: u32, time: u32, button: u32, state_w: u32) callconv(.c) void {
    _ = data;
    _ = p;
    _ = serial;
    _ = time;
    if (state_w == c.WL_POINTER_BUTTON_STATE_RELEASED) {
        drag_dock_group = -1;
        // Flush a pending settings-drag reorder exactly once on release
        // instead of saving on every motion event (issue #23).
        if (settings_drag_idx >= 0 and config_dirty) {
            config_manager.saveConfig();
        }
        settings_drag_idx = -1;
        markDirty();
        dock_surface.dirty = true;
        return;
    }
    if (state_w != c.WL_POINTER_BUTTON_STATE_PRESSED) return;

    // Modal click — dismiss via backdrop or × button; swallow clicks on the
    // card so the dialog captures attention until explicitly closed.
    if (pointer_on_modal and modal_open) {
        if (modal_mod.hitClose(modal_state, pointer_x, pointer_y)) {
            modalClose();
        } else if (std.mem.eql(u8, modal_title[0..modal_title_len], "Calendar") and pointer_x >= cal_prev_rect.x and pointer_x <= cal_prev_rect.x + cal_prev_rect.w and pointer_y >= cal_prev_rect.y and pointer_y <= cal_prev_rect.y + cal_prev_rect.h) {
            cal_month -= 1;
            if (cal_month < 0) {
                cal_month = 11;
                cal_year -= 1;
            }
            markDirty();
        } else if (std.mem.eql(u8, modal_title[0..modal_title_len], "Calendar") and pointer_x >= cal_next_rect.x and pointer_x <= cal_next_rect.x + cal_next_rect.w and pointer_y >= cal_next_rect.y and pointer_y <= cal_next_rect.y + cal_next_rect.h) {
            cal_month += 1;
            if (cal_month > 11) {
                cal_month = 0;
                cal_year += 1;
            }
            markDirty();
        } else if (std.mem.eql(u8, modal_title[0..modal_title_len], "Calendar") and pointer_x >= cal_today_rect.x and pointer_x <= cal_today_rect.x + cal_today_rect.w and pointer_y >= cal_today_rect.y and pointer_y <= cal_today_rect.y + cal_today_rect.h) {
            cal_month = cal_today_month;
            cal_year = cal_today_year;
            markDirty();
        } else if (!modal_mod.hitCard(modal_state, pointer_x, pointer_y)) {
            // Clicked the dark backdrop → dismiss.
            modalClose();
        }
        // Clicks on the card body are intentionally swallowed.
        return;
    }

    // Floating dock-launcher click
    if (pointer_on_launcher and dock_launcher.launcher_open) {
        if (dock_launcher.handleClick(pointer_x, pointer_y, launcher_surface.width, launcher_surface.height)) {
            if (!dock_launcher.launcher_open) dockLauncherClose();
            markDirty();
        }
        return;
    }

    // Dock click — activate/minimize window
    if (pointer_on_dock) {
        drag_dock_group = dock_mod.groupAt(dock_surface.width, pointer_x);
        if (dock_hover_idx == -2) {
            // Settings toggle on the dock — launch the out-of-process GTK
            // settings app (replaces the old in-panel settings UI).
            launchSettingsGtk();
            return;
        }

        if (dock_hover_idx == -3) {
            panel_mod.session_open = !panel_mod.session_open;
            applyPanelSurfaceHeight();
            markDirty();
            return;
        }

        // App-launcher toggle: open the OCWS apps launcher popup
        if (dock_hover_idx == -4) {
            app_launcher.toggleOcws();
            applyPanelSurfaceHeight();
            markDirty();
            return;
        }

        // Home toggle: open the full app-grid floating launcher
        if (dock_hover_idx == -5) {
            dock_launcher.toggle();
            if (dock_launcher.launcher_open) {
                dockLauncherOpen();
            } else {
                dockLauncherClose();
            }
            markDirty();
            return;
        }

        // Right-click: pin/unpin (the core Plank behavior). A pinned icon
        // (not running) is unpinned; a running, unpinned window is pinned.
        if (button == 3) {
            if (dock_hover_idx >= 1000) {
                _ = dock_mod.unpinAt(@intCast(dock_hover_idx - 1000));
                config_manager.saveConfig();
                markDirty();
                return;
            }
            if (dock_hover_idx >= 0 and dock_hover_idx < toplevel_count) {
                const info = &toplevels[@intCast(dock_hover_idx)];
                const app_id = info.app_id[0..std.mem.indexOfScalar(u8, &info.app_id, 0) orelse info.app_id.len];
                if (app_id.len > 0 and !dock_mod.isPinned(app_id)) {
                    _ = dock_mod.pinApp(app_id);
                    config_manager.saveConfig();
                    markDirty();
                }
                return;
            }
            return;
        }

        if (dock_hover_idx >= 1000) {
            dock_mod.launchPinned(@intCast(dock_hover_idx - 1000));
            return;
        }

        if (dock_hover_idx >= 0 and dock_hover_idx < toplevel_count and seat != null) {
            const info = &toplevels[@intCast(dock_hover_idx)];
            const handle: ?*c.zwlr_foreign_toplevel_handle_v1 = @ptrCast(@alignCast(info.handle));
            if (info.focused) {
                c.zwlr_foreign_toplevel_handle_v1_set_minimized(handle);
            } else {
                c.zwlr_foreign_toplevel_handle_v1_activate(handle, seat);
            }
            markDirty();
        }
        return;
    }

    // Panel click — handle widget clicks
    if (pointer_on_panel) {
        // Settings menu clicks — handled inside popup region; outside click
        // closes the popup and falls through to widget dispatch below.
        if (settings_open) {
            const handled = settings_ui.handleSettingsClick(pointer_x, pointer_y, button);
            markDirty();
            if (handled) return;
        }

        // Session-action popup clicks — same close-on-outside pattern.
        if (panel_mod.session_open) {
            const handled = session_ui.handleSessionClick(pointer_x, pointer_y, button);
            markDirty();
            if (handled) return;
        }

        // App launcher popup clicks — same pattern.
        if (app_launcher.launcher_open) {
            const handled = app_launcher.handleClick(pointer_x, pointer_y, panel_surface.width, panel_surface.height);
            applyPanelSurfaceHeight();
            markDirty();
            if (handled) return;
        }

        // Widget clicks
        for (0..@intCast(@max(0, widget_count))) |i| {
            if (pointer_x >= widget_x[i] and pointer_x < widget_x[i] + widgets[i].cached_w) {
                if (widgets[i].click_fn) |fn_ptr| {
                    _ = fn_ptr(&widgets[i], button, pointer_x - widget_x[i], pointer_y);
                    if (panel_mod.request_calendar_modal) {
                        panel_mod.request_calendar_modal = false;
                        modalOpen("Calendar");
                    }
                    if (panel_mod.request_settings_modal) {
                        panel_mod.request_settings_modal = false;
                        settings_open = true;
                        applyPanelSurfaceHeight();
                    }
                }
                // Opening the session popup needs a taller panel surface so the
                // popup (drawn below the 24px bar) is visible.
                if (panel_mod.session_open) applyPanelSurfaceHeight();
                markDirty();
                return;
            }
        }
    }
}

// Resize the panel layer surface to fit settings / session popups, or shrink
// back to the bare bar when both are closed.
const SESSION_PANEL_H: i32 = 300;
pub fn applyPanelSurfaceHeight() void {
    const h: i32 = if (settings_open) PANEL_SETTINGS_HEIGHT
    else if (panel_mod.session_open) SESSION_PANEL_H
    else if (app_launcher.launcher_open) blk: {
        app_launcher.ensureEntries();
        const lr = app_launcher.launcherRect(panel_surface.width, panel_height);
        break :blk lr.h + 8;
    } else panel_height;
    if (panel_surface.layer_surface) |ls| {
        c.zwlr_layer_surface_v1_set_size(ls, 0, @intCast(h));
        c.wl_surface_commit(panel_surface.surface);
    }
    panel_surface.height = h;
    panel_surface.dirty = true;
}

// ---- Settings panel geometry ----
const SET_X_OFF = 12;
const SET_W = 440;
pub const SET_CARD_Y = 52;
const SET_CARD_H = PANEL_SETTINGS_HEIGHT - SET_CARD_Y - 8;
pub const SET_TAB_H = 34;
pub const SET_ROW_H = 36;
pub const SET_LIST_Y = SET_CARD_Y + 30 + SET_TAB_H + 12;
pub const FONT_SCALE_STEP: f64 = 0.1;

// Layout of the settings card. Shared by click handling and drawing.
pub const SettingsRect = struct { x: i32, y: i32, w: i32, h: i32 };
pub fn settingsRect() SettingsRect {
    return .{
        .x = panel_surface.width - SET_W - SET_X_OFF,
        .y = SET_CARD_Y,
        .w = SET_W,
        .h = SET_CARD_H,
    };
}

// Launch the out-of-process GTK settings app. The binary lives next to this
// shell's executable (both installed by `zig build --prefix ~/.local`). We read
// /proc/self/exe to locate it so it works regardless of $PATH.
fn launchSettingsGtk() void {
    var self_buf: [512]u8 = undefined;
    const n = c.readlink("/proc/self/exe", &self_buf, self_buf.len);
    if (n <= 0) {
        _ = panel_mod.spawnCmd("zigshell-settings-gtk &");
        return;
    }
    const self_path = self_buf[0..@as(usize, @intCast(n))];
    const dir = std.fs.path.dirname(self_path) orelse ".";
    var cmd: [576]u8 = undefined;
    const full = std.fmt.bufPrintZ(&cmd, "{s}/zigshell-settings-gtk &", .{dir}) catch return;
    _ = panel_mod.spawnCmd(full);
}

// Open the system-wide app launcher (fuzzel). This is the Plank/Crystal-Dock
// equivalent of "show all apps" — launches any installed application even if it
// is not pinned to the dock.
fn spawnLauncher() void {
    // Mirror the launcher widget's command ('fuzzel &').
    _ = panel_mod.spawnCmd("fuzzel &");
}

// P6: apply a new panel height at runtime. Updates the variable used by all
// layout math and, if the layer surface already exists, resizes it (respecting
// auto-hide) so the change takes effect without a restart.
pub fn setPanelHeight(h: i32) void {
    const nh = @max(16, @min(h, 200));
    panel_height = nh;
    if (panel_surface.layer_surface) |ls| {
        const visible = !(autohide_panel and !pointer_on_panel);
        const sh = if (visible) nh else 1;
        c.zwlr_layer_surface_v1_set_size(ls, 0, @intCast(sh));
        c.zwlr_layer_surface_v1_set_exclusive_zone(ls, @intCast(if (visible) nh else 0));
        panel_surface.height = sh;
        c.wl_surface_commit(panel_surface.surface);
    }
    markDirty();
}

// Apply a font-scale factor to the live panel and (best-effort) to the rest of
// the system via scripts/font-scale.sh so labwc/GTK/Qt rescale together.
pub fn applyFontScale(scale: f64) void {
    font_scale = scale;
    panel_mod.setFontScale(scale);
    markDirty();
}

// Step the panel font scale by `delta` (e.g. +0.1 / -0.1), clamp to sane bounds,
// persist, and propagate to the whole system (labwc/GTK/Qt via font-scale.sh).
pub fn changeFontScale(delta: f64) void {
    const next = std.math.clamp(font_scale + delta, 0.6, 2.5);
    applyFontScale(next);
    config_manager.syncConfigFromRuntime();
    config_manager.saveConfig();
    // Best-effort: scale labwc/GTK/Qt together. font-scale.sh works in absolute
    // px sizes (6–24), so map the panel scale factor onto its default 10px base.
    const gtk_size = std.math.clamp(@as(i32, @intFromFloat(next * 10.0 + 0.5)), 6, 24);
    var size_arg: [16]u8 = undefined;
    _ = std.fmt.bufPrintZ(&size_arg, "{d}", .{gtk_size}) catch {};
    var root: []const u8 = ".";
    if (c.getenv("ZIGSHELL_ROOT")) |r| root = std.mem.sliceTo(r, 0);
    var cmd: [512]u8 = undefined;
    const full = std.fmt.bufPrintZ(&cmd, "{s}/scripts/font-scale.sh set {s}", .{ root, std.mem.sliceTo(&size_arg, 0) }) catch return;
    _ = panel_mod.spawnCmd(full);
}

// ===== Widget Manager tab =====


// Returns a view over the live widget globals (full capacity) so list ops can
// append up to MAX_WIDGETS while `count` tracks the valid portion.
pub var g_widget_list: panel_mod.WidgetList = undefined;

// ===== Dock Manager tab =====


pub fn setDockAutohide(on: bool) void {
    autohide_dock = on;
    if (dock_surface.layer_surface) |ls| {
        if (on and !pointer_on_dock) {
            c.zwlr_layer_surface_v1_set_size(ls, 0, 1);
            c.zwlr_layer_surface_v1_set_exclusive_zone(ls, 0);
            dock_surface.height = 1;
        } else {
            c.zwlr_layer_surface_v1_set_size(ls, 0, DOCK_HEIGHT);
            c.zwlr_layer_surface_v1_set_exclusive_zone(ls, DOCK_HEIGHT);
            dock_surface.height = DOCK_HEIGHT;
        }
        c.wl_surface_commit(dock_surface.surface);
    }
    markDirty();
}

// P15: collapse the panel to a 1px strip (no exclusive zone) when auto-hide is
// on and the pointer is not over it; reveal to full height on hover.
pub fn setPanelAutohide(on: bool) void {
    autohide_panel = on;
    if (panel_surface.layer_surface) |ls| {
        if (on and !pointer_on_panel) {
            c.zwlr_layer_surface_v1_set_size(ls, 0, 1);
            c.zwlr_layer_surface_v1_set_exclusive_zone(ls, 0);
            panel_surface.height = 1;
        } else {
            c.zwlr_layer_surface_v1_set_size(ls, 0, @intCast(panel_height));
            c.zwlr_layer_surface_v1_set_exclusive_zone(ls, @intCast(panel_height));
            panel_surface.height = panel_height;
        }
        c.wl_surface_commit(panel_surface.surface);
    }
    markDirty();
}

fn pointerAxis(data: ?*anyopaque, p: ?*c.wl_pointer, time: u32, axis: u32, value: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = p;
    _ = time;
    _ = axis;

    const dir: i32 = if (value > 0) 1 else if (value < 0) -1 else 0;
    if (dir == 0) return;

    if (pointer_on_launcher and dock_launcher.launcher_open) {
        dock_launcher.handleScroll(dir);
        launcher_surface.dirty = true;
        return;
    }

    if (pointer_on_panel) {
        // App launcher scroll
        if (app_launcher.launcher_open) {
            app_launcher.handleScroll(dir);
            panel_surface.dirty = true;
            return;
        }
        for (0..@intCast(@max(0, widget_count))) |i| {
            if (pointer_x >= widget_x[i] and pointer_x < widget_x[i] + widgets[i].cached_w) {
                if (widgets[i].scroll_fn) |fn_ptr| {
                    _ = fn_ptr(&widgets[i], dir);
                }
                return;
            }
        }
    }
}

const pointer_listener = c.wl_pointer_listener{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
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
    // Without creating a wl_keyboard object the compositor has nothing to
    // deliver key events to, so the panel can never receive keyboard input
    // even when keyboard_interactivity is enabled.
    if ((caps & c.WL_SEAT_CAPABILITY_KEYBOARD) != 0 and keyboard == null) {
        keyboard = c.wl_seat_get_keyboard(s);
        _ = c.wl_keyboard_add_listener(keyboard, &keyboard_listener, null);
    }
}

const seat_listener = c.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = struct { fn f(_: ?*anyopaque, _: ?*c.wl_seat, _: [*c]const u8) callconv(.c) void {} }.f,
};

// ==== KEYBOARD CALLBACKS ====

fn keyboardKeymap(data: ?*anyopaque, kb: ?*c.wl_keyboard, format: u32, fd: c_int, size: u32) callconv(.c) void {
    _ = data;
    _ = kb;
    _ = format;
    // Per the wl_keyboard protocol the client must map the shared keymap
    // memory. Closing the fd without mapping it can leave the keyboard
    // unusable on some compositors. We don't parse it (no xkbcommon dep),
    // but we map it and keep it mapped for the lifetime of the seat.
    if (keyboard_keymap_mapped) |m| {
        _ = c.munmap(@ptrCast(m), keyboard_keymap_size);
        keyboard_keymap_mapped = null;
    }
    if (keyboard_keymap_fd >= 0) _ = c.close(keyboard_keymap_fd);
    keyboard_keymap_fd = fd;
    keyboard_keymap_size = size;
    if (size > 0 and fd >= 0) {
        const mapped = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
        if (mapped != c.MAP_FAILED) {
            keyboard_keymap_mapped = @ptrCast(@alignCast(mapped));
        }
    }
}

fn keyboardEnter(data: ?*anyopaque, kb: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface, keys: ?*c.wl_array) callconv(.c) void {
    _ = data;
    _ = kb;
    _ = serial;
    _ = keys;
    keyboard_focus_surface = surface;
    markDirty();
}

fn keyboardLeave(data: ?*anyopaque, kb: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = kb;
    _ = serial;
    _ = surface;
    keyboard_focus_surface = null;
    markDirty();
}

fn keyboardKey(data: ?*anyopaque, kb: ?*c.wl_keyboard, serial: u32, time: u32, key: u32, state_w: u32) callconv(.c) void {
    _ = data;
    _ = kb;
    _ = serial;
    _ = time;
    if (state_w != c.WL_KEYBOARD_KEY_STATE_PRESSED) return;
    if (modal_open) {
        if (key == 9) {
            // Escape closes the modal.
            modalClose();
        }
        return;
    }
    if (app_launcher.launcher_open) {
        if (key == 9) {
            // Escape closes the launcher.
            app_launcher.launcher_open = false;
            applyPanelSurfaceHeight();
            markDirty();
        }
        return;
    }
    if (dock_launcher.launcher_open) {
        if (key == 9) {
            // Escape closes the floating dock launcher.
            dock_launcher.launcher_open = false;
            dockLauncherClose();
            markDirty();
        }
        return;
    }
    return;
}

fn keyboardModifiers(data: ?*anyopaque, kb: ?*c.wl_keyboard, serial: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) callconv(.c) void {
    _ = data;
    _ = kb;
    _ = serial;
    _ = mods_depressed;
    _ = mods_latched;
    _ = mods_locked;
    _ = group;
    markDirty();
}

fn keyboardRepeatInfo(data: ?*anyopaque, kb: ?*c.wl_keyboard, rate: i32, delay: i32) callconv(.c) void {
    _ = data;
    _ = kb;
    _ = rate;
    _ = delay;
}

const keyboard_listener = c.wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeatInfo,
};

// ==== LAYER SURFACE CALLBACKS ====

fn layerSurfaceConfigure(data: ?*anyopaque, surface: ?*c.zwlr_layer_surface_v1, serial: u32, w: u32, h: u32) callconv(.c) void {
    _ = data;
    const ss = if (surface == panel_surface.layer_surface)
        &panel_surface
    else if (surface == launcher_surface.layer_surface)
        &launcher_surface
    else if (surface == dock_surface.layer_surface)
        &dock_surface
    else if (surface == modal_surface.layer_surface)
        &modal_surface
    else {
        // Unknown surface — ack the configure but don't corrupt any state.
        c.zwlr_layer_surface_v1_ack_configure(surface, serial);
        return;
    };
    const wi: i32 = @intCast(@min(w, 16384));
    const hi: i32 = @intCast(@min(h, 16384));
    if (wi != 0 and hi != 0 and (wi != ss.width or hi != ss.height)) {
        ss.width = wi;
        ss.height = hi;
        markDirty();
    }
    c.zwlr_layer_surface_v1_ack_configure(surface, serial);
    // The launcher is a fixed-size floating panel; do not re-request its size
    // here (that would fight toggleLauncher). Panel/dock keep their height.
    if (surface != launcher_surface.layer_surface) {
        c.zwlr_layer_surface_v1_set_size(surface, 0, @intCast(@max(0, ss.height)));
    }
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

const launcher_layer_listener = c.zwlr_layer_surface_v1_listener{
    .configure = layerSurfaceConfigure,
    .closed = layerSurfaceClosed,
};

const modal_layer_listener = c.zwlr_layer_surface_v1_listener{
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
    } else if (cb == launcher_surface.frame_cb) {
        c.wl_callback_destroy(cb);
        launcher_surface.frame_cb = null;
    } else if (cb == modal_surface.frame_cb) {
        c.wl_callback_destroy(cb);
        modal_surface.frame_cb = null;
    }
}

const frame_listener = c.wl_callback_listener{
    .done = frameDone,
};

// ---- surface (HiDPI / fractional scale) ----
fn surfacePreferredScale(data: ?*anyopaque, surface: ?*c.wl_surface, scale: i32) callconv(.c) void {
    _ = data;
    if (scale <= 0) return;
    const ss = if (surface == panel_surface.surface) &panel_surface
        else if (surface == dock_surface.surface) &dock_surface
        else if (surface == launcher_surface.surface) &launcher_surface
        else if (surface == modal_surface.surface) &modal_surface
        else return;
    ss.scale = @intCast(scale);
    if (ss.surface) |s| c.wl_surface_set_buffer_scale(s, @intCast(ss.scale));
    markDirty();
}

const surface_listener = c.wl_surface_listener{
    .enter = struct { fn f(_: ?*anyopaque, _: ?*c.wl_surface, _: ?*c.wl_output) callconv(.c) void {} }.f,
    .leave = struct { fn f(_: ?*anyopaque, _: ?*c.wl_surface, _: ?*c.wl_output) callconv(.c) void {} }.f,
    .preferred_buffer_scale = surfacePreferredScale,
    .preferred_buffer_transform = struct { fn f(_: ?*anyopaque, _: ?*c.wl_surface, _: u32) callconv(.c) void {} }.f,
};

// ---- multi-monitor (wl_output) tracking ----
const OutputInfo = struct {
    output: ?*c.wl_output = null,
    name: [64]u8 = std.mem.zeroes([64]u8),
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,
    scale: i32 = 1,
    present: bool = false,
};

var outputs: [16]OutputInfo = std.mem.zeroes([16]OutputInfo);
var output_count: usize = 0;

fn findOrAddOutput(out: ?*c.wl_output) *OutputInfo {
    for (&outputs) |*o| {
        if (o.output == out) return o;
    }
    if (output_count < outputs.len) {
        const o = &outputs[output_count];
        output_count += 1;
        o.output = out;
        return o;
    }
    return &outputs[0];
}

fn outputGeometry(_: ?*anyopaque, out: ?*c.wl_output, x: i32, y: i32, _: i32, _: i32, _: i32, _: ?[*:0]const u8, _: ?[*:0]const u8, _: i32) callconv(.c) void {
    const o = findOrAddOutput(out);
    o.x = x;
    o.y = y;
}

fn outputMode(_: ?*anyopaque, out: ?*c.wl_output, _: u32, w: i32, h: i32, _: i32) callconv(.c) void {
    const o = findOrAddOutput(out);
    o.w = w;
    o.h = h;
}

fn outputScale(_: ?*anyopaque, out: ?*c.wl_output, factor: i32) callconv(.c) void {
    const o = findOrAddOutput(out);
    o.scale = factor;
}

fn outputName(_: ?*anyopaque, out: ?*c.wl_output, name: ?[*:0]const u8) callconv(.c) void {
    if (name == null) return;
    const o = findOrAddOutput(out);
    const n = std.mem.sliceTo(name.?, 0);
    const len = @min(n.len, o.name.len - 1);
    @memcpy(o.name[0..len], n[0..len]);
    o.name[len] = 0;
}

fn outputDone(_: ?*anyopaque, out: ?*c.wl_output) callconv(.c) void {
    const o = findOrAddOutput(out);
    o.present = true;
    std.log.info("zigshell-cairo-pango: output {s}: {d}x{d} @ scale {d} pos ({d},{d})", .{ o.name, o.w, o.h, o.scale, o.x, o.y });
}

const output_listener = c.wl_output_listener{
    .geometry = outputGeometry,
    .mode = outputMode,
    .done = outputDone,
    .scale = outputScale,
    .name = outputName,
    .description = struct { fn f(_: ?*anyopaque, _: ?*c.wl_output, _: ?[*:0]const u8) callconv(.c) void {} }.f,
};

// ==== LIVE CONFIG RELOAD (SIGHUP) ====

fn onSighup(_: c_int) callconv(.c) void {
    reload_config = true;
}

fn reloadWidgets() void {
    const path = config_path orelse return;
    // Preserve old state
    const old_count = widget_count;
    var old_widgets: [panel_mod.MAX_WIDGETS]panel_mod.Widget = undefined;
    const preserve = @min(old_count, panel_mod.MAX_WIDGETS);
    for (0..@intCast(preserve)) |i| old_widgets[i] = widgets[i];

    const n = panel_mod.widgetCreateDefault(&widgets);
    _ = n;
    _ = pcfg.Config.load(std.heap.page_allocator, path, .{ .widgets = &widgets, .count = &widget_count });

    // Restore accumulated / sampled fields
    for (0..@intCast(@max(0, widget_count))) |i| {
        for (0..@intCast(preserve)) |j| {
            if (widgets[i].wtype == old_widgets[j].wtype) {
                widgets[i].cpu_prev_total = old_widgets[j].cpu_prev_total;
                widgets[i].cpu_prev_idle = old_widgets[j].cpu_prev_idle;
                widgets[i].cpu_txt = old_widgets[j].cpu_txt;
                widgets[i].mem_txt = old_widgets[j].mem_txt;
                widgets[i].temp_txt = old_widgets[j].temp_txt;
                widgets[i].disk_txt = old_widgets[j].disk_txt;
                widgets[i].bat_lvl = old_widgets[j].bat_lvl;
                widgets[i].bat_charging = old_widgets[j].bat_charging;
                widgets[i].bat_txt = old_widgets[j].bat_txt;
                widgets[i].vol_mute = old_widgets[j].vol_mute;
                widgets[i].vol_txt = old_widgets[j].vol_txt;
                widgets[i].net_txt = old_widgets[j].net_txt;
                widgets[i].net_rx_prev = old_widgets[j].net_rx_prev;
                widgets[i].net_tx_prev = old_widgets[j].net_tx_prev;
                widgets[i].net_day_rx = old_widgets[j].net_day_rx;
                widgets[i].net_day_tx = old_widgets[j].net_day_tx;
                widgets[i].net_hist_day_rx = old_widgets[j].net_hist_day_rx;
                widgets[i].net_hist_day_tx = old_widgets[j].net_hist_day_tx;
                widgets[i].net_day_idx = old_widgets[j].net_day_idx;
                widgets[i].net_save_tick = old_widgets[j].net_save_tick;
                widgets[i].kb_idx = old_widgets[j].kb_idx;
                widgets[i].kb_txt = old_widgets[j].kb_txt;
                widgets[i].kb_layouts = old_widgets[j].kb_layouts;
                widgets[i].ver_txt = old_widgets[j].ver_txt;
                widgets[i].clock_txt = old_widgets[j].clock_txt;
                break;
            }
        }
    }

    config_manager.applyConfigToRuntime();
    markDirty();
    std.log.info("zigshell-cairo-pango: reloaded config from {s}", .{path});
}

// ==== RENDERING ====

const shm_log = std.log.scoped(.shm);

fn createShmFd(size: usize) ?i32 {
    var name_buf: [19]u8 = "/tmp/wl_shm-XXXXXX".* ++ .{0};
    const name_z: [*:0]u8 = @ptrCast(&name_buf);
    const fd = c.mkstemp(name_z);
    if (fd < 0) {
        shm_log.err("mkstemp failed for SHM backing file (size={d}): errno {d}", .{ size, errno() });
        return null;
    }
    _ = c.unlink(name_z);
    if (c.ftruncate(fd, @intCast(size)) < 0) {
        shm_log.err("ftruncate failed for SHM fd (size={d}): errno {d}", .{ size, errno() });
        _ = c.close(fd);
        return null;
    }
    return fd;
}

fn errno() c_int {
    return std.c._errno().*;
}

fn ensureBuffer(ss: *SurfaceState) void {
    const w = ss.width * @as(i32, @intCast(ss.scale));
    const h = ss.height * @as(i32, @intCast(ss.scale));
    if (w <= 0 or h <= 0) return;

    const stride = c.cairo_format_stride_for_width(c.CAIRO_FORMAT_ARGB32, w);
    if (stride <= 0) return;
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
        const fd = createShmFd(size) orelse {
            shm_log.err("cannot allocate buffer ({d}x{d}, {d} bytes): SHM fd creation failed; surface will not render", .{ w, h, size });
            return;
        };
        const data_ptr = c.mmap(null, size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
        if (data_ptr == c.MAP_FAILED) {
            shm_log.err("mmap failed for buffer ({d}x{d}, {d} bytes): errno {d}; surface will not render", .{ w, h, size, errno() });
            _ = c.close(fd);
            return;
        }
        ss.shm_data = @ptrCast(data_ptr);
        const pool = c.wl_shm_create_pool(shm, fd, @intCast(size));
        ss.buffer = c.wl_shm_pool_create_buffer(pool, 0, w, h, stride, c.WL_SHM_FORMAT_ARGB8888);
        c.wl_shm_pool_destroy(pool);
        _ = c.close(fd);
        if (ss.buffer == null) {
            shm_log.err("wl_shm_pool_create_buffer returned null ({d}x{d}); surface will not render", .{ w, h });
            _ = c.munmap(ss.shm_data, size);
            ss.shm_data = null;
            return;
        }
        ss.cairo_surface = c.cairo_image_surface_create_for_data(ss.shm_data, c.CAIRO_FORMAT_ARGB32, w, h, stride);
        ss.cairo_cr = c.cairo_create(ss.cairo_surface);
        c.cairo_scale(ss.cairo_cr, @floatFromInt(ss.scale), @floatFromInt(ss.scale));
        ss.buf_width = w;
        ss.buf_height = h;
        ss.buf_size = size;
    }
}

fn renderPanel() void {
    ensureBuffer(&panel_surface);
    const cr = panel_surface.cairo_cr orelse return;
    const w = panel_surface.width;
    const t = &theme.current;

    // Clear whole surface
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_CLEAR);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    // Panel background (compact bar)
    const ph = panel_height;
    const grad = c.cairo_pattern_create_linear(0, 0, 0, ph);
    c.cairo_pattern_add_color_stop_rgba(grad, 0.0, t.bg_color[0], t.bg_color[1], t.bg_color[2], t.bg_color[3]);
    c.cairo_pattern_add_color_stop_rgba(grad, 1.0, t.bg_gradient_end[0], t.bg_gradient_end[1], t.bg_gradient_end[2], t.bg_gradient_end[3]);
    c.cairo_set_source(cr, grad);
    c.cairo_rectangle(cr, 0, 0, w, ph);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(grad);

    // Accent line at bottom of panel
    theme.setSource(cr, t.accent_color);
    c.cairo_rectangle(cr, 0, ph - 2, w, 2);
    c.cairo_fill(cr);

    // Measure and layout widgets
    const pad: i32 = 6;
    _ = panel_mod.widgetListWidth(widgets[0..@intCast(@max(0, widget_count))], ph, pad, cr);
    const x0: i32 = 8;

    var left_w: i32 = 0;
    var right_w: i32 = 0;
    for (0..@intCast(@max(0, widget_count))) |i| {
        if (widgets[i].hidden) continue;
        if (widgets[i].side == 1) right_w += widgets[i].cached_w + pad
        else left_w += widgets[i].cached_w + pad;
    }
    if (left_w > 0) left_w -= pad;
    if (right_w > 0) right_w -= pad;

    // Reserve space for settings button
    var x: i32 = x0;
    for (0..@intCast(@max(0, widget_count))) |i| {
        if (widgets[i].hidden or widgets[i].side == 1) continue;
        widget_x[i] = x;
        x += widgets[i].cached_w + pad;
    }

    // Clamp rx to 0 to prevent signed underflow when right-side widgets +
    // settings button exceed panel width (C3).
    var rx: i32 = @intCast(@max(@as(i64, 0), @as(i64, w) - @as(i64, x0) - @as(i64, right_w)));
    if (rx < x) rx = x;
    for (0..@intCast(@max(0, widget_count))) |i| {
        if (widgets[i].hidden or widgets[i].side != 1) continue;
        widget_x[i] = rx;
        rx += widgets[i].cached_w + pad;
    }

    // Draw widgets
    for (0..@intCast(@max(0, widget_count))) |i| {
        if (widgets[i].hidden) continue;
        // P10: per-widget hover feedback — translucent rounded rect behind the
        // widget currently under the pointer.
        if (pointer_on_panel) {
            const wx = widget_x[i];
            const ww = widgets[i].cached_w;
            const hx0 = wx - 2;
            const hx1 = wx + ww + 2;
            if (pointer_x >= hx0 and pointer_x <= hx1 and pointer_y >= 0 and pointer_y <= ph) {
                c.cairo_set_source_rgba(cr, t.accent_color[0], t.accent_color[1], t.accent_color[2], 0.18);
                roundedRect(cr, @floatFromInt(hx0), 3, @floatFromInt(hx1 - hx0), @floatFromInt(ph - 6), 6.0);
                c.cairo_fill(cr);
            }
        }
        if (widgets[i].draw_fn) |fn_ptr| {
            fn_ptr(&widgets[i], cr, widget_x[i], 0, ph);
        }
    }
    // Draw settings menu if open
    if (settings_open) {
        settings_ui.drawSettingsMenu(cr, w, ph);
    }

    // Draw session-action popup if open
    if (panel_mod.session_open) {
        session_ui.drawSessionMenu(cr, w, ph);
    }

    // Draw app launcher popup if open
    if (app_launcher.launcher_open) {
        app_launcher.draw(cr, w, ph, pointer_x, pointer_y);
    }

    // drawDynamicIsland(cr, w);

    c.cairo_surface_flush(panel_surface.cairo_surface);
    panel_surface.dirty_region.add(0, 0, panel_surface.buf_width, panel_surface.buf_height);
}

fn drawDynamicIsland(cr: *c.cairo_t, w: i32) void {
    const island_w = 200;
    const island_h = 32;
    const x = @divTrunc(w - island_w, 2);
    const y = panel_height - 6;
    
    // Draw rounded background
    c.cairo_set_source_rgba(cr, 0.05, 0.05, 0.07, 0.95);
    roundedRect(cr, @floatFromInt(x), @floatFromInt(y), @floatFromInt(island_w), @floatFromInt(island_h), 16.0);
    c.cairo_fill(cr);
    
    // Draw subtle border
    c.cairo_set_source_rgba(cr, 1, 1, 1, 0.1);
    c.cairo_set_line_width(cr, 1.0);
    roundedRect(cr, @floatFromInt(x), @floatFromInt(y), @floatFromInt(island_w), @floatFromInt(island_h), 16.0);
    c.cairo_stroke(cr);
    
    // Draw some text and a small icon inside
    _ = panel_mod.widgetText(cr, "🎵", x + 12, y + 22, "Inter 10", 0.9, 0.9, 0.9);
    _ = panel_mod.widgetText(cr, "Zigshell Enrichments", x + 34, y + 20, "Inter Bold 10", 1.0, 1.0, 1.0);
}

// helper for rounded rectangles
pub fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    c.cairo_move_to(cr, x + w - r, y);
    c.cairo_arc(cr, x + w - r, y + r, r, -std.math.pi / 2.0, 0);
    c.cairo_arc(cr, x + w - r, y + h - r, r, 0, std.math.pi / 2.0);
    c.cairo_arc(cr, x + r, y + h - r, r, std.math.pi / 2.0, std.math.pi);
    c.cairo_arc(cr, x + r, y + r, r, std.math.pi, 3.0 * std.math.pi / 2.0);
    c.cairo_close_path(cr);
}

// ===== Session-action popup =====
// A small popup anchored to the bottom-right of the panel, opened by the
// "Session" widget. Lists session actions (logout/lock/suspend/...) and runs
// the chosen command when an entry is picked.



// ===== Widget Manager tab =====



// A "Font Size" control: label on the left, [−] [value%] [+] on the right.
// Click handling lives in handleDockClick (FONT_SCALE_Y sentinel row).

// ===== Dock Manager tab =====



fn renderDock() void {
    if (dock_surface.height <= 0) {
        if (dock_surface.buffer != null) submitSurface(&dock_surface);
        return;
    }
    ensureBuffer(&dock_surface);
    dock_mod.draw(
        dock_surface.cairo_cr orelse return,
        dock_surface.width,
        dock_surface.height,
        &toplevels,
        toplevel_count,
        dock_hover_idx,
        if (pointer_on_dock) @as(f64, @floatFromInt(pointer_x)) else -1.0,
    );
    if (dock_surface.cairo_cr) |cr| drawDockTooltip(cr, dock_surface.width, dock_surface.height);
    c.cairo_surface_flush(dock_surface.cairo_surface);
    dock_surface.dirty_region.add(0, 0, dock_surface.buf_width, dock_surface.buf_height);
}

// ---- App launcher ----
// The floating launcher panel is disabled by default (no-op).

fn toggleLauncher() void {
    // Floating launcher panel is disabled by default. Intentionally a no-op.
    return;
}

// ================= Global Modal =================
//
// A full-screen TOP-layer overlay with a dark translucent backdrop and a
// centered, rounded content card. While open it captures input (Escape,
// backdrop click, or the × button dismiss it) and blocks the rest of the
// shell from receiving clicks. Reusable by any feature that needs an alert or
// confirmation dialog.

const MODAL_W: i32 = 480;
const MODAL_H: i32 = 320;
const MODAL_PAD: i32 = 18;

var cal_year: i32 = 0;
var cal_month: i32 = 0; // 0..11
var cal_today_year: i32 = 0;
var cal_today_month: i32 = 0;
var cal_today_day: i32 = 0;

fn modalOpen(title: []const u8) void {
    modal_open = true;
    const n = @min(title.len, modal_title.len - 1);
    @memcpy(modal_title[0..n], title[0..n]);
    modal_title[n] = 0;
    modal_title_len = n;
    modal_state = .{ .open = true };

    if (std.mem.eql(u8, title, "Calendar")) {
        const ts = c.time(null);
        const tm = c.localtime(&ts);
        cal_today_year = tm.*.tm_year + 1900;
        cal_today_month = tm.*.tm_mon;
        cal_today_day = tm.*.tm_mday;
        
        cal_year = cal_today_year;
        cal_month = cal_today_month;
    }

    // Lazily create the modal layer surface the first time it opens.
    if (modal_surface.surface == null) {
        modal_surface.surface = c.wl_compositor_create_surface(compositor) orelse return;
        _ = c.wl_surface_add_listener(modal_surface.surface, &surface_listener, null);
    }
    if (modal_surface.layer_surface == null) {
        modal_surface.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
            layer_shell,
            modal_surface.surface,
            null,
            c.ZWLR_LAYER_SHELL_V1_LAYER_TOP,
            "zigshell-cairo-pango-modal",
        );
        _ = c.zwlr_layer_surface_v1_add_listener(modal_surface.layer_surface, &modal_layer_listener, null);
        // Anchor to all edges so the surface covers the whole output.
        const anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
            c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
            c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
            c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
        c.zwlr_layer_surface_v1_set_anchor(modal_surface.layer_surface, anchor);
        c.zwlr_layer_surface_v1_set_exclusive_zone(modal_surface.layer_surface, 0);
        c.zwlr_layer_surface_v1_set_keyboard_interactivity(modal_surface.layer_surface, 1);
    }
    markDirty();
}

fn modalClose() void {
    modal_open = false;
    modal_state.open = false;
    if (modal_surface.frame_cb) |cb| {
        c.wl_callback_destroy(cb);
        modal_surface.frame_cb = null;
    }
    if (modal_surface.layer_surface) |ls| {
        c.zwlr_layer_surface_v1_destroy(ls);
        modal_surface.layer_surface = null;
    }
    if (modal_surface.surface) |s| {
        c.wl_surface_destroy(s);
        modal_surface.surface = null;
    }
    markDirty();
}

// ---- Floating dock launcher surface management ----

fn dockLauncherOpen() void {
    dock_launcher.ensureEntries();
    const ch = dock_launcher.cardHeight(panel_surface.width);
    if (launcher_surface.surface == null) {
        launcher_surface.surface = c.wl_compositor_create_surface(compositor) orelse return;
        _ = c.wl_surface_add_listener(launcher_surface.surface, &surface_listener, null);
    }
    if (launcher_surface.layer_surface == null) {
        launcher_surface.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
            layer_shell,
            launcher_surface.surface,
            null,
            c.ZWLR_LAYER_SHELL_V1_LAYER_TOP,
            "zigshell-cairo-pango-launcher",
        );
        _ = c.zwlr_layer_surface_v1_add_listener(launcher_surface.layer_surface, &launcher_layer_listener, null);
        const anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
            c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
            c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
        c.zwlr_layer_surface_v1_set_anchor(launcher_surface.layer_surface, anchor);
        c.zwlr_layer_surface_v1_set_exclusive_zone(launcher_surface.layer_surface, 0);
        c.zwlr_layer_surface_v1_set_margin(launcher_surface.layer_surface, 0, 0, DOCK_HEIGHT + 6, 0);
        c.zwlr_layer_surface_v1_set_keyboard_interactivity(launcher_surface.layer_surface, 1);
    }
    c.zwlr_layer_surface_v1_set_size(launcher_surface.layer_surface, 0, @intCast(ch));
    launcher_surface.height = ch;
    launcher_surface.dirty = true;
    markDirty();
}

fn dockLauncherClose() void {
    if (launcher_surface.layer_surface) |ls| {
        c.zwlr_layer_surface_v1_destroy(ls);
        launcher_surface.layer_surface = null;
    }
    launcher_surface.dirty = false;
    markDirty();
}

fn renderLauncher() void {
    if (!dock_launcher.launcher_open) return;
    launcher_surface.width = panel_surface.width;
    ensureBuffer(&launcher_surface);
    const cr = launcher_surface.cairo_cr orelse return;
    const w = launcher_surface.width;
    const h = launcher_surface.height;

    // Clear with transparency.
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_CLEAR);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    dock_launcher.draw(cr, w, h, pointer_x, pointer_y);
}

var cal_prev_rect: modal_mod.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
var cal_next_rect: modal_mod.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
var cal_today_rect: modal_mod.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

fn daysInMonth(year: i32, month: i32) i32 {
    return switch (month) {
        0, 2, 4, 6, 7, 9, 11 => 31,
        3, 5, 8, 10 => 30,
        1 => if ((@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0)) 29 else 28,
        else => 31,
    };
}

const month_names = [_][]const u8{
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
};

fn renderCalendar(cr: *c.cairo_t, card: modal_mod.Rect) void {
    const t = &theme.current;
    
    // Header (Month Year)
    var buf: [64]u8 = undefined;
    const header_text = std.fmt.bufPrintZ(&buf, "{s} {d}", .{ month_names[@intCast(cal_month)], cal_year }) catch return;
    
    const header_y = card.y + MODAL_PAD + 40; // Below title
    
    _ = panel_mod.widgetText(cr, header_text, card.x + MODAL_PAD, header_y, "Inter Bold 18", 1.0, 1.0, 1.0);
    
    // Draw buttons
    const btn_w = 30;
    const btn_h = 24;
    const btn_y = header_y - 16;
    
    cal_today_rect = .{ .x = card.x + card.w - MODAL_PAD - 50, .y = btn_y, .w = 50, .h = btn_h };
    cal_next_rect = .{ .x = cal_today_rect.x - btn_w - 10, .y = btn_y, .w = btn_w, .h = btn_h };
    cal_prev_rect = .{ .x = cal_next_rect.x - btn_w - 10, .y = btn_y, .w = btn_w, .h = btn_h };
    
    c.cairo_set_source_rgba(cr, 1, 1, 1, 0.1);
    roundedRect(cr, @floatFromInt(cal_prev_rect.x), @floatFromInt(cal_prev_rect.y), @floatFromInt(cal_prev_rect.w), @floatFromInt(cal_prev_rect.h), 4);
    c.cairo_fill(cr);
    _ = panel_mod.widgetText(cr, "<", cal_prev_rect.x + 10, cal_prev_rect.y + 16, "Inter Bold 14", 1, 1, 1);
    
    c.cairo_set_source_rgba(cr, 1, 1, 1, 0.1);
    roundedRect(cr, @floatFromInt(cal_next_rect.x), @floatFromInt(cal_next_rect.y), @floatFromInt(cal_next_rect.w), @floatFromInt(cal_next_rect.h), 4);
    c.cairo_fill(cr);
    _ = panel_mod.widgetText(cr, ">", cal_next_rect.x + 10, cal_next_rect.y + 16, "Inter Bold 14", 1, 1, 1);

    c.cairo_set_source_rgba(cr, t.accent_color[0], t.accent_color[1], t.accent_color[2], 0.3);
    roundedRect(cr, @floatFromInt(cal_today_rect.x), @floatFromInt(cal_today_rect.y), @floatFromInt(cal_today_rect.w), @floatFromInt(cal_today_rect.h), 4);
    c.cairo_fill(cr);
    _ = panel_mod.widgetText(cr, "Today", cal_today_rect.x + 8, cal_today_rect.y + 16, "Inter 12", 1, 1, 1);
    
    // Draw days of week header
    const days = [_][:0]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    const grid_y = header_y + 36;
    const cell_w = @divTrunc(card.w - MODAL_PAD * 2, 7);
    const cell_h = 32;
    
    for (days, 0..) |d, i| {
        _ = panel_mod.widgetText(cr, d.ptr, card.x + MODAL_PAD + @as(i32, @intCast(i)) * cell_w + 12, grid_y, "Inter Bold 12", 0.6, 0.6, 0.6);
    }
    
    // Find first day of week
    var tm: c.tm = std.mem.zeroes(c.tm);
    tm.tm_year = cal_year - 1900;
    tm.tm_mon = cal_month;
    tm.tm_mday = 1;
    _ = c.mktime(&tm);
    const start_dow = tm.tm_wday;
    const total_days = daysInMonth(cal_year, cal_month);
    
    var cur_x = card.x + MODAL_PAD + start_dow * cell_w;
    var cur_y = grid_y + 30;
    
    for (1..@as(usize, @intCast(total_days)) + 1) |day| {
        if (cal_year == cal_today_year and cal_month == cal_today_month and day == cal_today_day) {
            c.cairo_set_source_rgba(cr, t.accent_color[0], t.accent_color[1], t.accent_color[2], 0.5);
            roundedRect(cr, @floatFromInt(cur_x + 8), @floatFromInt(cur_y - 14), 24, 24, 12);
            c.cairo_fill(cr);
        }
        
        var d_buf: [16]u8 = undefined;
        const d_text = std.fmt.bufPrintZ(&d_buf, "{d}", .{ day }) catch return;
        _ = panel_mod.widgetText(cr, d_text, cur_x + 14, cur_y, "Inter 14", 1.0, 1.0, 1.0);
        
        cur_x += cell_w;
        if (cur_x >= card.x + MODAL_PAD + 7 * cell_w) {
            cur_x = card.x + MODAL_PAD;
            cur_y += cell_h;
        }
    }
}

// Toggle the modal from a dock/keyboard action. If already open, close it.
fn toggleModal(title: []const u8) void {
    if (modal_open) {
        modalClose();
    } else {
        modalOpen(title);
    }
}

fn renderModal() void {
    if (!modal_open) return;
    const out_w = panel_surface.width;
    const out_h = panel_surface.height + dock_surface.height;
    modal_surface.width = out_w;
    modal_surface.height = out_h;
    ensureBuffer(&modal_surface);
    const cr = modal_surface.cairo_cr orelse return;
    const w = modal_surface.width;
    const h = modal_surface.height;
    const t = &theme.current;

    // Dark translucent backdrop.
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.55);
    c.cairo_paint(cr);

    // Centered content card.
    const card = modal_mod.layoutCard(w, h, MODAL_W, MODAL_H);
    modal_state.card_x = card.x;
    modal_state.card_y = card.y;
    modal_state.card_w = card.w;
    modal_state.card_h = card.h;

    // Card background (premium translucent slate).
    c.cairo_set_source_rgba(cr, 0.10, 0.10, 0.14, 0.96);
    roundedRect(cr, @floatFromInt(card.x), @floatFromInt(card.y), @floatFromInt(card.w), @floatFromInt(card.h), 14.0);
    c.cairo_fill(cr);

    // Subtle border glow.
    c.cairo_set_source_rgba(cr, t.accent_color[0], t.accent_color[1], t.accent_color[2], 0.35);
    c.cairo_set_line_width(cr, 1.5);
    roundedRect(cr, @floatFromInt(card.x), @floatFromInt(card.y), @floatFromInt(card.w), @floatFromInt(card.h), 14.0);
    c.cairo_stroke(cr);

    // Title.
    if (modal_title_len > 0) {
        _ = panel_mod.widgetText(cr, @ptrCast(&modal_title), card.x + MODAL_PAD, card.y + MODAL_PAD + 18, "Inter Bold 16", t.text_color[0], t.text_color[1], t.text_color[2]);
    }

    // Close (×) button, top-right of the card.
    const card_rect = modal_mod.Rect{ .x = card.x, .y = card.y, .w = card.w, .h = card.h };
    const cl = modal_mod.layoutClose(card_rect, 14);
    modal_state.close_x = cl.x;
    modal_state.close_y = cl.y;
    modal_state.close_r = cl.r;
    if (modal_state.close_hover) {
        c.cairo_set_source_rgba(cr, t.danger_color[0], t.danger_color[1], t.danger_color[2], 0.25);
    } else {
        c.cairo_set_source_rgba(cr, 1, 1, 1, 0.10);
    }
    roundedRect(cr, @floatFromInt(cl.x), @floatFromInt(cl.y), @floatFromInt(cl.r * 2), @floatFromInt(cl.r * 2), 8.0);
    c.cairo_fill(cr);
    // The × glyph.
    c.cairo_set_source_rgba(cr, t.text_color[0], t.text_color[1], t.text_color[2], 0.9);
    c.cairo_set_line_width(cr, 2.0);
    const cx = @as(f64, @floatFromInt(cl.x + cl.r));
    const cy = @as(f64, @floatFromInt(cl.y + cl.r));
    const d = 6.0;
    c.cairo_move_to(cr, cx - d, cy - d);
    c.cairo_line_to(cr, cx + d, cy + d);
    c.cairo_move_to(cr, cx + d, cy - d);
    c.cairo_line_to(cr, cx - d, cy + d);
    c.cairo_stroke(cr);

    if (std.mem.eql(u8, modal_title[0..modal_title_len], "Calendar")) {
        renderCalendar(cr, card_rect);
    } else {
        // Demo body text (replace with feature-specific content later).
        _ = panel_mod.widgetText(cr, "Global modal — dark backdrop + centered card.", card.x + MODAL_PAD, card.y + MODAL_PAD + 52, "Inter 12", t.text_dim_color[0], t.text_dim_color[1], t.text_dim_color[2]);
        _ = panel_mod.widgetText(cr, "Press Esc, click the backdrop, or × to dismiss.", card.x + MODAL_PAD, card.y + MODAL_PAD + 74, "Inter 12", t.text_dim_color[0], t.text_dim_color[1], t.text_dim_color[2]);
    }
}

fn drawDockTooltip(cr: *c.cairo_t, surf_w: i32, surf_h: i32) void {
    if (!pointer_on_dock) return;
    if (dock_hover_idx < 0) return;

    // Resolve tooltip text: running windows use toplevel title, pinned apps
    // (1000+g) use the pinned name from persistent_order.
    var title: []const u8 = "";
    if (dock_hover_idx < toplevel_count) {
        title = std.mem.sliceTo(&toplevels[@intCast(dock_hover_idx)].title, 0);
    } else if (dock_hover_idx >= 1000) {
        const pin_idx = @as(usize, @intCast(dock_hover_idx - 1000));
        if (pin_idx < dock_mod.persistent_count) {
            title = std.mem.sliceTo(&dock_mod.persistent_order[pin_idx], 0);
        }
    }
    if (title.len == 0) return;

    const pad: i32 = 8;
    const tw: i32 = @as(i32, @intCast(title.len)) * 7 + pad * 2;
    const th: i32 = 22;
    var bx: i32 = pointer_x -| @divTrunc(tw, 2);
    if (bx < 0) bx = 0;
    if (bx + tw > surf_w) bx = surf_w - tw;
    const by: i32 = surf_h - th - 4;

    c.cairo_set_source_rgba(cr, 0.08, 0.08, 0.1, 0.95);
    c.cairo_rectangle(cr, @floatFromInt(bx), @floatFromInt(by), @floatFromInt(tw), @floatFromInt(th));
    c.cairo_fill(cr);
    _ = panel_mod.widgetText(cr, @ptrCast(title.ptr), bx + pad, by + th, "Sans 10", 0.9, 0.9, 0.9);
}

fn submitSurface(ss: *SurfaceState) void {
    if (!ss.dirty) return;
    ss.dirty = false;
    if (ss.buffer == null or ss.surface == null) return;
    c.wl_surface_attach(ss.surface, ss.buffer, 0, 0);
    const r = ss.dirty_region;
    if (r.active) {
        c.wl_surface_damage_buffer(ss.surface, r.x, r.y, r.w, r.h);
    } else {
        c.wl_surface_damage_buffer(ss.surface, 0, 0, ss.buf_width, ss.buf_height);
    }
    ss.dirty_region.reset();
    if (ss.frame_cb) |cb| c.wl_callback_destroy(cb);
    ss.frame_cb = c.wl_surface_frame(ss.surface);
    if (ss.frame_cb) |cb| {
        _ = c.wl_callback_add_listener(cb, &frame_listener, null);
    }
    c.wl_surface_commit(ss.surface);
}

// ==== MAIN ====

pub fn main() !void {
    var render_out: ?[]const u8 = null;
    
    if (c.getenv("RENDER_TO_PNG")) |env_ptr| {
        render_out = std.mem.span(env_ptr);
    }

    if (render_out) |out_path| {
        dock_surface.width = 800;
        dock_surface.height = 100;
        dock_surface.scale = 1;
        dock_mod.initOrder();
        
        const cairo_surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 800, 100);
        const cr = c.cairo_create(cairo_surface);
        
        // Fill background with transparent
        c.cairo_set_source_rgba(cr, 0, 0, 0, 0);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        dock_mod.draw(
            cr,
            800,
            100,
            &toplevels,
            0,
            -1,
            -1.0,
        );
        
        c.cairo_surface_flush(cairo_surface);
        
        var zpath: [4096]u8 = undefined;
        @memcpy(zpath[0..out_path.len], out_path);
        zpath[out_path.len] = 0;
        
        _ = c.cairo_surface_write_to_png(cairo_surface, @ptrCast(&zpath));
        c.cairo_destroy(cr);
        c.cairo_surface_destroy(cairo_surface);
        std.log.info("Headless rendering complete. Output: {s}", .{out_path});
        return;
    }

    display = c.wl_display_connect(null) orelse {
        std.log.err("zigshell-cairo-pango: failed to connect to Wayland display", .{});
        return error.WaylandConnectFailed;
    };

    _ = c.signal(c.SIGHUP, onSighup);
    if (c.getenv("ZIGSHELL_CONFIG")) |p| {
        config_path = std.mem.sliceTo(p, 0);
    }

    registry = c.wl_display_get_registry(display);
    _ = c.wl_registry_add_listener(registry, &registry_listener, null);
    _ = c.wl_display_roundtrip(display);
    _ = c.wl_display_roundtrip(display);

    if (compositor == null or shm == null or layer_shell == null) {
        std.log.err("zigshell-cairo-pango: missing required Wayland globals", .{});
        return error.MissingGlobals;
    }

    if (toplevel_manager != null) {
        _ = c.wl_display_roundtrip(display);
        std.log.info("zigshell-cairo-pango: toplevel management enabled", .{});
    }

    if (seat != null) {
        _ = c.wl_display_roundtrip(display);
    }

    // Load widgets: compact mode if OCWS_PANEL_COMPACT=1, else full default
    const use_compact = if (c.getenv("OCWS_PANEL_COMPACT")) |v| blk: {
        const s = std.mem.span(v);
        break :blk std.mem.eql(u8, s, "1");
    } else false;
    const count = if (use_compact)
        panel_mod.widgetCreateCompact(&widgets)
    else
        panel_mod.widgetCreateDefault(&widgets);
    widget_count = count;

    // Ensure a concrete config path so the file-backed config (and SIGHUP
    // reload triggered by the GTK settings app) always works.
    if (config_path == null) config_path = config_manager.resolveConfigPath();

    // Load persisted config (panel/dock/widgets/pins) if a path is set.
    if (config_path) |p| {
        _ = pcfg.Config.load(std.heap.page_allocator, p, .{ .widgets = &widgets, .count = &widget_count });
        config_manager.applyConfigToRuntime();
        std.log.info("zigshell-cairo-pango: loaded config from {s}", .{p});
    }

    // Create panel surface (TOP)
    panel_surface.surface = c.wl_compositor_create_surface(compositor) orelse {
        std.log.err("zigshell-cairo-pango: wl_compositor_create_surface failed for panel", .{});
        return error.SurfaceCreateFailed;
    };
    _ = c.wl_surface_add_listener(panel_surface.surface, &surface_listener, null);
    panel_surface.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
        layer_shell, panel_surface.surface, null,
        c.ZWLR_LAYER_SHELL_V1_LAYER_TOP, "zigshell-cairo-pango-panel",
    ) orelse {
        std.log.err("zigshell-cairo-pango: get_layer_surface failed for panel", .{});
        return error.LayerSurfaceCreateFailed;
    };
    _ = c.zwlr_layer_surface_v1_add_listener(panel_surface.layer_surface, &panel_layer_listener, null);

    const panel_anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    c.zwlr_layer_surface_v1_set_anchor(panel_surface.layer_surface, panel_anchor);
    c.zwlr_layer_surface_v1_set_size(panel_surface.layer_surface, 0, @intCast(panel_height));
    c.zwlr_layer_surface_v1_set_exclusive_zone(panel_surface.layer_surface, @intCast(panel_height));
    // The panel/dock is an indicator+launcher bar with no in-process text
    // entry, so it must NOT grab keyboard focus. Using interactivity 1 here
    // meant the panel always held keyboard focus and discarded every key
    // press — i.e. "keyboard can't type anything". Keep it NONE (0); the
    // launcher spawns external tools (fuzzel) that manage their own focus.
    c.zwlr_layer_surface_v1_set_keyboard_interactivity(panel_surface.layer_surface, 0);
    c.wl_surface_commit(panel_surface.surface);

    // Create dock surface (BOTTOM)
    dock_surface.surface = c.wl_compositor_create_surface(compositor) orelse {
        std.log.err("zigshell-cairo-pango: wl_compositor_create_surface failed for dock", .{});
        return error.SurfaceCreateFailed;
    };
    _ = c.wl_surface_add_listener(dock_surface.surface, &surface_listener, null);
    dock_surface.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
        layer_shell, dock_surface.surface, null,
        c.ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM, "zigshell-cairo-pango-dock",
    ) orelse {
        std.log.err("zigshell-cairo-pango: get_layer_surface failed for dock", .{});
        return error.LayerSurfaceCreateFailed;
    };
    _ = c.zwlr_layer_surface_v1_add_listener(dock_surface.layer_surface, &dock_layer_listener, null);

    const dock_anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    c.zwlr_layer_surface_v1_set_anchor(dock_surface.layer_surface, dock_anchor);
    c.zwlr_layer_surface_v1_set_size(dock_surface.layer_surface, 0, DOCK_HEIGHT);
    c.zwlr_layer_surface_v1_set_exclusive_zone(dock_surface.layer_surface, DOCK_HEIGHT);
    c.zwlr_layer_surface_v1_set_keyboard_interactivity(dock_surface.layer_surface, 0);
    c.wl_surface_commit(dock_surface.surface);

    // The app-launcher layer surface is created lazily (on first open) by
    // toggleLauncher(). Creating/committing it at init with a hidden state is
    // error-prone under wlr-layer-shell (a 0-height commit is a protocol
    // error), so we defer it entirely until the user opens the launcher.

    // Wait for initial configure
    var ret: i32 = 0;
    while (panel_surface.width == 0 and ret >= 0 and c.wl_display_get_error(display) == 0) {
        ret = c.wl_display_dispatch(display);
    }

    if (c.wl_display_get_error(display) != 0) {
        std.log.err("zigshell-cairo-pango: Wayland protocol error during init (code {d}, errno {d}); aborting", .{ c.wl_display_get_error(display), errno() });
        return error.WaylandProtocolError;
    }

    if (panel_surface.width == 0) {
        std.log.warn("zigshell-cairo-pango: no configure event received, using fallback width", .{});
        panel_surface.width = if (output_count > 0) outputs[0].w else 1920;
    }
    if (panel_surface.height == 0) panel_surface.height = panel_height;
    if (dock_surface.width == 0) dock_surface.width = panel_surface.width;
    if (dock_surface.height == 0) dock_surface.height = DOCK_HEIGHT;

    std.log.info("zigshell-cairo-pango: panel ({d}x{d}) dock ({d}x{d})", .{
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

    markDirty();

    const wl_fd = c.wl_display_get_fd(display);
    var pfds: [2]c.struct_pollfd = undefined;

    // Main event loop
    while (running) {
        if (reload_config) {
            reload_config = false;
            reloadWidgets();
        }
        // Animation step
        var any_animating = false;
        for (0..@intCast(@max(0, toplevel_count))) |i| {
            const target: f64 = if (dock_hover_idx == @as(i32, @intCast(i))) 1.0 else 0.0;
            const diff = target - toplevels[i].hover_anim;
            if (@abs(diff) > 0.01) {
                toplevels[i].hover_anim += diff * 0.2; // Lerp factor
                any_animating = true;
                markDirty();
            } else {
                toplevels[i].hover_anim = target;
            }
        }

        // Repaint each surface only when its own dirty flag is set. Surfaces
        // own their dirty bit, so (e.g.) hovering the dock never repaints the
        // panel — this is what previously made the panel blink.
        if (panel_surface.dirty) {
            renderPanel();
        }
        if (dock_surface.dirty) {
            renderDock();
        }
        if (modal_surface.dirty) {
            renderModal();
        }
        if (launcher_surface.dirty) {
            renderLauncher();
        }
        submitSurface(&panel_surface);
        submitSurface(&dock_surface);
        submitSurface(&modal_surface);
        submitSurface(&launcher_surface);

        if (c.wl_display_flush(display) < 0) { running = false; continue; }

        pfds[0].fd = wl_fd;
        pfds[0].events = c.POLLIN;
        pfds[1].fd = timer_fd;
        pfds[1].events = c.POLLIN;

        const poll_ret = c.poll(&pfds, 2, if (any_animating) 16 else 3000);
        if (poll_ret > 0) {
            if ((pfds[0].revents & (c.POLLERR | c.POLLHUP)) != 0) {
                running = false;
            } else if ((pfds[0].revents & c.POLLIN) != 0) {
                if (c.wl_display_dispatch(display) < 0) running = false;
            }
            if ((pfds[1].revents & c.POLLIN) != 0) {
                var exp: u64 = 0;
                _ = c.read(timer_fd, &exp, @sizeOf(u64));
                panel_mod.widgetListUpdate(widgets[0..@intCast(@max(0, widget_count))]);
                markDirty();
            }
        } else {
            _ = c.wl_display_dispatch_pending(display);
        }
    }

    // Cleanup
    if (keyboard_keymap_mapped) |m| {
        _ = c.munmap(@ptrCast(m), keyboard_keymap_size);
        keyboard_keymap_mapped = null;
    }
    if (keyboard_keymap_fd >= 0) {
        _ = c.close(keyboard_keymap_fd);
        keyboard_keymap_fd = -1;
    }
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

    if (launcher_surface.buffer) |b| c.wl_buffer_destroy(b);
    if (launcher_surface.cairo_cr) |cr| c.cairo_destroy(cr);
    if (launcher_surface.cairo_surface) |s| c.cairo_surface_destroy(s);
    if (launcher_surface.shm_data) |d| _ = c.munmap(d, launcher_surface.buf_size);
    if (launcher_surface.frame_cb) |cb| c.wl_callback_destroy(cb);
    if (launcher_surface.layer_surface) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (launcher_surface.surface) |s| c.wl_surface_destroy(s);

    if (modal_surface.buffer) |b| c.wl_buffer_destroy(b);
    if (modal_surface.cairo_cr) |cr| c.cairo_destroy(cr);
    if (modal_surface.cairo_surface) |s| c.cairo_surface_destroy(s);
    if (modal_surface.shm_data) |d| _ = c.munmap(d, modal_surface.buf_size);
    if (modal_surface.frame_cb) |cb| c.wl_callback_destroy(cb);
    if (modal_surface.layer_surface) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (modal_surface.surface) |s| c.wl_surface_destroy(s);

    icon.clearCache();
    if (display) |d| _ = c.wl_display_disconnect(d);

    std.log.info("zigshell-cairo-pango: exiting", .{});
}
comptime {
    _ = @import("dock.zig");
    _ = @import("icon.zig");
    _ = @import("panel.zig");
    _ = @import("theme.zig");
    _ = @import("modal.zig");
    _ = @import("app_launcher.zig");
    _ = @import("ocws_apps.zig");
}
