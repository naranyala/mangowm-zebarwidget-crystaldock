// toplevel_test.zig — Unit tests for toplevel.zig
const std = @import("std");
const toplevel = @import("toplevel.zig");

test "ToplevelInfo default initialization" {
    const info = toplevel.ToplevelInfo{};
    try std.testing.expectEqual(@as(?*anyopaque, null), info.handle);
    try std.testing.expectEqual(false, info.focused);
    try std.testing.expectEqual(false, info.minimized);
    try std.testing.expectEqual(false, info.maximized);
    try std.testing.expectEqual(@as(u32, 0), info.id);
    // title and app_id should be zeroed
    try std.testing.expectEqual(@as(u8, 0), info.title[0]);
    try std.testing.expectEqual(@as(u8, 0), info.app_id[0]);
}

test "findIndex — empty array" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    const result = toplevel.findIndex(&infos, 0, null);
    try std.testing.expectEqual(@as(i32, -1), result);
}

test "findIndex — handle not found" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x2000));

    const result = toplevel.findIndex(&infos, count, @ptrFromInt(0x3000));
    try std.testing.expectEqual(@as(i32, -1), result);
}

test "findIndex — handle found" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x2000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x3000));

    try std.testing.expectEqual(@as(i32, 0), toplevel.findIndex(&infos, count, @ptrFromInt(0x1000)));
    try std.testing.expectEqual(@as(i32, 1), toplevel.findIndex(&infos, count, @ptrFromInt(0x2000)));
    try std.testing.expectEqual(@as(i32, 2), toplevel.findIndex(&infos, count, @ptrFromInt(0x3000)));
}

test "findIndex — null handle" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, null);
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));

    try std.testing.expectEqual(@as(i32, 0), toplevel.findIndex(&infos, count, null));
}

test "add — single element" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;

    const idx = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    try std.testing.expectEqual(@as(usize, 0), idx);
    try std.testing.expectEqual(@as(i32, 1), count);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1000)), infos[0].handle);
}

test "add — multiple elements" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;

    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x2000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x3000));

    try std.testing.expectEqual(@as(i32, 3), count);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1000)), infos[0].handle);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x2000)), infos[1].handle);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x3000)), infos[2].handle);
}

test "add — at capacity returns 0" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = toplevel.MAX_TOPLEVELS;

    const idx = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    try std.testing.expectEqual(@as(usize, 0), idx);
    try std.testing.expectEqual(@as(i32, toplevel.MAX_TOPLEVELS), count);
}

test "add — null handle" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;

    const idx = toplevel.add(&infos, &count, null);
    try std.testing.expectEqual(@as(usize, 0), idx);
    try std.testing.expectEqual(@as(?*anyopaque, null), infos[0].handle);
}

test "removeAt — first element" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x2000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x3000));

    toplevel.removeAt(&infos, &count, 0);

    try std.testing.expectEqual(@as(i32, 2), count);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x2000)), infos[0].handle);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x3000)), infos[1].handle);
}

test "removeAt — last element" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x2000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x3000));

    toplevel.removeAt(&infos, &count, 2);

    try std.testing.expectEqual(@as(i32, 2), count);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1000)), infos[0].handle);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x2000)), infos[1].handle);
    // Removed slot should be zeroed
    try std.testing.expectEqual(@as(?*anyopaque, null), infos[2].handle);
}

test "removeAt — middle element" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x2000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x3000));

    toplevel.removeAt(&infos, &count, 1);

    try std.testing.expectEqual(@as(i32, 2), count);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1000)), infos[0].handle);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x3000)), infos[1].handle);
}

test "removeAt — invalid index (negative)" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));

    toplevel.removeAt(&infos, &count, -1);
    try std.testing.expectEqual(@as(i32, 1), count);
}

test "removeAt — invalid index (out of bounds)" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));

    toplevel.removeAt(&infos, &count, 5);
    try std.testing.expectEqual(@as(i32, 1), count);
}

test "removeAt — all elements" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000));
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x2000));

    toplevel.removeAt(&infos, &count, 0);
    toplevel.removeAt(&infos, &count, 0);

    try std.testing.expectEqual(@as(i32, 0), count);
}

test "add then remove cycle" {
    var infos: [toplevel.MAX_TOPLEVELS]toplevel.ToplevelInfo = undefined;
    var count: i32 = 0;

    // Add 5 elements
    for (0..5) |i| {
        _ = toplevel.add(&infos, &count, @ptrFromInt(0x1000 + i * 0x1000));
    }
    try std.testing.expectEqual(@as(i32, 5), count);

    // Remove middle
    toplevel.removeAt(&infos, &count, 2);
    try std.testing.expectEqual(@as(i32, 4), count);

    // Add one more
    _ = toplevel.add(&infos, &count, @ptrFromInt(0x6000));
    try std.testing.expectEqual(@as(i32, 5), count);

    // Verify order
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1000)), infos[0].handle);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x2000)), infos[1].handle);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x4000)), infos[2].handle);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x5000)), infos[3].handle);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x6000)), infos[4].handle);
}
