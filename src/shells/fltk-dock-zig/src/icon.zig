const std = @import("std");
const c = @import("c.zig").c;

const desktop_dirs = [_][]const u8{
    "/usr/share/applications/",
    "/usr/local/share/applications/",
};

const theme_dirs = [_][]const u8{
    "/usr/share/icons/hicolor/{d}x{d}/apps/",
    "/usr/local/share/icons/hicolor/{d}x{d}/apps/",
    "/usr/share/icons/Papirus/{d}x{d}/apps/",
    "/usr/share/icons/Papirus-Dark/{d}x{d}/apps/",
    "/usr/share/icons/breeze/apps/{d}/",
    "/usr/share/icons/breeze-dark/apps/{d}/",
    "/usr/share/icons/gnome/{d}x{d}/apps/",
    "/usr/share/icons/Adwaita/{d}x{d}/apps/",
};

const scalable_dirs = [_][]const u8{
    "/usr/share/icons/hicolor/scalable/apps/",
    "/usr/local/share/icons/hicolor/scalable/apps/",
    "/usr/share/icons/Papirus/scalable/apps/",
    "/usr/share/icons/Papirus-Dark/scalable/apps/",
    "/usr/share/icons/breeze/apps/scalable/",
    "/usr/share/icons/breeze-dark/apps/scalable/",
    "/usr/share/icons/gnome/scalable/apps/",
    "/usr/share/icons/Adwaita/scalable/apps/",
};

const sizes = [_]i32{ 48, 32, 24, 22, 16, 64, 96, 128, 256 };

// Icon cache
const CacheEntry = struct {
    app_id: [128]u8,
    surf: ?*c.cairo_surface_t,
};

const ICON_CACHE_MAX = 64;
var icon_cache: [ICON_CACHE_MAX]CacheEntry = std.mem.zeroes([ICON_CACHE_MAX]CacheEntry);
var icon_cache_count: i32 = 0;

pub fn clearCache() void {
    for (0..@intCast(icon_cache_count)) |i| {
        if (icon_cache[i].surf) |s| c.cairo_surface_destroy(s);
    }
    icon_cache_count = 0;
}

fn pathExists(path: [*:0]const u8) bool {
    const f = c.fopen(path, "r") orelse return false;
    _ = c.fclose(f);
    return true;
}

fn findDesktopFile(app_id: [*:0]const u8) ?[512:0]u8 {
    var buf: [512:0]u8 = std.mem.zeroes([512:0]u8);
    const id_slice = std.mem.sliceTo(app_id, 0);

    for (desktop_dirs) |dir| {
        // Try direct match: app_id.desktop
        const path = std.fmt.bufPrintZ(&buf, "{s}{s}.desktop", .{ dir, id_slice }) catch continue;
        if (pathExists(path.ptr)) return buf;

        // Try with hyphens replaced by dots: org.example-app -> org.example.app.desktop
        var alt: [128]u8 = std.mem.zeroes([128]u8);
        var alt_len: usize = 0;
        for (id_slice) |ch| {
            if (alt_len < alt.len) {
                alt[alt_len] = if (ch == '-') '.' else ch;
                alt_len += 1;
            }
        }
        if (alt_len > 0) {
            const alt_path = std.fmt.bufPrintZ(&buf, "{s}{s}.desktop", .{ dir, alt[0..alt_len] }) catch continue;
            if (pathExists(alt_path.ptr)) return buf;
        }
    }
    return null;
}

fn readIconName(desktop_path: [*:0]const u8) ?[128:0]u8 {
    var icon_name: [128:0]u8 = std.mem.zeroes([128:0]u8);
    const f = c.fopen(desktop_path, "r") orelse return null;
    defer _ = c.fclose(f);

    var line: [512]u8 = std.mem.zeroes([512]u8);
    var in_entry = false;

    while (c.fgets(@ptrCast(&line), @intCast(line.len), f) != null) {
        // Find the actual end of the string (null terminator from fgets)
        const line_len = std.mem.indexOfScalar(u8, &line, 0) orelse line.len;
        const real_line = line[0..line_len];

        if (real_line.len > 0 and real_line[0] == '[') {
            if (in_entry) break;
            in_entry = true;
            continue;
        }
        if (std.mem.startsWith(u8, real_line, "Icon=")) {
            var val = real_line[5..];
            // Strip trailing newline/carriage return
            while (val.len > 0 and (val[val.len - 1] == '\n' or val[val.len - 1] == '\r')) {
                val = val[0 .. val.len - 1];
            }
            const len = @min(val.len, icon_name.len - 1);
            @memcpy(icon_name[0..len], val[0..len]);
            icon_name[len] = 0;
            break;
        }
    }
    return if (icon_name[0] != 0) icon_name else null;
}

