const std = @import("std");

pub const MAX_TOPLEVELS = 64;

pub const ToplevelInfo = struct {
    handle: ?*anyopaque = null,
    title: [256]u8 = std.mem.zeroes([256]u8),
    app_id: [128]u8 = std.mem.zeroes([128]u8),
    id: u32 = 0,
    focused: bool = false,
    minimized: bool = false,
    maximized: bool = false,
};

pub fn findIndex(infos: []ToplevelInfo, count: i32, handle: ?*anyopaque) i32 {
    for (0..@intCast(count)) |i| {
        if (infos[i].handle == handle) return @intCast(i);
    }
    return -1;
}

pub fn add(infos: []ToplevelInfo, count: *i32, handle: ?*anyopaque) usize {
    if (count.* >= MAX_TOPLEVELS) return 0;
    const idx: usize = @intCast(count.*);
    count.* += 1;
    infos[idx] = .{ .handle = handle };
    return idx;
}

pub fn removeAt(infos: []ToplevelInfo, count: *i32, idx: i32) void {
    if (idx < 0 or idx >= count.*) return;
    count.* -= 1;
    const ui: usize = @intCast(idx);
    const uc: usize = @intCast(count.*);
    var i = ui;
    while (i < count.*) : (i += 1) {
        infos[i] = infos[i + 1];
    }
    infos[uc] = .{};
}
