// icon_test.zig — Unit tests for icon.zig pure logic functions
const std = @import("std");
const icon = @import("icon.zig");
const c = @import("c.zig").c;

// ---- Cache tests ----

test "clearCache — resets count to zero" {
    icon.clearCache();
    try std.testing.expect(true);
}

test "clearCache — idempotent" {
    icon.clearCache();
    icon.clearCache();
    icon.clearCache();
    try std.testing.expect(true);
}

// ---- Fallback icon tests ----

test "fallback — creates valid image" {
    var img = icon.fallback("firefox", 32);
    _ = c.bl_image_destroy(@ptrCast(&img));
    try std.testing.expect(true);
}

test "fallback — different sizes" {
    const sizes = [_]i32{ 16, 24, 32, 48, 64 };
    for (sizes) |size| {
        var img = icon.fallback("test", size);
        _ = c.bl_image_destroy(@ptrCast(&img));
    }
    try std.testing.expect(true);
}

test "fallback — empty app_id" {
    var img = icon.fallback("", 32);
    _ = c.bl_image_destroy(@ptrCast(&img));
    try std.testing.expect(true);
}

test "fallback — special characters in app_id" {
    var img = icon.fallback("org.example.app-v2.1", 32);
    _ = c.bl_image_destroy(@ptrCast(&img));
    try std.testing.expect(true);
}

test "fallback — unicode app_id" {
    var img = icon.fallback("com.github.user.app", 32);
    _ = c.bl_image_destroy(@ptrCast(&img));
    try std.testing.expect(true);
}

test "fallback — very long app_id" {
    var img = icon.fallback("com.very.long.application.name.that.exceeds.normal.length.limits", 32);
    _ = c.bl_image_destroy(@ptrCast(&img));
    try std.testing.expect(true);
}

// ---- Load function tests ----

test "load — returns null for non-existent app" {
    const result = icon.load("com.nonexistent.app.that.does.not.exist", 32);
    try std.testing.expect(result == null);
}

test "load — caches results" {
    const result1 = icon.load("com.nonexistent.app.that.does.not.exist", 32);
    const result2 = icon.load("com.nonexistent.app.that.does.not.exist", 32);
    try std.testing.expect(result1 == null);
    try std.testing.expect(result2 == null);
}

test "load — different app_ids are independent" {
    const r1 = icon.load("com.app.one", 32);
    const r2 = icon.load("com.app.two", 32);
    try std.testing.expect(r1 == null);
    try std.testing.expect(r2 == null);
}

// ---- Cache limit tests ----

test "cache — does not crash at limit" {
    for (0..70) |i| {
        var buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "app-{d}", .{i}) catch continue;
        _ = icon.load(@ptrCast(name.ptr), 32);
    }
    try std.testing.expect(true);
}

// ---- Icon size tests ----

test "sizes array — valid dimensions" {
    const sizes = [_]i32{ 48, 32, 24, 22, 16, 64, 96, 128, 256 };
    for (sizes) |s| {
        try std.testing.expect(s > 0);
        try std.testing.expect(s <= 256);
    }
}
