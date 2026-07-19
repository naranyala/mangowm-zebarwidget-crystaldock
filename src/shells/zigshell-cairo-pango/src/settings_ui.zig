const std = @import("std");
const c = @import("c.zig").c;
const panel_mod = @import("panel.zig");
const dock_mod = @import("dock.zig");
const icon = @import("icon.zig");
const main = @import("main_shell.zig");
const config_mgr = @import("config_manager.zig");

pub fn handleSettingsClick(x: i32, y: i32, button: u32) bool {
    const r = main.settingsRect();
    if (x < r.x or x > r.x + r.w or y < r.y or y > r.y + r.h) {
        main.settings_open = false;
        main.applyPanelSurfaceHeight();
        return false;
    }

    // Tab bar
    const tab0_x = r.x + 16;
    const tab1_x = r.x + 16 + @divTrunc(r.w - 32, 2) + 8;
    const tab_w = @divTrunc(r.w - 32, 2);
    if (y >= r.y + 8 + 22 and y < r.y + 8 + 22 + main.SET_TAB_H) {
        if (x >= tab0_x and x < tab0_x + tab_w) main.settings_tab = 0;
        if (x >= tab1_x and x < tab1_x + tab_w) main.settings_tab = 1;
        main.settings_add_menu = false;
        main.settings_drag_idx = -1;
        main.markDirty();
        return true;
    }

    if (main.settings_tab == 0) {
        handleWidgetListClick(x, y, button);
    } else {
        handleDockClick(x, y, button);
    }
    return true;
}

pub fn handleWidgetListClick(x: i32, y: i32, button: u32) void {
    _ = button;
    const r = main.settingsRect();
    const list_x = r.x + 16;
    const list_w = r.w - 32;

    // "Add widget" button at the bottom of the card.
    const add_btn_y = r.y + r.h - 44;
    if (y >= add_btn_y and y < add_btn_y + 32) {
        main.settings_add_menu = !main.settings_add_menu;
        main.settings_drag_idx = -1;
        main.markDirty();
        return;
    }

    if (main.settings_add_menu) {
        // Click inside the add menu grid.
        const menu_y = add_btn_y - (@as(i32, @intCast((panel_mod.AllWidgetTypes.len + 2) / 3)) * 32 + 10) - 8;
        if (y >= menu_y) {
            const col = @divTrunc(x - list_x, @divTrunc(list_w, 3));
            const row = @divTrunc(y - menu_y, 32);
            const idx = row * 3 + col;
            if (idx >= 0 and idx < panel_mod.AllWidgetTypes.len and x >= list_x and x < list_x + list_w) {
                _ = panel_mod.widgetListAdd(widgetListRef(), panel_mod.AllWidgetTypes[@as(usize, @intCast(idx))]);
                config_mgr.syncConfigFromRuntime();
                main.config_dirty = true;
                config_mgr.saveConfig();
            }
            main.settings_add_menu = false;
            main.markDirty();
            return;
        }
        main.settings_add_menu = false;
    }

    // Rows: [drag handle] [name] [eye: show/hide] [L/R side] [x: delete]
    const first = main.settings_scroll;
    var row: i32 = 0;
    while (first + row < main.widget_count) : (row += 1) {
        const iy = main.SET_LIST_Y + row * main.SET_ROW_H;
        if (iy > r.y + r.h - 44) break;
        if (y < iy or y > iy + main.SET_ROW_H) continue;
        const idx = first + row;
        const ui = widgetListRef();
        const eye_x = list_x + list_w - 92;
        const side_x = list_x + list_w - 48;
        const del_x = list_x + list_w - 4;
        // Delete
        if (x >= del_x and x < del_x + 36) {
            _ = panel_mod.widgetListRemoveAt(ui, @intCast(idx));
            config_mgr.syncConfigFromRuntime();
            main.config_dirty = true;
            config_mgr.saveConfig();
            main.markDirty();
            return;
        }
        // Visibility toggle (eye)
        if (x >= eye_x and x < eye_x + 36) {
            _ = panel_mod.widgetListToggleHidden(ui, @intCast(idx));
            config_mgr.syncConfigFromRuntime();
            main.config_dirty = true;
            config_mgr.saveConfig();
            main.markDirty();
            return;
        }
        // Side toggle (L <-> R)
        if (x >= side_x and x < side_x + 36) {
            main.widgets[@intCast(idx)].side = if (main.widgets[@intCast(idx)].side == 0) 1 else 0;
            config_mgr.syncConfigFromRuntime();
            main.config_dirty = true;
            config_mgr.saveConfig();
            main.markDirty();
            return;
        }
        // Press anywhere else on the row starts a drag-to-reorder.
        main.settings_drag_idx = idx;
        main.markDirty();
        return;
    }
}

