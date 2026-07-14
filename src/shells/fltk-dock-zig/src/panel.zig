const std = @import("std");
const c = @import("c.zig").c;
const toplevel = @import("toplevel.zig");

const PANEL_HEIGHT = 36;
const MAX_TOPLEVELS = 64;
const MAX_WIDGETS = 64;

// ---- Widget System ----

pub const WidgetType = enum {
    workspaces,
    toplevel_task,
    launcher,
    cpu,
    mem,
    temp,
    disk,
    battery,
    volume,
    network,
    media,
    clock,
    power,
};

pub const Widget = struct {
    wtype: WidgetType,
    name: [64]u8,
    side: u8, // 0 = left, 1 = right
    cached_w: i32,

    // measure: returns width needed
    measure_fn: ?*const fn (*Widget, i32) i32 = null,
    // draw: render at (x, y) with height h
    draw_fn: ?*const fn (*Widget, *c.cairo_t, i32, i32, i32) void = null,
    // update: refresh data from system
    update_fn: ?*const fn (*Widget) void = null,
    // click: handle click, return true if consumed
    click_fn: ?*const fn (*Widget, u32, i32, i32) bool = null,

    // Private data
    priv: ?*anyopaque = null,

    // Workspaces
    ws_labels: [64]u8 = std.mem.zeroes([64]u8),

    // CPU
    cpu_prev_total: i32 = 0,
    cpu_prev_idle: i32 = 0,
    cpu_txt: [32]u8 = std.mem.zeroes([32]u8),

    // Memory
    mem_txt: [32]u8 = std.mem.zeroes([32]u8),

    // Temperature
    temp_txt: [32]u8 = std.mem.zeroes([32]u8),

    // Disk
    disk_txt: [32]u8 = std.mem.zeroes([32]u8),

    // Battery
    bat_lvl: i32 = -1,
    bat_charging: bool = false,
    bat_txt: [32]u8 = std.mem.zeroes([32]u8),

    // Volume
    vol_pct: i32 = 0,
    vol_mute: bool = false,
    vol_txt: [32]u8 = std.mem.zeroes([32]u8),

    // Network
    net_txt: [64]u8 = std.mem.zeroes([64]u8),

    // Media
    media_txt: [96]u8 = std.mem.zeroes([96]u8),
    media_playing: bool = false,

    // Clock
    clock_fmt: [32]u8 = std.mem.zeroes([32]u8),
    clock_txt: [64]u8 = std.mem.zeroes([64]u8),

    // Launcher/Power
    cmd: [128]u8 = std.mem.zeroes([128]u8),
};

pub const PanelCtx = struct {
    toplevels: []toplevel.ToplevelInfo,
    count: *i32,
    seat: ?*c.wl_seat,
};

// ---- Text Rendering Helpers ----

pub fn widgetText(cr: *c.cairo_t, text: [*:0]const u8, x: i32, h: i32, font_desc: [*:0]const u8, r: f64, g: f64, b: f64) i32 {
    const layout = c.pango_cairo_create_layout(cr);
    defer c.g_object_unref(layout);
    const font = c.pango_font_description_from_string(font_desc);
    defer c.pango_font_description_free(font);
    c.pango_layout_set_font_description(layout, font);
    c.pango_layout_set_text(layout, text, -1);
    var tw: c_int = 0;
    var th: c_int = 0;
    c.pango_layout_get_pixel_size(layout, &tw, &th);
    c.cairo_set_source_rgb(cr, r, g, b);
    c.cairo_move_to(cr, x, @divTrunc(h - th, 2));
    c.pango_cairo_show_layout(cr, layout);
    return tw;
}

pub fn widgetIconGlyph(cr: *c.cairo_t, glyph: [*:0]const u8, x: i32, h: i32, r: f64, g: f64, b: f64) void {
    const layout = c.pango_cairo_create_layout(cr);
    defer c.g_object_unref(layout);
    const font = c.pango_font_description_from_string("Sans 11");
    defer c.pango_font_description_free(font);
    c.pango_layout_set_font_description(layout, font);
    c.pango_layout_set_text(layout, glyph, -1);
    var tw: c_int = 0;
    var th: c_int = 0;
    c.pango_layout_get_pixel_size(layout, &tw, &th);
    c.cairo_set_source_rgb(cr, r, g, b);
    c.cairo_move_to(cr, x, @divTrunc(h - th, 2));
    c.pango_cairo_show_layout(cr, layout);
}