fn scaleToSize(src: *c.cairo_surface_t, size: i32) *c.cairo_surface_t {
    const w = c.cairo_image_surface_get_width(src);
    const h = c.cairo_image_surface_get_height(src);
    if (w == size and h == size) return src;

    const scaled = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, size, size);
    const cr = c.cairo_create(scaled);
    c.cairo_scale(cr, @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(w)), @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(h)));
    c.cairo_set_source_surface(cr, src, 0, 0);
    c.cairo_paint(cr);
    c.cairo_destroy(cr);
    c.cairo_surface_destroy(src);
    return scaled;
}

fn buildPath(buf: *[1024:0]u8, dir: []const u8, name: []const u8, ext: []const u8) bool {
    var pos: usize = 0;
    for (dir) |c_val| { if (pos < buf.len) { buf[pos] = c_val; pos += 1; } }
    for (name) |c_val| { if (pos < buf.len) { buf[pos] = c_val; pos += 1; } }
    for (ext) |c_val| { if (pos < buf.len) { buf[pos] = c_val; pos += 1; } }
    if (pos < buf.len) { buf[pos] = 0; return true; }
    return false;
}

fn buildSizedPath(buf: *[1024:0]u8, dir_fmt: []const u8, size1: i32, size2: i32, name: []const u8, ext: []const u8) bool {
    // Manually format the size into the dir template: replace first %d with size1, second with size2
    var pos: usize = 0;
    var size_idx: u8 = 0;
    var i: usize = 0;
    while (i < dir_fmt.len) : (i += 1) {
        if (dir_fmt[i] == '%' and i + 1 < dir_fmt.len and dir_fmt[i + 1] == 'd') {
            const val: usize = @intCast(if (size_idx == 0) size1 else size2);
            size_idx += 1;
            var digit_buf: [16]u8 = undefined;
            const digit_str = std.fmt.bufPrint(&digit_buf, "{d}", .{val}) catch return false;
            for (digit_str) |d| { if (pos < buf.len) { buf[pos] = d; pos += 1; } }
            i += 1; // skip 'd'
        } else {
            if (pos < buf.len) { buf[pos] = dir_fmt[i]; pos += 1; }
        }
    }
    for (name) |c_val| { if (pos < buf.len) { buf[pos] = c_val; pos += 1; } }
    for (ext) |c_val| { if (pos < buf.len) { buf[pos] = c_val; pos += 1; } }
    if (pos < buf.len) { buf[pos] = 0; return true; }
    return false;
}

fn tryLoadPng(icon_name: [*:0]const u8) ?*c.cairo_surface_t {
    // Try scalable directories first
    for (scalable_dirs) |dir| {
        var buf: [1024:0]u8 = std.mem.zeroes([1024:0]u8);
        if (!buildPath(&buf, dir, std.mem.sliceTo(icon_name, 0), ".png")) continue;
        const buf_ptr: [*:0]const u8 = @ptrCast(&buf);
        const surf = c.cairo_image_surface_create_from_png(buf_ptr);
        if (c.cairo_surface_status(surf) == c.CAIRO_STATUS_SUCCESS) return surf;
        c.cairo_surface_destroy(surf);
    }

    // Try sized directories
    for (sizes) |s| {
        for (theme_dirs) |dir| {
            var buf: [1024:0]u8 = std.mem.zeroes([1024:0]u8);
            if (!buildSizedPath(&buf, dir, s, s, std.mem.sliceTo(icon_name, 0), ".png")) continue;
            const buf_ptr: [*:0]const u8 = @ptrCast(&buf);
            const surf = c.cairo_image_surface_create_from_png(buf_ptr);
            if (c.cairo_surface_status(surf) == c.CAIRO_STATUS_SUCCESS) return surf;
            c.cairo_surface_destroy(surf);
        }
    }
    return null;
}