pub fn widgetListRef() *panel_mod.WidgetList {
    main.g_widget_list = .{
        .widgets = &main.widgets,
        .count = &main.widget_count,
    };
    return &main.g_widget_list;
}

pub fn handleDockClick(x: i32, y: i32, button: u32) void {
    const r = main.settingsRect();
    const list_x = r.x + 16;
    const list_w = r.w - 32;

    // Autohide toggle row.
    const ah_y = main.SET_LIST_Y;
    if (y >= ah_y and y < ah_y + main.SET_ROW_H) {
        main.setDockAutohide(!main.autohide_dock);
        config_mgr.syncConfigFromRuntime();
        main.config_dirty = true;
        config_mgr.saveConfig();
        main.markDirty();
        return;
    }

    // Font size increment/decrement row (applies to the whole system).
    const fs_y = ah_y + main.SET_ROW_H + 10;
    if (y >= fs_y and y < fs_y + main.SET_ROW_H) {
        const btn_w: i32 = 36;
        const val_w: i32 = 56;
        const total = btn_w * 2 + val_w;
        const bx = list_x + list_w - total;
        if (x >= bx and x < bx + btn_w) {
            main.changeFontScale(-main.FONT_SCALE_STEP);
            return;
        }
        if (x >= bx + btn_w + val_w and x < bx + btn_w + val_w + btn_w) {
            main.changeFontScale(main.FONT_SCALE_STEP);
            return;
        }
        return;
    }

    // Icon size segmented control (small/med/large).
    const is_y = fs_y + main.SET_ROW_H + 10;
    if (y >= is_y and y < is_y + main.SET_ROW_H) {
        const seg = @divTrunc(x - list_x, @divTrunc(list_w, 3));
        const sizes = [_]i32{ 22, 28, 36 };
        if (seg >= 0 and seg < 3 and x >= list_x and x < list_x + list_w) {
            dock_mod.DOCK_ICON_SIZE = sizes[@intCast(seg)];
            icon.clearCache();
            config_mgr.syncConfigFromRuntime();
            main.config_dirty = true;
            config_mgr.saveConfig();
            main.markDirty();
            return;
        }
    }

    // Pinned-app rows: [name] [x to unpin]
    const pins_start = is_y + main.SET_ROW_H + 14 + main.SET_ROW_H;
    dock_mod.initOrder();
    var row: i32 = 0;
    while (row * main.SET_ROW_H + pins_start < r.y + r.h - 8) : (row += 1) {
        const idx = row;
        if (idx >= dock_mod.persistent_count) break;
        const iy = pins_start + row * main.SET_ROW_H;
        if (y < iy or y > iy + main.SET_ROW_H) continue;
        const del_x = list_x + list_w - 4;
        if (x >= del_x and x < del_x + 36) {
            _ = dock_mod.unpinAt(@intCast(idx));
            config_mgr.syncConfigFromRuntime();
            main.config_dirty = true;
            config_mgr.saveConfig();
            main.markDirty();
            return;
        }
        // Drag to reorder: clicking a pinned row + drag handled in pointerMotion.
        if (button == 272) {
            main.settings_drag_idx = idx;
        }
        break;
    }
}

