// blend2d_render_test.zig — Unit tests for blend2d_render.zig
const std = @import("std");
const render = @import("blend2d_render.zig");
const c = @import("c.zig").c;

test "TextMetrics default" {
    const tm = render.TextMetrics{};
    try std.testing.expectEqual(@as(f64, 0), tm.width);
    try std.testing.expectEqual(@as(f64, 0), tm.height);
}

test "BlendRenderer struct size" {
    const size = @sizeOf(render.BlendRenderer);
    try std.testing.expect(size > 0);
    try std.testing.expect(size < 4096); // Sanity check
}

test "BlendRenderer — init and deinit" {
    // Allocate a small pixel buffer
    const W: i32 = 64;
    const H: i32 = 32;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch |err| {
        // If Blend2D is not available, skip the test
        std.log.warn("Blend2D init failed (library not linked?): {}", .{err});
        return;
    };
    defer renderer.deinit();

    try std.testing.expect(renderer.initialized);
    try std.testing.expectEqual(W, renderer.buf_width);
    try std.testing.expectEqual(H, renderer.buf_height);
    try std.testing.expectEqual(stride, renderer.stride);
}

test "BlendRenderer — fillRect produces pixels" {
    const W: i32 = 32;
    const H: i32 = 32;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    // Fill entire buffer with red
    renderer.fillRect(0, 0, @floatFromInt(W), @floatFromInt(H), 0xFFFF0000);
    renderer.flush();

    // Check that pixels are non-zero
    var nonzero: usize = 0;
    for (buf) |b| {
        if (b != 0) nonzero += 1;
    }
    try std.testing.expect(nonzero > 0);
}

test "BlendRenderer — fillRect partial" {
    const W: i32 = 32;
    const H: i32 = 32;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    // Fill top-left quadrant only
    renderer.fillRect(0, 0, 16, 16, 0xFF00FF00);
    renderer.flush();

    // Top-left should be green
    const pixel0 = @as(u32, buf[0]) | (@as(u32, buf[1]) << 8) |
        (@as(u32, buf[2]) << 16) | (@as(u32, buf[3]) << 24);
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), pixel0);
}

test "BlendRenderer — fillRectRaw" {
    const W: i32 = 16;
    const H: i32 = 16;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    renderer.fillRectRaw(0, 0, @floatFromInt(W), @floatFromInt(H), 0, 128, 255, 255);
    renderer.flush();

    // Check first pixel: A=255, R=0, G=128, B=255
    try std.testing.expectEqual(@as(u8, 255), buf[3]); // A
    try std.testing.expectEqual(@as(u8, 0), buf[2]);   // R
    try std.testing.expectEqual(@as(u8, 128), buf[1]); // G
    try std.testing.expectEqual(@as(u8, 255), buf[0]); // B
}

test "BlendRenderer — multiple flushes" {
    const W: i32 = 16;
    const H: i32 = 16;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    // First frame: red
    renderer.fillRect(0, 0, @floatFromInt(W), @floatFromInt(H), 0xFFFF0000);
    renderer.flush();

    var nonzero: usize = 0;
    for (buf) |b| {
        if (b != 0) nonzero += 1;
    }
    try std.testing.expect(nonzero > 0);

    // Second frame: blue (overwrite)
    renderer.fillRect(0, 0, @floatFromInt(W), @floatFromInt(H), 0xFF0000FF);
    renderer.flush();

    // Should still have non-zero pixels
    nonzero = 0;
    for (buf) |b| {
        if (b != 0) nonzero += 1;
    }
    try std.testing.expect(nonzero > 0);
}

test "BlendRenderer — drawBorder" {
    const W: i32 = 32;
    const H: i32 = 32;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    renderer.drawBorder(4, 4, 24, 24, 0xFFFFFFFF);
    renderer.flush();

    // Border should produce some non-zero pixels
    var nonzero: usize = 0;
    for (buf) |b| {
        if (b != 0) nonzero += 1;
    }
    try std.testing.expect(nonzero > 0);
}

test "BlendRenderer — drawCircle" {
    const W: i32 = 32;
    const H: i32 = 32;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    renderer.drawCircle(16, 16, 10, 0xFF00FF00);
    renderer.flush();

    // Circle should produce some non-zero pixels
    var nonzero: usize = 0;
    for (buf) |b| {
        if (b != 0) nonzero += 1;
    }
    try std.testing.expect(nonzero > 0);
}

test "BlendRenderer — measureText returns valid metrics" {
    const W: i32 = 64;
    const H: i32 = 32;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    const tm = renderer.measureText("Hello");
    // Width should be positive if font is loaded
    if (renderer.font_loaded) {
        try std.testing.expect(tm.width > 0);
        try std.testing.expect(tm.height > 0);
    }
}

test "BlendRenderer — measureText empty string" {
    const W: i32 = 32;
    const H: i32 = 32;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    const tm = renderer.measureText("");
    try std.testing.expectEqual(@as(f64, 0), tm.width);
    try std.testing.expectEqual(@as(f64, 0), tm.height);
}

test "BlendRenderer — setFontSize" {
    const W: i32 = 32;
    const H: i32 = 32;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    // Should not crash
    renderer.setFontSize(24.0);
    renderer.setFontSize(8.0);
    renderer.setFontSize(72.0);
    try std.testing.expect(true);
}

test "BlendRenderer — deinit is idempotent" {
    const W: i32 = 16;
    const H: i32 = 16;
    const stride = W * 4;
    var buf: [@as(usize, @intCast(W * H * 4))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;

    renderer.deinit();
    try std.testing.expect(!renderer.initialized);

    // Second deinit should not crash
    renderer.deinit();
    try std.testing.expect(true);
}

test "BlendRenderer — stride alignment handling" {
    // Test with non-standard stride (padded beyond pixel width)
    const W: i32 = 30;
    const H: i32 = 4;
    const stride = 128; // Stride wider than W*4=120
    var buf: [@as(usize, @intCast(stride * H))]u8 = undefined;
    @memset(&buf, 0);

    var renderer = render.BlendRenderer.init(&buf, W, H, stride) catch return;
    defer renderer.deinit();

    renderer.fillRect(0, 0, @floatFromInt(W), @floatFromInt(H), 0xFF1A1C26);
    renderer.flush();

    // First pixel should be correct
    const pixel0 = @as(u32, buf[0]) | (@as(u32, buf[1]) << 8) |
        (@as(u32, buf[2]) << 16) | (@as(u32, buf[3]) << 24);
    try std.testing.expectEqual(@as(u32, 0xFF1A1C26), pixel0);

    // Last pixel of first row should also be correct
    const last_row0_idx = @as(usize, @intCast((W - 1) * 4));
    const pixel_last = @as(u32, buf[last_row0_idx]) | (@as(u32, buf[last_row0_idx + 1]) << 8) |
        (@as(u32, buf[last_row0_idx + 2]) << 16) | (@as(u32, buf[last_row0_idx + 3]) << 24);
    try std.testing.expectEqual(@as(u32, 0xFF1A1C26), pixel_last);

    // Second row should also be correct (stride handled properly)
    const row1_idx = @as(usize, @intCast(stride));
    const pixel_row1 = @as(u32, buf[row1_idx]) | (@as(u32, buf[row1_idx + 1]) << 8) |
        (@as(u32, buf[row1_idx + 2]) << 16) | (@as(u32, buf[row1_idx + 3]) << 24);
    try std.testing.expectEqual(@as(u32, 0xFF1A1C26), pixel_row1);
}