fn loadSvgAndRender(path: [*:0]const u8, size: i32) ?*c.cairo_surface_t {
    const handle = c.rsvg_handle_new_from_file(path, null) orelse return null;
    defer c.g_object_unref(handle);

    var has_w: c.gboolean = 0;
    var has_h: c.gboolean = 0;
    var has_vb: c.gboolean = 0;
    var rsvg_w = std.mem.zeroes(c.RsvgLength);
    var rsvg_h = std.mem.zeroes(c.RsvgLength);
    var vb = c.RsvgRectangle{ .x = 0, .y = 0, .width = @floatFromInt(size), .height = @floatFromInt(size) };

    c.rsvg_handle_get_intrinsic_dimensions(handle, &has_w, &rsvg_w, &has_h, &rsvg_h, &has_vb, &vb);

    var sw: f64 = undefined;
    var sh: f64 = undefined;
    if (has_vb != 0) {
        sw = vb.width;
        sh = vb.height;
    } else if (has_w != 0 and has_h != 0) {
        sw = rsvg_w.length;
        sh = rsvg_h.length;
    } else {
        sw = @floatFromInt(size);
        sh = @floatFromInt(size);
    }
    if (sw <= 0 or sh <= 0) {
        sw = @floatFromInt(size);
        sh = @floatFromInt(size);
    }

    const surf = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, size, size);
    const cr = c.cairo_create(surf);
    const scale = @min(@as(f64, @floatFromInt(size)) / sw, @as(f64, @floatFromInt(size)) / sh);
    const ox = (@as(f64, @floatFromInt(size)) - sw * scale) / 2;
    const oy = (@as(f64, @floatFromInt(size)) - sh * scale) / 2;
    c.cairo_translate(cr, ox, oy);
    c.cairo_scale(cr, scale, scale);
    var viewport = c.RsvgRectangle{ .x = 0, .y = 0, .width = sw, .height = sh };
    _ = c.rsvg_handle_render_document(handle, cr, &viewport, null);
    c.cairo_destroy(cr);
    return surf;
}

fn tryLoadSvg(icon_name: [*:0]const u8, size: i32) ?*c.cairo_surface_t {
    // Try scalable directories first
    for (scalable_dirs) |dir| {
        var buf: [1024:0]u8 = std.mem.zeroes([1024:0]u8);
        if (!buildPath(&buf, dir, std.mem.sliceTo(icon_name, 0), ".svg")) continue;
        const buf_ptr: [*:0]const u8 = @ptrCast(&buf);
        if (!pathExists(buf_ptr)) continue;
        if (loadSvgAndRender(buf_ptr, size)) |surf| return surf;
    }

    // Try sized directories
    for (sizes) |s| {
        for (theme_dirs) |dir| {
            var buf: [1024:0]u8 = std.mem.zeroes([1024:0]u8);
            if (!buildSizedPath(&buf, dir, s, s, std.mem.sliceTo(icon_name, 0), ".svg")) continue;
            const buf_ptr: [*:0]const u8 = @ptrCast(&buf);
            if (!pathExists(buf_ptr)) continue;
            if (loadSvgAndRender(buf_ptr, size)) |surf| return surf;
        }
    }
    return null;
}