pub fn drawSettingsMenu(cr: *c.cairo_t, _: i32, _: i32) void {
    const r = main.settingsRect();

    // Premium Card background with translucent dark slate
    c.cairo_set_source_rgba(cr, 0.05, 0.05, 0.07, 0.92);
    main.roundedRect(cr, @floatFromInt(r.x), @floatFromInt(r.y), @floatFromInt(r.w), @floatFromInt(r.h), 14.0);
    c.cairo_fill(cr);

    // Soft inner shadow tint
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.25);
    main.roundedRect(cr, @floatFromInt(r.x), @floatFromInt(r.y + r.h - 28), @floatFromInt(r.w), 28.0, 14.0);
    c.cairo_fill(cr);

    // Subtle border glow
    c.cairo_set_source_rgba(cr, 0.3, 0.5, 1.0, 0.22);
    c.cairo_set_line_width(cr, 1.5);
    main.roundedRect(cr, @floatFromInt(r.x), @floatFromInt(r.y), @floatFromInt(r.w), @floatFromInt(r.h), 14.0);
    c.cairo_stroke(cr);

    // Title
    _ = panel_mod.widgetText(cr, "Panel Settings", r.x + 16, r.y + 26, "Inter Bold 14", 0.98, 0.98, 1.0);

    // Tab bar
    const tab_w = @divTrunc(r.w - 32, 2);
    drawTab(cr, r.x + 16, r.y + 8 + 22, tab_w, main.SET_TAB_H, "Widgets", main.settings_tab == 0);
    drawTab(cr, r.x + 16 + tab_w + 8, r.y + 8 + 22, tab_w, main.SET_TAB_H, "Dock", main.settings_tab == 1);

    if (main.settings_tab == 0) {
        drawWidgetManager(cr, r);
    } else {
        drawDockManager(cr, r);
    }
}

pub fn drawTab(cr: *c.cairo_t, x: i32, y: i32, w: i32, h: i32, label: []const u8, active: bool) void {
    main.roundedRect(cr, @floatFromInt(x), @floatFromInt(y), @floatFromInt(w), @floatFromInt(h), 9.0);
    if (active) {
        const pat = c.cairo_pattern_create_linear(@floatFromInt(x), @floatFromInt(y), @floatFromInt(x + w), @floatFromInt(y + h));
        c.cairo_pattern_add_color_stop_rgba(pat, 0.0, 0.15, 0.45, 0.95, 1.0);
        c.cairo_pattern_add_color_stop_rgba(pat, 1.0, 0.25, 0.25, 0.85, 1.0);
        c.cairo_set_source(cr, pat);
        c.cairo_fill(cr);
        c.cairo_pattern_destroy(pat);
    } else {
        c.cairo_set_source_rgba(cr, 1, 1, 1, 0.05);
        c.cairo_fill(cr);
    }
    _ = panel_mod.widgetText(cr, @ptrCast(label.ptr), x + 12, y + h - 10, "Inter Bold 12", 0.95, 0.95, 0.98);
}

