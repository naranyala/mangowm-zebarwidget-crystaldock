// panel_test.zig — Unit tests for panel.zig widget system
const std = @import("std");
const panel = @import("panel.zig");
const toplevel = @import("toplevel.zig");

test "WidgetType enum has all expected variants" {
    const types = [_]panel.WidgetType{
        .workspaces, .toplevel_task, .launcher,
        .cpu, .mem, .temp, .disk, .battery,
        .volume, .network, .media, .clock, .power,
    };
    try std.testing.expectEqual(@as(usize, 13), types.len);
}

test "widgetCreateDefault — correct count" {
    const result = panel.widgetCreateDefault();
    try std.testing.expectEqual(@as(i32, 13), result.count);
}

test "widgetCreateDefault — correct sides" {
    const result = panel.widgetCreateDefault();

    // Left side: workspaces, toplevel_task, launcher
    try std.testing.expectEqual(@as(u8, 0), result.widgets[0].side); // workspaces
    try std.testing.expectEqual(@as(u8, 0), result.widgets[1].side); // toplevel_task
    try std.testing.expectEqual(@as(u8, 0), result.widgets[2].side); // launcher

    // Right side: cpu through power
    for (3..13) |i| {
        try std.testing.expectEqual(@as(u8, 1), result.widgets[i].side);
    }
}

test "widgetCreateDefault — all have measure and draw functions" {
    const result = panel.widgetCreateDefault();
    for (0..@intCast(result.count)) |i| {
        try std.testing.expect(result.widgets[i].measure_fn != null);
        try std.testing.expect(result.widgets[i].draw_fn != null);
    }
}

test "widgetCreateDefault — click functions" {
    const result = panel.widgetCreateDefault();
    for (0..@intCast(result.count)) |i| {
        if (result.widgets[i].wtype != .toplevel_task) {
            try std.testing.expect(result.widgets[i].click_fn != null);
        }
    }
}

test "widgetCreateDefault — update functions" {
    const result = panel.widgetCreateDefault();
    const has_update = [_]panel.WidgetType{ .cpu, .mem, .temp, .battery, .clock };
    for (0..@intCast(result.count)) |i| {
        var found = false;
        for (has_update) |ut| {
            if (result.widgets[i].wtype == ut) {
                found = true;
                break;
            }
        }
        if (found) {
            try std.testing.expect(result.widgets[i].update_fn != null);
        }
    }
}

test "widgetCreateDefault — workspace labels" {
    const result = panel.widgetCreateDefault();
    const ws = &result.widgets[0];
    try std.testing.expectEqual(panel.WidgetType.workspaces, ws.wtype);
    const labels = std.mem.sliceTo(&ws.ws_labels, 0);
    try std.testing.expect(std.mem.indexOf(u8, labels, "1") != null);
    try std.testing.expect(std.mem.indexOf(u8, labels, "4") != null);
}

test "widgetCreateDefault — launcher command" {
    const result = panel.widgetCreateDefault();
    const launcher = &result.widgets[2];
    try std.testing.expectEqual(panel.WidgetType.launcher, launcher.wtype);
    const cmd = std.mem.sliceTo(&launcher.cmd, 0);
    try std.testing.expectEqualStrings("fuzzel &", cmd);
}

test "widgetCreateDefault — CPU initial text" {
    const result = panel.widgetCreateDefault();
    const cpu = &result.widgets[3];
    try std.testing.expectEqual(panel.WidgetType.cpu, cpu.wtype);
    const txt = std.mem.sliceTo(&cpu.cpu_txt, 0);
    try std.testing.expectEqualStrings("CPU --", txt);
}

test "widgetCreateDefault — MEM initial text" {
    const result = panel.widgetCreateDefault();
    const mem = &result.widgets[4];
    try std.testing.expectEqual(panel.WidgetType.mem, mem.wtype);
    const txt = std.mem.sliceTo(&mem.mem_txt, 0);
    try std.testing.expectEqualStrings("MEM --", txt);
}

test "widgetCreateDefault — clock format" {
    const result = panel.widgetCreateDefault();
    const clk = &result.widgets[11];
    try std.testing.expectEqual(panel.WidgetType.clock, clk.wtype);
    const fmt = std.mem.sliceTo(&clk.clock_fmt, 0);
    try std.testing.expectEqualStrings("%H:%M", fmt);
}

test "widgetCreateDefault — power command" {
    const result = panel.widgetCreateDefault();
    const pwr = &result.widgets[12];
    try std.testing.expectEqual(panel.WidgetType.power, pwr.wtype);
    const cmd = std.mem.sliceTo(&pwr.cmd, 0);
    try std.testing.expectEqualStrings("loginctl poweroff &", cmd);
}

test "widgetListWidth — single widget" {
    var result = panel.widgetCreateDefault();
    const total = panel.widgetListWidth(result.widgets[0..1], 36, 12);
    try std.testing.expect(total > 0);
    // Workspace measure: " 1 2 3 4 " has chars, measure = len*7+8
    // Just verify it returns a positive value
    try std.testing.expect(result.widgets[0].cached_w > 0);
}

test "widgetListWidth — multiple widgets accumulate" {
    var result = panel.widgetCreateDefault();
    const total = panel.widgetListWidth(result.widgets[0..3], 36, 12);
    try std.testing.expect(total > 0);
}

test "widgetListWidth — updates cached_w" {
    var result = panel.widgetCreateDefault();
    _ = panel.widgetListWidth(result.widgets[0..3], 36, 12);
    try std.testing.expect(result.widgets[0].cached_w > 0);
    try std.testing.expect(result.widgets[1].cached_w >= 0);
    try std.testing.expect(result.widgets[2].cached_w > 0);
}

test "PanelCtx default" {
    var infos: [64]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    const ctx = panel.PanelCtx{
        .toplevels = &infos,
        .count = &count,
        .seat = null,
    };
    try std.testing.expectEqual(@as(i32, 0), ctx.count.*);
}

test "Widget struct size is reasonable" {
    const size = @sizeOf(panel.Widget);
    try std.testing.expect(size > 0);
    try std.testing.expect(size < 1024);
}