// ---- Widget Measure/Draw Functions ----

fn wsMeasure(w: *Widget, h: i32) i32 {
    _ = h;
    const len = std.mem.indexOfScalar(u8, &w.ws_labels, 0) orelse w.ws_labels.len;
    return @intCast(len * 7 + 8);
}

fn wsDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    _ = widgetText(cr, @ptrCast(&w.ws_labels), x, h, "Sans 10", 0.6, 0.6, 0.7);
}

fn tlMeasure(w: *Widget, h: i32) i32 {
    _ = h;
    _ = w;
    return 16; // stub
}

fn tlDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = w;
    _ = y;
    // Draw taskbar placeholder
    c.cairo_set_source_rgb(cr, 0.40, 0.42, 0.46);
    c.cairo_rectangle(cr, x + 2, 6, 10, h - 12);
    c.cairo_fill(cr);
}

fn launcherMeasure(w: *Widget, h: i32) i32 {
    _ = w;
    _ = h;
    return 22;
}

fn launcherDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = w;
    _ = y;
    widgetIconGlyph(cr, "⌘", x + 4, h, 0.8, 0.8, 0.85);
}

fn launcherClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = x;
    _ = y;
    if (btn != 1) return false;
    // Launch the command (fuzzel by default)
    _ = c.system(@ptrCast(&w.cmd));
    return true;
}

fn cpuUpdate(w: *Widget) void {
    const f = c.fopen("/proc/stat", "r") orelse return;
    defer _ = c.fclose(f);
    var line: [128]u8 = std.mem.zeroes([128]u8);
    if (c.fgets(&line, line.len, f) != null) {
        var u: i32 = 0;
        var n: i32 = 0;
        var s: i32 = 0;
        var io_i: i32 = 0;
        var irq: i32 = 0;
        var sirq: i32 = 0;
        _ = c.sscanf(&line, "cpu %d %d %d %d %*d %d %d", &u, &n, &s, &io_i, &irq, &sirq);
        const idle = io_i;
        const total = u + n + s + io_i + irq + sirq;
        const dtotal = total - w.cpu_prev_total;
        const didle = idle - w.cpu_prev_idle;
        if (dtotal > 0) {
            const pct = @divTrunc(100 * (dtotal - didle), dtotal);
            _ = std.fmt.bufPrintZ(&w.cpu_txt, "CPU {d}%", .{pct}) catch {};
        }
        w.cpu_prev_total = total;
        w.cpu_prev_idle = idle;
    }
}

fn cpuMeasure(w: *Widget, h: i32) i32 {
    _ = w;
    _ = h;
    return 64;
}

fn cpuDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "▸", x, h, 0.5, 0.7, 0.9);
    _ = widgetText(cr, @ptrCast(&w.cpu_txt), x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}

fn memUpdate(w: *Widget) void {
    const f = c.fopen("/proc/meminfo", "r") orelse return;
    defer _ = c.fclose(f);
    var total: i64 = 0;
    var avail: i64 = 0;
    var k: [32]u8 = std.mem.zeroes([32]u8);
    var v: i64 = 0;
    while (c.fscanf(f, "%31s %ld kB", &k, &v) == 2) {
        if (std.mem.eql(u8, std.mem.sliceTo(&k, 0), "MemTotal:")) total = v
        else if (std.mem.eql(u8, std.mem.sliceTo(&k, 0), "MemAvailable:")) avail = v;
    }
    if (total > 0) {
        const used = total - avail;
        const pct: i64 = @divTrunc(100 * used, total);
        _ = std.fmt.bufPrintZ(&w.mem_txt, "MEM {d}%", .{pct}) catch {};
    }
}

fn memMeasure(w: *Widget, h: i32) i32 {
    _ = w;
    _ = h;
    return 70;
}

fn memDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "▤", x, h, 0.6, 0.6, 0.9);
    _ = widgetText(cr, @ptrCast(&w.mem_txt), x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}

