// dock_test.zig — Unit tests for dock.zig layout functions
const std = @import("std");
const dock = @import("dock.zig");
const toplevel = @import("toplevel.zig");

test "DOCK_ICON_SIZE constant" {
    try std.testing.expectEqual(@as(i32, 28), dock.DOCK_ICON_SIZE);
}

test "iconAt — no windows" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    const result = dock.iconAt(1920, 48, &infos, 0, 960);
    try std.testing.expectEqual(@as(i32, -1), result);
}

test "iconAt — single window centered" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));

    // Single icon centered at x=960 (center of 1920)
    const center_x: i32 = 960; // center of 1920

    // Click on the icon
    const result = dock.iconAt(1920, 48, &infos, 1, center_x);
    try std.testing.expectEqual(@as(i32, 0), result);
}

test "iconAt — miss to the left" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));

    const result = dock.iconAt(1920, 48, &infos, 1, 0);
    try std.testing.expectEqual(@as(i32, -1), result);
}

test "iconAt — miss to the right" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));

    const result = dock.iconAt(1920, 48, &infos, 1, 1919);
    try std.testing.expectEqual(@as(i32, -1), result);
}

test "iconAt — multiple windows" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x2000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x3000));

    const slot = dock.DOCK_ICON_SIZE + 8; // 36
    const total_w: i32 = 3 * slot - 8; // 100
    const start_x: i32 = @divTrunc(1920 - total_w, 2); // center

    // Click on first icon
    try std.testing.expectEqual(@as(i32, 0), dock.iconAt(1920, 48, &infos, 3, start_x));

    // Click on second icon
    try std.testing.expectEqual(@as(i32, 1), dock.iconAt(1920, 48, &infos, 3, start_x + slot));

    // Click on third icon
    try std.testing.expectEqual(@as(i32, 2), dock.iconAt(1920, 48, &infos, 3, start_x + 2 * slot));

    // Click before first icon
    try std.testing.expectEqual(@as(i32, -1), dock.iconAt(1920, 48, &infos, 3, start_x - 1));

    // Click after last icon
    try std.testing.expectEqual(@as(i32, -1), dock.iconAt(1920, 48, &infos, 3, start_x + 3 * slot));
}

test "iconAt — narrow screen" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x2000));

    // Screen narrower than icons — start_x should clamp to 0
    const result = dock.iconAt(80, 48, &infos, 2, 40);
    try std.testing.expect(result >= 0);
}

test "iconAt — exact boundary" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));

    const slot = dock.DOCK_ICON_SIZE + 8;
    const start_x: i32 = @divTrunc(1920 - (slot - 8), 2);

    // Click at exact left edge of icon
    try std.testing.expectEqual(@as(i32, 0), dock.iconAt(1920, 48, &infos, 1, start_x));

    // Click at exact right edge (exclusive)
    try std.testing.expectEqual(@as(i32, -1), dock.iconAt(1920, 48, &infos, 1, start_x + dock.DOCK_ICON_SIZE + 8));
}