pub fn load(app_id: [*:0]const u8, size: i32) ?*c.cairo_surface_t {
    const app_id_slice = std.mem.sliceTo(app_id, 0);

    // Check cache first
    for (0..@intCast(icon_cache_count)) |i| {
        if (std.mem.eql(u8, &icon_cache[i].app_id, app_id_slice)) {
            return icon_cache[i].surf;
        }
    }

    var icon_name_ptr: [*:0]const u8 = app_id;
    var desktop_buf: ?[512:0]u8 = findDesktopFile(app_id);
    if (desktop_buf) |*db| {
        if (readIconName(db.ptr)) |name| {
            icon_name_ptr = @ptrCast(&name);
        }
    }

    var surf = tryLoadPng(icon_name_ptr);
    if (surf) |s| {
        const result = scaleToSize(s, size);
        cacheIcon(app_id_slice, result);
        return result;
    }

    surf = tryLoadSvg(icon_name_ptr, size);
    if (surf) |s| {
        cacheIcon(app_id_slice, s);
        return s;
    }

    // Try app_id directly
    if (icon_name_ptr != app_id) {
        surf = tryLoadPng(app_id);
        if (surf) |s| {
            const result = scaleToSize(s, size);
            cacheIcon(app_id_slice, result);
            return result;
        }

        surf = tryLoadSvg(app_id, size);
        if (surf) |s| {
            cacheIcon(app_id_slice, s);
            return s;
        }
    }

    return null;
}

fn cacheIcon(app_id: []const u8, surf: *c.cairo_surface_t) void {
    if (icon_cache_count >= ICON_CACHE_MAX) return;
    const idx: usize = @intCast(icon_cache_count);
    icon_cache_count += 1;
    const len = @min(app_id.len, 127);
    @memcpy(icon_cache[idx].app_id[0..len], app_id[0..len]);
    icon_cache[idx].app_id[len] = 0;
    icon_cache[idx].surf = surf;
}

fn hueForString(s: []const u8) f64 {
    var h: u32 = 0;
    for (s) |c_val| {
        h = h *| 31 +| @as(u32, c_val);
    }
    return @as(f64, @floatFromInt(@mod(h, 360))) / 360.0;
}

pub fn fallback(app_id: [*:0]const u8, size: i32) *c.cairo_surface_t {
    const surf = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, size, size);
    const cr = c.cairo_create(surf);

    const app_id_slice = std.mem.sliceTo(app_id, 0);
    const hue = hueForString(app_id_slice);
    const h6 = hue * 6;
    const sext: i32 = @intFromFloat(h6);
    const frac = h6 - @as(f64, @floatFromInt(sext));
    const v = 0.6;
    const s = 0.7;
    const p = v * (1 - s);
    const q = v * (1 - s * frac);
    const t = v * (1 - s * (1 - frac));

    var r: f64 = undefined;
    var g: f64 = undefined;
    var b: f64 = undefined;
    switch (@mod(sext, 6)) {
        0 => { r = v; g = t; b = p; },
        1 => { r = q; g = v; b = p; },
        2 => { r = p; g = v; b = t; },
        3 => { r = p; g = q; b = v; },
        4 => { r = t; g = p; b = v; },
        else => { r = v; g = p; b = q; },
    }

    c.cairo_set_source_rgb(cr, r, g, b);
    const cx = @as(f64, @floatFromInt(size)) / 2.0;
    const cy = @as(f64, @floatFromInt(size)) / 2.0;
    const rad = @as(f64, @floatFromInt(size)) / 2.0 - 2;
    c.cairo_arc(cr, cx, cy, rad, 0, 2 * 3.141592653589793);
    c.cairo_fill(cr);

    c.cairo_set_source_rgb(cr, 1, 1, 1);
    c.cairo_select_font_face(cr, "Sans", c.CAIRO_FONT_SLANT_NORMAL, c.CAIRO_FONT_WEIGHT_BOLD);
    c.cairo_set_font_size(cr, @as(f64, @floatFromInt(size)) * 0.55);

    var letter: [2]u8 = undefined;
    if (app_id_slice.len > 0) {
        letter[0] = std.ascii.toUpper(app_id_slice[0]);
    } else {
        letter[0] = '?';
    }
    letter[1] = 0;

    var te = std.mem.zeroes(c.cairo_text_extents_t);
    c.cairo_text_extents(cr, &letter, &te);
    c.cairo_move_to(cr, cx - te.width / 2 - te.x_bearing, cy - te.height / 2 - te.y_bearing);
    _ = c.cairo_show_text(cr, &letter);

    c.cairo_destroy(cr);
    return surf;
}