pub fn drawWidgetManager(cr: *c.cairo_t, r: main.SettingsRect) void {
    const list_x = r.x + 16;
    const list_w = r.w - 32;
    const first = main.settings_scroll;
    var row: i32 = 0;
    while (first + row < main.widget_count) : (row += 1) {
        const iy = main.SET_LIST_Y + 4 + row * main.SET_ROW_H;
        if (iy > r.y + r.h - 44) break;
        const idx = first + row;
        const wgt = main.widgets[@intCast(idx)];
        const wy = iy + main.SET_ROW_H;
        const hidden = wgt.hidden;
        // Row background (dimmed when hidden)
        main.roundedRect(cr, @floatFromInt(list_x), @floatFromInt(iy), @floatFromInt(list_w), @floatFromInt(main.SET_ROW_H - 6), 8.0);
        if (hidden) {
            c.cairo_set_source_rgba(cr, 1, 1, 1, 0.02);
        } else if (main.settings_drag_idx == idx) {
            c.cairo_set_source_rgba(cr, 0.2, 0.6, 0.9, 0.16);
        } else {
            c.cairo_set_source_rgba(cr, 1, 1, 1, 0.05);
        }
        c.cairo_fill(cr);
        // Drag handle (left)
        _ = panel_mod.widgetText(cr, "⠿", list_x + 8, wy - 8, "Inter 14", 0.35, 0.35, 0.42);
        // Name (struck-through when hidden)
        const name = panel_mod.widgetTypeName(wgt.wtype);
        const name_a: f64 = if (hidden) 0.42 else 0.94;
        _ = panel_mod.widgetText(cr, @ptrCast(name.ptr), list_x + 30, wy - 8, "Inter 12", name_a, name_a, name_a + 0.03);
        if (hidden) {
            const tw = panel_mod.widgetTextWidth(cr, @ptrCast(name.ptr), "Inter 12");
            c.cairo_set_source_rgba(cr, 0.6, 0.6, 0.65, 0.5);
            c.cairo_set_line_width(cr, 1);
            c.cairo_move_to(cr, @floatFromInt(list_x + 30), @floatFromInt(wy - 13));
            c.cairo_line_to(cr, @floatFromInt(list_x + 30 + tw), @floatFromInt(wy - 13));
            c.cairo_stroke(cr);
        }
        // Side badge ("L"/"R")
        _ = panel_mod.widgetText(cr, if (wgt.side == 1) "R" else "L", list_x + list_w - 116, wy - 8, "Inter 11", 0.6, 0.7, 0.9);
        // Eye (visibility), Side (L/R) toggle, Delete
        drawListBtn(cr, list_x + list_w - 92, iy + 4, if (hidden) "◌" else "◉", false);
        drawListBtn(cr, list_x + list_w - 48, iy + 4, "⇄", false);
        drawListBtn(cr, list_x + list_w - 4, iy + 4, "✕", true);
    }

    // Ghost drop indicator line during drag-reorder
    if (main.settings_drag_idx >= 0 and main.settings_drag_idx < main.widget_count) {
        const drop_y = main.pointer_y - 2;
        if (drop_y > main.SET_LIST_Y and drop_y < r.y + r.h - 44) {
            c.cairo_set_source_rgba(cr, 0.3, 0.6, 1.0, 0.6);
            c.cairo_set_line_width(cr, 2.0);
            c.cairo_move_to(cr, @floatFromInt(list_x + 4), @floatFromInt(drop_y));
            c.cairo_line_to(cr, @floatFromInt(list_x + list_w - 4), @floatFromInt(drop_y));
            c.cairo_stroke(cr);
        }
    }

    // Add widget button
    const add_y = r.y + r.h - 44;
    main.roundedRect(cr, @floatFromInt(list_x), @floatFromInt(add_y), @floatFromInt(list_w), 32.0, 9.0);
    const pat = c.cairo_pattern_create_linear(@floatFromInt(list_x), @floatFromInt(add_y), @floatFromInt(list_x + list_w), @floatFromInt(add_y));
    c.cairo_pattern_add_color_stop_rgba(pat, 0.0, 0.2, 0.7, 0.5, 0.9);
    c.cairo_pattern_add_color_stop_rgba(pat, 1.0, 0.1, 0.8, 0.6, 0.9);
    c.cairo_set_source(cr, pat);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(pat);
    _ = panel_mod.widgetText(cr, "+ Add Widget", list_x + 14, add_y + 24, "Inter Bold 12", 1, 1, 1);

    // Add menu grid (3 columns)
    if (main.settings_add_menu) {
        const cols: i32 = 3;
        const rows = (panel_mod.AllWidgetTypes.len + @as(usize, @intCast(cols)) - 1) / @as(usize, @intCast(cols));
        const menu_h = @as(i32, @intCast(rows)) * 32 + 10;
        const menu_y = add_y - menu_h - 8;
        main.roundedRect(cr, @floatFromInt(list_x), @floatFromInt(menu_y), @floatFromInt(list_w), @floatFromInt(menu_h), 12.0);
        c.cairo_set_source_rgba(cr, 0.08, 0.08, 0.11, 0.98);
        c.cairo_fill(cr);

        c.cairo_set_source_rgba(cr, 0.2, 0.4, 0.9, 0.3);
        c.cairo_set_line_width(cr, 1);
        main.roundedRect(cr, @floatFromInt(list_x), @floatFromInt(menu_y), @floatFromInt(list_w), @floatFromInt(menu_h), 12.0);
        c.cairo_stroke(cr);

        const cw = @divTrunc(list_w, cols);
        for (panel_mod.AllWidgetTypes, 0..) |wt, i| {
            const col = @mod(@as(i32, @intCast(i)), cols);
            const rrow = @divTrunc(@as(i32, @intCast(i)), cols);
            const gx = list_x + col * cw;
            const gy = menu_y + 5 + rrow * 32;
            _ = panel_mod.widgetText(cr, @ptrCast(panel_mod.widgetTypeName(wt).ptr), gx + 8, gy + 26, "Inter 11", 0.85, 0.85, 0.9);
        }
    }
}