fn tempUpdate(w: *Widget) void {
    const f = c.fopen("/sys/class/thermal/thermal_zone0/temp", "r") orelse {
        _ = std.fmt.bufPrintZ(&w.temp_txt, "--°C", .{}) catch {};
        return;
    };
    defer _ = c.fclose(f);
    var mt: i32 = -1;
    _ = c.fscanf(f, "%d", &mt);
    if (mt > 0) {
        _ = std.fmt.bufPrintZ(&w.temp_txt, "{d}°C", .{@divTrunc(mt, 1000)}) catch {};
    } else {
        _ = std.fmt.bufPrintZ(&w.temp_txt, "--°C", .{}) catch {};
    }
}

fn tempMeasure(w: *Widget, h: i32) i32 {
    _ = w;
    _ = h;
    return 56;
}

fn tempDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "♨", x, h, 0.9, 0.6, 0.4);
    _ = widgetText(cr, @ptrCast(&w.temp_txt), x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}

fn diskMeasure(w: *Widget, h: i32) i32 {
    _ = w;
    _ = h;
    return 64;
}

fn diskDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "▥", x, h, 0.5, 0.8, 0.6);
    _ = widgetText(cr, @ptrCast(&w.disk_txt), x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}

fn batMeasure(w: *Widget, h: i32) i32 {
    _ = w;
    _ = h;
    return 64;
}

fn batDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "▮", x, h, 0.5, 0.9, 0.4);
    _ = widgetText(cr, @ptrCast(&w.bat_txt), x + 16, h, "Sans 9", 0.8, 0.8, 0.82);
}

fn volMeasure(w: *Widget, h: i32) i32 {
    _ = w;
    _ = h;
    return 64;
}

fn volDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, if (w.vol_mute) "🔇" else "🔊", x, h, 0.6, 0.8, 0.9);
    _ = widgetText(cr, @ptrCast(&w.vol_txt), x + 18, h, "Sans 9", 0.8, 0.8, 0.82);
}

fn volClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = x;
    _ = y;
    if (btn != 1) return false;
    if (w.vol_mute) {
        _ = c.system("pactl set-sink-mute @DEFAULT_SINK@ 0 &");
    } else {
        _ = c.system("pactl set-sink-mute @DEFAULT_SINK@ 1 &");
    }
    return true;
}

fn netMeasure(w: *Widget, h: i32) i32 {
    _ = w;
    _ = h;
    return 92;
}

fn netDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "📶", x, h, 0.5, 0.9, 0.6);
    _ = widgetText(cr, @ptrCast(&w.net_txt), x + 18, h, "Sans 9", 0.8, 0.8, 0.82);
}

fn mediaMeasure(w: *Widget, h: i32) i32 {
    _ = h;
    const len = std.mem.indexOfScalar(u8, &w.media_txt, 0) orelse w.media_txt.len;
    return @intCast(len * 6 + 20);
}

fn mediaDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    if (w.media_txt[0] == 0) return;
    widgetIconGlyph(cr, if (w.media_playing) "▶" else "❚❚", x, h, 0.9, 0.8, 0.4);
    _ = widgetText(cr, @ptrCast(&w.media_txt), x + 18, h, "Sans 9", 0.85, 0.85, 0.88);
}

fn mediaClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 1) return false;
    _ = c.system("playerctl play-pause &");
    return true;
}

fn clkMeasure(w: *Widget, h: i32) i32 {
    _ = h;
    const len = std.mem.indexOfScalar(u8, &w.clock_txt, 0) orelse w.clock_txt.len;
    return @intCast(len * 7 + 16);
}

fn clkDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    _ = widgetText(cr, @ptrCast(&w.clock_txt), x, h, "Sans 10", 0.85, 0.85, 0.85);
}

fn pwrMeasure(w: *Widget, h: i32) i32 {
    _ = w;
    _ = h;
    return 22;
}

fn pwrDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = w;
    _ = y;
    widgetIconGlyph(cr, "⏻", x + 4, h, 0.9, 0.5, 0.5);
}

fn pwrClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = x;
    _ = y;
    if (btn != 1) return false;
    _ = c.system(@ptrCast(&w.cmd));
    return true;
}

// ---- Widget Creation ----

pub const WidgetList = struct {
    widgets: [MAX_WIDGETS]Widget,
    count: i32,
};