pub fn drawDockManager(cr: *c.cairo_t, r: main.SettingsRect) void {
    const list_x = r.x + 16;
    const list_w = r.w - 32;

    // Autohide toggle
    const ah_y = main.SET_LIST_Y;
    drawToggleRow(cr, list_x, list_w, ah_y, "Auto-hide Dock", main.autohide_dock);

    // Font size increment/decrement (applies to the whole system).
    const fs_y = ah_y + main.SET_ROW_H + 10;
    drawFontScaleRow(cr, list_x, list_w, fs_y);

    // Icon size segmented control
    const is_y = fs_y + main.SET_ROW_H + 10;
    _ = panel_mod.widgetText(cr, "Icon Size", list_x + 2, is_y + main.SET_ROW_H - 8, "Inter 10", 0.7, 0.7, 0.78);
    const sizes = [_]struct { label: []const u8, val: i32 }{
        .{ .label = "S", .val = 22 },
        .{ .label = "M", .val = 28 },
        .{ .label = "L", .val = 36 },
    };
    const seg_w = @divTrunc(list_w, 3);
    for (sizes, 0..) |s, i| {
        const sx = list_x + @as(i32, @intCast(i)) * seg_w;
        const active = dock_mod.DOCK_ICON_SIZE == s.val;
        main.roundedRect(cr, @floatFromInt(sx + 3), @floatFromInt(is_y + 2), @floatFromInt(seg_w - 6), @floatFromInt(main.SET_ROW_H - 10), 7.0);
        if (active) {
            c.cairo_set_source_rgb(cr, 0.2, 0.45, 0.95);
        } else {
            c.cairo_set_source_rgba(cr, 1, 1, 1, 0.05);
        }
        c.cairo_fill(cr);
        _ = panel_mod.widgetText(cr, @ptrCast(s.label.ptr), sx + @divTrunc(seg_w, 2) - 5, is_y + main.SET_ROW_H - 11, "Inter Bold 12", 0.95, 0.95, 0.98);
    }

    // Pinned apps list
    const pins_label_y = is_y + main.SET_ROW_H + 14;
    _ = panel_mod.widgetText(cr, "Pinned Apps", list_x + 2, pins_label_y + main.SET_ROW_H - 10, "Inter Bold 11", 0.6, 0.7, 0.85);
    dock_mod.initOrder();
    const pins_start = pins_label_y + main.SET_ROW_H;
    var row: i32 = 0;
    while (row * main.SET_ROW_H + pins_start < r.y + r.h - 8) : (row += 1) {
        const idx = row;
        if (idx >= dock_mod.persistent_count) break;
        const iy = pins_start + row * main.SET_ROW_H;
        const wy = iy + main.SET_ROW_H;

        main.roundedRect(cr, @floatFromInt(list_x), @floatFromInt(iy), @floatFromInt(list_w), @floatFromInt(main.SET_ROW_H - 6), 8.0);
        c.cairo_set_source_rgba(cr, 1, 1, 1, 0.04);
        c.cairo_fill(cr);

        const name = std.mem.sliceTo(&dock_mod.persistent_order[@intCast(idx)], 0);
        _ = panel_mod.widgetText(cr, @ptrCast(name.ptr), list_x + 10, wy - 8, "Inter 12", 0.9, 0.9, 0.92);
        drawListBtn(cr, list_x + list_w - 4, iy + 4, "✕", true);
    }

    // Ghost drop indicator line during pin drag-reorder
    if (main.settings_drag_idx >= 0 and main.settings_tab == 1) {
        const drop_y = main.pointer_y - 2;
        if (drop_y > pins_start and drop_y < r.y + r.h - 8) {
            c.cairo_set_source_rgba(cr, 0.3, 0.6, 1.0, 0.6);
            c.cairo_set_line_width(cr, 2.0);
            c.cairo_move_to(cr, @floatFromInt(list_x + 4), @floatFromInt(drop_y));
            c.cairo_line_to(cr, @floatFromInt(list_x + list_w - 4), @floatFromInt(drop_y));
            c.cairo_stroke(cr);
        }
    }
}

pub fn drawFontScaleRow(cr: *c.cairo_t, x: i32, w: i32, y: i32) void {
    _ = panel_mod.widgetText(cr, "Font Size", x + 2, y + main.SET_ROW_H - 8, "Inter 12", 0.9, 0.9, 0.92);
    const pct = @as(i32, @intFromFloat(main.font_scale * 100.0 + 0.5));
    const btn_w: i32 = 36;
    const val_w: i32 = 56;
    const total = btn_w * 2 + val_w;
    const bx = x + w - total;
    // − button
    drawListBtn(cr, bx, y + 4, "−", false);
    // value
    const val_x = bx + btn_w;
    main.roundedRect(cr, @floatFromInt(val_x), @floatFromInt(y + 4), @floatFromInt(val_w), @floatFromInt(main.SET_ROW_H - 14), 6.0);
    c.cairo_set_source_rgba(cr, 1, 1, 1, 0.06);
    c.cairo_fill(cr);
    var buf: [32]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "{d}%", .{pct}) catch {};
    _ = panel_mod.widgetText(cr, @ptrCast(&buf), val_x + 10, y + main.SET_ROW_H - 13, "Inter Bold 12", 0.9, 0.95, 1.0);
    // + button
    drawListBtn(cr, val_x + val_w, y + 4, "+", false);
}


pub fn drawListBtn(cr: *c.cairo_t, x: i32, y: i32, glyph: []const u8, danger: bool) void {
    const bw: f64 = 36.0;
    const bh: f64 = @floatFromInt(main.SET_ROW_H - 14);
    main.roundedRect(cr, @floatFromInt(x), @floatFromInt(y), bw, bh, 6.0);
    if (danger) {
        c.cairo_set_source_rgba(cr, 0.9, 0.2, 0.3, 0.16);
    } else {
        c.cairo_set_source_rgba(cr, 1, 1, 1, 0.09);
    }
    c.cairo_fill(cr);
    _ = panel_mod.widgetText(cr, @ptrCast(glyph.ptr), x + 9, y + main.SET_ROW_H - 13, "Inter 12", 0.8, 0.8, 0.85);
}

pub fn drawToggleRow(cr: *c.cairo_t, x: i32, w: i32, y: i32, label: []const u8, on: bool) void {
    _ = panel_mod.widgetText(cr, @ptrCast(label.ptr), x + 6, y + main.SET_ROW_H, "Inter 10", 0.9, 0.9, 0.92);
    const tw: i32 = 44;
    const th: i32 = 20;
    const tx = x + w - tw;
    const ty = y + (main.SET_ROW_H - th) / 2;
    
    main.roundedRect(cr, @floatFromInt(tx), @floatFromInt(ty), @floatFromInt(tw), @floatFromInt(th), @as(f64, @floatFromInt(th)) / 2.0);
    if (on) {
        c.cairo_set_source_rgb(cr, 0.2, 0.5, 0.95);
    } else {
        c.cairo_set_source_rgba(cr, 1, 1, 1, 0.1);
    }
    c.cairo_fill(cr);
    
    const knob: f64 = if (on) @floatFromInt(tx + tw - th + 2) else @floatFromInt(tx + 2);
    c.cairo_set_source_rgb(cr, 0.95, 0.95, 0.98);
    c.cairo_arc(cr, knob + @as(f64, @floatFromInt(th)) / 2.0 - 1.0, @floatFromInt(ty + th / 2), @as(f64, @floatFromInt(th)) / 2.0 - 3.0, 0, 2.0 * std.math.pi);
    c.cairo_fill(cr);
}