pub fn widgetCreateDefault() WidgetList {
    var result = WidgetList{
        .widgets = std.mem.zeroes([MAX_WIDGETS]Widget),
        .count = 0,
    };

    const defaults = [_]struct { wtype: WidgetType, side: u8 }{
        .{ .wtype = .workspaces, .side = 0 },
        .{ .wtype = .toplevel_task, .side = 0 },
        .{ .wtype = .launcher, .side = 0 },
        .{ .wtype = .cpu, .side = 1 },
        .{ .wtype = .mem, .side = 1 },
        .{ .wtype = .temp, .side = 1 },
        .{ .wtype = .disk, .side = 1 },
        .{ .wtype = .battery, .side = 1 },
        .{ .wtype = .volume, .side = 1 },
        .{ .wtype = .network, .side = 1 },
        .{ .wtype = .media, .side = 1 },
        .{ .wtype = .clock, .side = 1 },
        .{ .wtype = .power, .side = 1 },
    };

    for (defaults) |d| {
        const idx: usize = @intCast(result.count);
        result.widgets[idx] = createWidget(d.wtype);
        result.widgets[idx].side = d.side;
        result.count += 1;
    }

    return result;
}

fn createWidget(wtype: WidgetType) Widget {
    var w: Widget = undefined;
    w.wtype = wtype;
    w.name = std.mem.zeroes([64]u8);
    w.side = 0;
    w.cached_w = 0;
    w.priv = null;
    w.ws_labels = std.mem.zeroes([64]u8);
    w.cpu_prev_total = 0;
    w.cpu_prev_idle = 0;
    w.cpu_txt = std.mem.zeroes([32]u8);
    w.mem_txt = std.mem.zeroes([32]u8);
    w.temp_txt = std.mem.zeroes([32]u8);
    w.disk_txt = std.mem.zeroes([32]u8);
    w.bat_lvl = -1;
    w.bat_charging = false;
    w.bat_txt = std.mem.zeroes([32]u8);
    w.vol_pct = 0;
    w.vol_mute = false;
    w.vol_txt = std.mem.zeroes([32]u8);
    w.net_txt = std.mem.zeroes([64]u8);
    w.media_txt = std.mem.zeroes([96]u8);
    w.media_playing = false;
    w.clock_fmt = std.mem.zeroes([32]u8);
    w.clock_txt = std.mem.zeroes([64]u8);
    w.cmd = std.mem.zeroes([128]u8);
    w.update_fn = null;
    w.click_fn = null;

    switch (wtype) {
        .workspaces => {
            std.mem.copyForwards(u8, &w.ws_labels, " 1 2 3 4 ");
            w.measure_fn = wsMeasure;
            w.draw_fn = wsDraw;
        },
        .toplevel_task => {
            w.measure_fn = tlMeasure;
            w.draw_fn = tlDraw;
        },
        .launcher => {
            std.mem.copyForwards(u8, &w.cmd, "fuzzel &");
            w.measure_fn = launcherMeasure;
            w.draw_fn = launcherDraw;
            w.click_fn = launcherClick;
        },
        .cpu => {
            std.mem.copyForwards(u8, &w.cpu_txt, "CPU --");
            w.measure_fn = cpuMeasure;
            w.draw_fn = cpuDraw;
            w.update_fn = cpuUpdate;
        },
        .mem => {
            std.mem.copyForwards(u8, &w.mem_txt, "MEM --");
            w.measure_fn = memMeasure;
            w.draw_fn = memDraw;
            w.update_fn = memUpdate;
        },
        .temp => {
            std.mem.copyForwards(u8, &w.temp_txt, "--\xc2\xb0C");
            w.measure_fn = tempMeasure;
            w.draw_fn = tempDraw;
            w.update_fn = tempUpdate;
        },
        .disk => {
            std.mem.copyForwards(u8, &w.disk_txt, "SSD --");
            w.measure_fn = diskMeasure;
            w.draw_fn = diskDraw;
        },
        .battery => {
            std.mem.copyForwards(u8, &w.bat_txt, "BAT ?");
            w.measure_fn = batMeasure;
            w.draw_fn = batDraw;
        },
        .volume => {
            w.measure_fn = volMeasure;
            w.draw_fn = volDraw;
            w.click_fn = volClick;
        },
        .network => {
            std.mem.copyForwards(u8, &w.net_txt, "off");
            w.measure_fn = netMeasure;
            w.draw_fn = netDraw;
        },
        .media => {
            w.measure_fn = mediaMeasure;
            w.draw_fn = mediaDraw;
            w.click_fn = mediaClick;
        },
        .clock => {
            std.mem.copyForwards(u8, &w.clock_fmt, "%H:%M");
            w.measure_fn = clkMeasure;
            w.draw_fn = clkDraw;
            w.update_fn = clkUpdate;
        },
        .power => {
            std.mem.copyForwards(u8, &w.cmd, "loginctl poweroff &");
            w.measure_fn = pwrMeasure;
            w.draw_fn = pwrDraw;
            w.click_fn = pwrClick;
        },
    }

    return w;
}

fn clkUpdate(w: *Widget) void {
    const now = c.time(null);
    var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
    _ = c.localtime_r(&now, &tm);
    _ = c.strftime(&w.clock_txt, w.clock_txt.len, &w.clock_fmt, &tm);
}

// ---- Widget List Operations ----

pub fn widgetListUpdate(widgets: []Widget) void {
    for (widgets) |*w| {
        if (w.update_fn) |fn_ptr| fn_ptr(w);
    }
}

pub fn widgetListWidth(widgets: []Widget, h: i32, pad: i32) i32 {
    var total: i32 = 0;
    for (widgets) |*w| {
        const width = if (w.measure_fn) |fn_ptr| fn_ptr(w, h) else 0;
        w.cached_w = width;
        total += width + pad;
    }
    return total;
}

// ---- Config Loading ----

pub fn configLoadWidgets(allocator: std.mem.Allocator, path: []const u8) ?struct { widgets: [MAX_WIDGETS]Widget, count: i32 } {
    const data = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch return null;
    defer allocator.free(data);

    var result = struct { widgets: [MAX_WIDGETS]Widget, count: i32 }{
        .widgets = std.mem.zeroes([MAX_WIDGETS]Widget),
        .count = 0,
    };

    var lines = std.mem.splitScalar(u8, data, '\n');
    var cur_type: [64]u8 = std.mem.zeroes([64]u8);
    var opts_buf: [1024]u8 = std.mem.zeroes([1024]u8);
    var opts_len: usize = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (trimmed[0] == '[') {
            // Finalize previous section
            if (cur_type[0] != 0) {
                if (result.count < MAX_WIDGETS) {
                    const wtype = parseWidgetType(std.mem.sliceTo(&cur_type, 0));
                    if (wtype) |wt| {
                        result.widgets[@intCast(result.count)] = createWidget(wt);
                        result.count += 1;
                    }
                }
            }
            // Start new section
            const end = std.mem.indexOfScalar(u8, trimmed, ']') orelse continue;
            opts_len = 0;
            const type_name = trimmed[1..end];
            @memcpy(cur_type[0..@min(type_name.len, 63)], type_name[0..@min(type_name.len, 63)]);
            cur_type[@min(type_name.len, 63)] = 0;
        } else {
            // Accumulate options
            if (opts_len > 0 and opts_len < opts_buf.len - 1) {
                opts_buf[opts_len] = '\n';
                opts_len += 1;
            }
            const copy_len = @min(trimmed.len, opts_buf.len - opts_len - 1);
            @memcpy(opts_buf[opts_len .. opts_len + copy_len], trimmed[0..copy_len]);
            opts_len += copy_len;
            opts_buf[opts_len] = 0;
        }
    }

    // Finalize last section
    if (cur_type[0] != 0 and result.count < MAX_WIDGETS) {
        const wtype = parseWidgetType(std.mem.sliceTo(&cur_type, 0));
        if (wtype) |wt| {
            result.widgets[@intCast(result.count)] = createWidget(wt);
            result.count += 1;
        }
    }

    return result;
}

fn parseWidgetType(name: []const u8) ?WidgetType {
    const map = [_]struct { n: []const u8, t: WidgetType }{
        .{ .n = "workspaces", .t = .workspaces },
        .{ .n = "toplevel", .t = .toplevel_task },
        .{ .n = "launcher", .t = .launcher },
        .{ .n = "cpu", .t = .cpu },
        .{ .n = "mem", .t = .mem },
        .{ .n = "temp", .t = .temp },
        .{ .n = "disk", .t = .disk },
        .{ .n = "battery", .t = .battery },
        .{ .n = "volume", .t = .volume },
        .{ .n = "network", .t = .network },
        .{ .n = "media", .t = .media },
        .{ .n = "clock", .t = .clock },
        .{ .n = "power", .t = .power },
    };
    for (map) |entry| {
        if (std.mem.eql(u8, name, entry.n)) return entry.t;
    }
    return null;
}
