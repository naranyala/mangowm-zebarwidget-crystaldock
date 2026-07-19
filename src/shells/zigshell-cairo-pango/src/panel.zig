const std = @import("std");
const c = @import("c.zig").c;
const sysread = @import("shellcore").sysread;
const theme = @import("theme.zig");

pub const MAX_WIDGETS = 64;

/// Every widget type, used to populate the "Add Widget" menu in settings.
pub const AllWidgetTypes = [_]WidgetType{
    .workspaces,
    .launcher,
    .cpu,
    .mem,
    .temp,
    .disk,
    .battery,
    .volume,
    .network,
    .media,
    .clock,
    .power,
    .spacer,
    .kbindicator,
    .customcommand,
    .showdesktop,
    .worldclock,
    .backlight,
    .session,
    .versions,
    .settings,
};

const spawn_log = std.log.scoped(.spawn);

/// Run a shell command via c.system, logging a diagnostic when the shell
/// cannot be started or the command exits non-zero. Widget actions are
/// fire-and-forget (most append '&'), so we only surface failures — we never
/// block or propagate. Returns true when the command was launched cleanly.
fn spawn(cmd: [*c]const u8) bool {
    const rc = c.system(cmd);
    if (rc == -1) {
        spawn_log.err("failed to start shell for command: {s}", .{std.mem.sliceTo(cmd, 0)});
        return false;
    }
    if (rc != 0) {
        spawn_log.warn("command exited with status {d}: {s}", .{ rc, std.mem.sliceTo(cmd, 0) });
        return false;
    }
    return true;
}

/// Public wrapper around spawn() for firing shell commands from the shell core
/// (e.g. propagating font-scale changes to the rest of the system).
pub fn spawnCmd(cmd: [*c]const u8) bool {
    return spawn(cmd);
}

// ---- Widget System ----

pub const WidgetType = enum {
    workspaces,
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
    spacer,
    kbindicator,
    customcommand,
    showdesktop,
    wallpaper,
    worldclock,
    backlight,
    session,
    versions,
    settings,
};

pub const Widget = struct {
    wtype: WidgetType,
    side: u8, // 0 = left, 1 = right
    cached_w: i32,

    // measure: returns width needed (cr provided so text widgets can measure
    // real glyph widths instead of guessing — issue #18)
    measure_fn: ?*const fn (*Widget, i32, *c.cairo_t) i32 = null,
    // draw: render at (x, y) with height h
    draw_fn: ?*const fn (*Widget, *c.cairo_t, i32, i32, i32) void = null,
    // update: refresh data from system
    update_fn: ?*const fn (*Widget) void = null,
    // click: handle click, return true if consumed
    click_fn: ?*const fn (*Widget, u32, i32, i32) bool = null,
    // key: handle key press, return true if consumed
    key_fn: ?*const fn (*Widget, u32, u32) bool = null,
    // scroll: handle scroll event (dir: 1 for up, -1 for down), return true if consumed
    scroll_fn: ?*const fn (*Widget, i32) bool = null,

    // Private data
    priv: ?*anyopaque = null,

    // Workspaces
    ws_labels: [64]u8 = std.mem.zeroes([64]u8),

    // CPU (i64 to avoid overflow panic on long-running systems — issue #28)
    cpu_prev_total: i64 = 0,
    cpu_prev_idle: i64 = 0,
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

    // Spacer
    spacer_w: i32 = 20,

    // Keyboard layout indicator
    kb_layouts: [256]u8 = std.mem.zeroes([256]u8),
    kb_idx: i32 = 0,
    kb_txt: [32]u8 = std.mem.zeroes([32]u8),

    // Custom command
    cc_out: [128]u8 = std.mem.zeroes([128]u8),

    // World clock
    wc_tz: [64]u8 = std.mem.zeroes([64]u8),
    wc_label: [16]u8 = std.mem.zeroes([16]u8),

    // Backlight
    bl_lvl: i32 = -1,

    // Versions (wayland + compositor)
    ver_txt: [32]u8 = std.mem.zeroes([32]u8),

    // Network monitor
    net_rx_prev: u64 = 0,
    net_tx_prev: u64 = 0,
    net_iface: [32]u8 = std.mem.zeroes([32]u8),
    net_hist_rx: [16]f64 = std.mem.zeroes([16]f64),
    net_hist_tx: [16]f64 = std.mem.zeroes([16]f64),
    net_retry_tick: u32 = 0,

    // Per-day bandwidth tracker (resets at midnight)
    net_day_rx: u64 = 0,
    net_day_tx: u64 = 0,
    net_hist_day_rx: [7]u64 = .{0} ** 7,
    net_hist_day_tx: [7]u64 = .{0} ** 7,
    net_day_idx: i64 = -1, // (tm_year * 366 + tm_yday) last checked
    net_save_tick: u32 = 0,

    // Visibility — when true the widget is omitted from the bar but still
    // listed (and reorderable) in the settings panel.
    hidden: bool = false,
};

// ---- Text Rendering Helpers ----

pub fn widgetText(cr: *c.cairo_t, text: [*:0]const u8, x: i32, h: i32, font_desc: [*:0]const u8, r: f64, g: f64, b: f64) i32 {
    return c.widget_text_c(cr, text, x, h, font_desc, r, g, b);
}

/// Measure the rendered pixel width of `text` in `font_desc` (no painting).
/// Used by measure functions so allocated widths match actual drawn glyphs
/// (issue #18).
pub fn widgetTextWidth(cr: *c.cairo_t, text: [*:0]const u8, font_desc: [*:0]const u8) i32 {
    return c.widget_text_width_c(cr, text, font_desc);
}

pub fn widgetIconGlyph(cr: *c.cairo_t, glyph: [*:0]const u8, x: i32, h: i32, r: f64, g: f64, b: f64) void {
    c.widget_icon_glyph_c(cr, glyph, x, h, r, g, b);
}

/// Set the global panel font-scale factor (1.0 = no scaling). Applied to every
/// text glyph painted by the panel so the whole bar rescales together with
/// labwc/GTK/Qt (see scripts/font-scale.sh).
pub fn setFontScale(scale: f64) void {
    c.widget_set_font_scale(scale);
}

// ---- Widget Measure/Draw Functions ----

fn wsMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    // Measure the actual rendered width so allocation matches what wsDraw
    // paints (issue #18). Falls back to a rough estimate if measuring fails.
    const labels = @as([*:0]const u8, @ptrCast(&w.ws_labels));
    const wpx = widgetTextWidth(cr, labels, "Sans 10");
    if (wpx > 0) return wpx + 8;
    const len = std.mem.indexOfScalar(u8, &w.ws_labels, 0) orelse w.ws_labels.len;
    return @intCast(len * 7 + 8);
}

fn wsDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    _ = widgetText(cr, @ptrCast(&w.ws_labels), x, h, "Sans 10", theme.current.text_dim_color[0], theme.current.text_dim_color[1], theme.current.text_dim_color[2]);
}

fn wsClick(w: *Widget, btn: u32, lx: i32, _: i32) bool {
    if (btn != 1) return false;
    // Count workspace labels (digits in ws_labels)
    var ws_count: i32 = 0;
    for (w.ws_labels) |ch| {
        if (ch >= '1' and ch <= '9') ws_count += 1;
    }
    if (ws_count == 0) return false;

    // Estimate workspace width from label string (Sans 10 ≈ 7px/char)
    const label_len = std.mem.indexOfScalar(u8, &w.ws_labels, 0) orelse w.ws_labels.len;
    const total_w = @as(i32, @intCast(label_len)) * 7 + 8;
    const ws_w = @divTrunc(total_w, ws_count);
    const ws_idx = @divTrunc(lx, ws_w);
    const target = @max(1, @min(ws_idx + 1, ws_count));

    // Switch to the clicked workspace
    var cmd: [48]u8 = std.mem.zeroes([48]u8);
    _ = std.fmt.bufPrintZ(&cmd, "wlrctl workgroup focus {d}", .{target}) catch return false;
    _ = spawn(@ptrCast(&cmd));
    return true;
}

fn launcherMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    _ = w;
    const wpx = widgetTextWidth(cr, "zigshell-cairo-pango", "Sans Bold 11");
    if (wpx > 0) return wpx + 8;
    return 150;
}

fn launcherDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = w;
    _ = y;
    _ = widgetText(cr, "zigshell-cairo-pango", x + 4, h, "Sans Bold 11", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn launcherClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = x;
    _ = y;
    if (btn != 272) return false;
    // Launch the command (fuzzel by default)
    _ = spawn(@ptrCast(&w.cmd));
    return true;
}

fn cpuUpdate(w: *Widget) void {
    var pt: i64 = w.cpu_prev_total;
    var pi: i64 = w.cpu_prev_idle;
    sysread.cpu(&w.cpu_txt, &pt, &pi);
    w.cpu_prev_total = pt;
    w.cpu_prev_idle = pi;
}

fn cpuMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    // Measure the 60px bar + text width for accurate layout
    const wpx = widgetTextWidth(cr, @ptrCast(&w.cpu_txt), "Sans Bold 9");
    if (wpx > 0) return @max(60, wpx + 8);
    return 60;
}

fn cpuDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    const bar_w: f64 = 60.0;
    const bar_h: f64 = @floatFromInt(h - 16);
    const bar_y: f64 = @floatFromInt(y + 8);
    theme.setSource(cr, theme.current.bg_gradient_end);
    c.cairo_rectangle(cr, @floatFromInt(x), bar_y, bar_w, bar_h);
    c.cairo_fill(cr);

    var pct: f64 = 0;
    if (c.sscanf(&w.cpu_txt, "CPU %lf%%", &pct) == 1) {
        const fill_w = bar_w * pct / 100.0;
        if (pct < 50.0) {
            theme.setSource(cr, theme.current.success_color);
        } else if (pct < 80.0) {
            theme.setSource(cr, theme.current.warning_color);
        } else {
            theme.setSource(cr, theme.current.danger_color);
        }
        c.cairo_rectangle(cr, @floatFromInt(x), bar_y, fill_w, bar_h);
        c.cairo_fill(cr);
    }
    
    _ = widgetText(cr, @ptrCast(&w.cpu_txt), x + 4, h, "Sans Bold 9", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn cpuClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 272) return false;
    _ = spawn("foot btop &");
    return true;
}

fn memUpdate(w: *Widget) void {
    sysread.mem(&w.mem_txt);
}

fn memMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    // Measure the 70px bar + text width for accurate layout
    const wpx = widgetTextWidth(cr, @ptrCast(&w.mem_txt), "Sans Bold 9");
    if (wpx > 0) return @max(70, wpx + 8);
    return 70;
}

fn memDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    const bar_w: f64 = 70.0;
    const bar_h: f64 = @floatFromInt(h - 16);
    const bar_y: f64 = @floatFromInt(y + 8);
    
    theme.setSource(cr, theme.current.bg_gradient_end);
    c.cairo_rectangle(cr, @floatFromInt(x), bar_y, bar_w, bar_h);
    c.cairo_fill(cr);

    var pct: f64 = 0;
    if (c.sscanf(&w.mem_txt, "MEM %lf%%", &pct) == 1) {
        const fill_w = bar_w * pct / 100.0;
        theme.setSource(cr, theme.current.accent_color);
        c.cairo_rectangle(cr, @floatFromInt(x), bar_y, fill_w, bar_h);
        c.cairo_fill(cr);
    }
    
    _ = widgetText(cr, @ptrCast(&w.mem_txt), x + 4, h, "Sans Bold 9", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn memClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 272) return false;
    _ = spawn("foot htop &");
    return true;
}

fn tempUpdate(w: *Widget) void {
    sysread.temp(&w.temp_txt);
}

fn tempMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    // Measure glyph icon (16px) + text width for accurate layout
    const wpx = widgetTextWidth(cr, @ptrCast(&w.temp_txt), "Sans 9");
    if (wpx > 0) return wpx + 18;
    return 56;
}

fn tempDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "♨", x, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
    _ = widgetText(cr, @ptrCast(&w.temp_txt), x + 16, h, "Sans 9", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn tempClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 272) return false;
    _ = spawn("foot sensors &");
    return true;
}

fn diskMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    // Measure glyph icon (16px) + text width for accurate layout
    const wpx = widgetTextWidth(cr, @ptrCast(&w.disk_txt), "Sans 9");
    if (wpx > 0) return wpx + 18;
    return 64;
}

fn diskDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "▥", x, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
    _ = widgetText(cr, @ptrCast(&w.disk_txt), x + 16, h, "Sans 9", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn diskClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 272) return false;
    _ = spawn("pcmanfm-qt &");
    return true;
}

fn batMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    // Battery icon (24px) + text width for accurate layout
    const wpx = widgetTextWidth(cr, @ptrCast(&w.bat_txt), "Sans 9");
    if (wpx > 0) return wpx + 32;
    return 64;
}

fn batDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    const bat_w: f64 = 24.0;
    const bat_h: f64 = 14.0;
    const bat_y: f64 = @floatFromInt(y + @divTrunc(h - 14, 2));

    // Outline
    theme.setSource(cr, theme.current.border_color);
    c.cairo_set_line_width(cr, 1.5);
    c.cairo_rectangle(cr, @as(f64, @floatFromInt(x)), bat_y, bat_w, bat_h);
    c.cairo_stroke(cr);

    // Nub
    c.cairo_rectangle(cr, @as(f64, @floatFromInt(x)) + bat_w, bat_y + 4.0, 2.0, bat_h - 8.0);
    c.cairo_fill(cr);

    if (w.bat_lvl >= 0) {
        const fill_w = (bat_w - 4.0) * @as(f64, @floatFromInt(w.bat_lvl)) / 100.0;
        if (w.bat_charging) {
            // Charging: pulsing green (brighter than normal success)
            c.cairo_set_source_rgb(cr, 0.2, 0.9, 0.4);
        } else if (w.bat_lvl > 50) {
            theme.setSource(cr, theme.current.success_color);
        } else if (w.bat_lvl > 20) {
            theme.setSource(cr, theme.current.warning_color);
        } else {
            theme.setSource(cr, theme.current.danger_color);
        }
        c.cairo_rectangle(cr, @as(f64, @floatFromInt(x)) + 2.0, bat_y + 2.0, fill_w, bat_h - 4.0);
        c.cairo_fill(cr);
    }

    // Charging indicator: small lightning bolt when charging
    if (w.bat_charging) {
        widgetIconGlyph(cr, "⚡", x + @as(i32, @intFromFloat(bat_w)) + 4, h, 0.9, 0.8, 0.2);
    }

    _ = widgetText(cr, @ptrCast(&w.bat_txt), x + 30, h, "Sans 9", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn batUpdate(w: *Widget) void {
    sysread.battery(&w.bat_txt, &w.bat_lvl, &w.bat_charging);
}

fn batClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 272) return false;
    _ = spawn("foot upower -i /org/freedesktop/UPower/devices/battery_BAT0 &");
    return true;
}

fn volMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    // Icon glyph (18px) + text width for accurate layout
    const wpx = widgetTextWidth(cr, @ptrCast(&w.vol_txt), "Sans 9");
    if (wpx > 0) return wpx + 20;
    return 64;
}

fn volDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, if (w.vol_mute) "🔇" else "🔊", x, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
    _ = widgetText(cr, @ptrCast(&w.vol_txt), x + 18, h, "Sans 9", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn volClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = x;
    _ = y;
    if (btn != 272) return false;
    if (w.vol_mute) {
        _ = spawn("pactl set-sink-mute @DEFAULT_SINK@ 0 &");
    } else {
        _ = spawn("pactl set-sink-mute @DEFAULT_SINK@ 1 &");
    }
    return true;
}

// P3: reflect the real sink volume/mute so the widget isn't stuck at the
// default until first click. pactl may be absent (e.g. PipeWire via wpctl);
// failures silently keep the previous state.
fn volUpdate(w: *Widget) void {
    var mute: [16]u8 = std.mem.zeroes([16]u8);
    if (captureCmd("pactl get-sink-mute 2>/dev/null || wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null", &mute) > 0) {
        const m = std.mem.sliceTo(&mute, 0);
        w.vol_mute = std.mem.indexOf(u8, m, "yes") != null or std.mem.indexOf(u8, m, "[MUTED]") != null;
    }
    var vol: [32]u8 = std.mem.zeroes([32]u8);
    if (captureCmd("pactl get-sink-volume 2>/dev/null || wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null", &vol) > 0) {
        const v = std.mem.sliceTo(&vol, 0);
        // Try pactl format first (e.g. "69%").
        var it = std.mem.tokenizeAny(u8, v, " /%");
        var found: u32 = 0;
        while (it.next()) |tok| {
            if (std.fmt.parseUnsigned(u32, tok, 10)) |pct| {
                if (pct <= 150) {
                    found = pct;
                    break;
                }
            } else |_| {}
        }
        // If pactl format gave 0, try wpctl fraction format (e.g. "0.45" → 45%).
        if (found == 0) {
            if (std.mem.indexOfScalar(u8, v, '.')) |_| {
                var fit = std.mem.tokenizeScalar(u8, v, ' ');
                while (fit.next()) |tok| {
                    if (std.fmt.parseFloat(f64, tok)) |frac| {
                        if (frac > 0 and frac <= 1.0) {
                            found = @intFromFloat(frac * 100.0);
                            break;
                        }
                    } else |_| {}
                }
            }
        }
        if (found > 0 and found <= 150) {
            _ = std.fmt.bufPrintZ(&w.vol_txt, "{d}%", .{found}) catch {};
        }
    }
}

fn volScroll(w: *Widget, dir: i32) bool {
    _ = w;
    if (dir > 0) {
        _ = spawn("pactl set-sink-volume @DEFAULT_SINK@ +5% &");
    } else if (dir < 0) {
        _ = spawn("pactl set-sink-volume @DEFAULT_SINK@ -5% &");
    }
    return true;
}

fn netMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    // Sparkline (56) + gap + text (measured) + padding
    const wpx = widgetTextWidth(cr, @ptrCast(&w.net_txt), "Sans 8");
    if (wpx > 0) return @max(wpx + 80, 80);
    const len = std.mem.indexOfScalar(u8, &w.net_txt, 0) orelse w.net_txt.len;
    return @intCast(@max(@as(i32, @intCast(len)) * 5 + 80, 80));
}

fn netUpdate(w: *Widget) void {
    if (w.net_iface[0] == 0) {
        w.net_retry_tick +%= 1;
        if (w.net_retry_tick > 0 and w.net_retry_tick % 30 != 0) return;
        if (!sysread.netPickInterface(&w.net_iface)) return;
    }
    const sample = sysread.netSample(std.mem.sliceTo(&w.net_iface, 0));
    if (!sample.found) return;

    const rx = sample.rx_bytes;
    const tx = sample.tx_bytes;

    // --- Per-day bandwidth tracker: init/rollover ---
    const t = c.time(null);
    var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
    _ = c.localtime_r(&t, &tm);
    const day_idx = @as(i64, tm.tm_year) * 366 + @as(i64, tm.tm_yday);

    if (w.net_day_idx == -1) {
        loadNetBandwidth(w);
        if (w.net_day_idx != -1 and w.net_day_idx != day_idx) {
            const days_gap = @as(u64, @intCast(day_idx - w.net_day_idx));
            if (days_gap >= 7) {
                w.net_hist_day_rx = .{0} ** 7;
                w.net_hist_day_tx = .{0} ** 7;
            } else if (w.net_day_idx != -1) {
                var si: u64 = 0;
                while (si < 7 - days_gap) : (si += 1) {
                    w.net_hist_day_rx[si] = w.net_hist_day_rx[si + days_gap];
                    w.net_hist_day_tx[si] = w.net_hist_day_tx[si + days_gap];
                }
                while (si < 7) : (si += 1) {
                    w.net_hist_day_rx[si] = 0;
                    w.net_hist_day_tx[si] = 0;
                }
            }
            w.net_day_rx = 0;
            w.net_day_tx = 0;
        }
        w.net_day_idx = day_idx;
    } else if (day_idx != w.net_day_idx) {
        var si: usize = 0;
        while (si < 6) : (si += 1) {
            w.net_hist_day_rx[si] = w.net_hist_day_rx[si + 1];
            w.net_hist_day_tx[si] = w.net_hist_day_tx[si + 1];
        }
        w.net_hist_day_rx[6] = w.net_day_rx;
        w.net_hist_day_tx[6] = w.net_day_tx;
        w.net_day_rx = 0;
        w.net_day_tx = 0;
        w.net_day_idx = day_idx;
    }

    if (w.net_rx_prev == 0) {
        w.net_rx_prev = rx;
        w.net_tx_prev = tx;
        return;
    }
    const drx = rx -% w.net_rx_prev;
    const dtx = tx -% w.net_tx_prev;
    const rx_kb = @as(f64, @floatFromInt(drx)) / 1024.0;
    const tx_kb = @as(f64, @floatFromInt(dtx)) / 1024.0;
    var k: usize = 0;
    while (k < 15) : (k += 1) {
        w.net_hist_rx[k] = w.net_hist_rx[k + 1];
        w.net_hist_tx[k] = w.net_hist_tx[k + 1];
    }
    w.net_hist_rx[15] = rx_kb;
    w.net_hist_tx[15] = tx_kb;

    // Accumulate into daily totals (wrapping-safe; reset at midnight).
    w.net_day_rx +%= drx;
    w.net_day_tx +%= dtx;

    // Persist every ~60 ticks.
    w.net_save_tick +%= 1;
    if (w.net_save_tick % 60 == 0) saveNetBandwidth(w);

    // Build net_txt: rate + daily Dn/Up + weekly total.
    _ = std.fmt.bufPrintZ(&w.net_txt, "{d:.0}/{d:.0}  ", .{ rx_kb, tx_kb }) catch |err| {
        std.log.err("net text format error: {}", .{err});
        return;
    };
    const pos = std.mem.indexOfScalar(u8, &w.net_txt, 0) orelse w.net_txt.len;

    var day_buf: [24]u8 = undefined;
    var wk_buf: [24]u8 = undefined;
    const drx_str = formatBytes(w.net_day_rx, &day_buf);
    const dtx_str = formatBytes(w.net_day_tx, day_buf[drx_str.len..]);

    var wk_total: u64 = 0;
    for (w.net_hist_day_rx) |v| wk_total +%= v;
    for (w.net_hist_day_tx) |v| wk_total +%= v;
    const wk_str = formatBytes(wk_total +% w.net_day_rx +% w.net_day_tx, &wk_buf);

    @memset(w.net_txt[pos..], 0);
    _ = std.fmt.bufPrint(w.net_txt[pos..], "D:{s}\u{2193}{s}\u{2191} W:{s}", .{ drx_str, dtx_str, wk_str }) catch {};

    w.net_rx_prev = rx;
    w.net_tx_prev = tx;
}

fn formatBytes(bytes: u64, buf: []u8) []u8 {
    const units = [_][]const u8{ "B", "K", "M", "G", "T" };
    if (bytes == 0) {
        if (buf.len > 0) buf[0] = '0';
        return buf[0..1];
    }
    var v: f64 = @floatFromInt(bytes);
    var ui: usize = 0;
    while (v >= 1024.0 and ui < units.len - 1) : (ui += 1) v /= 1024.0;
    if (ui == 0) {
        _ = std.fmt.bufPrint(buf, "{d}B", .{bytes}) catch return buf[0..0];
    } else if (v < 10.0) {
        _ = std.fmt.bufPrint(buf, "{d:.1}{s}", .{ v, units[ui] }) catch return buf[0..0];
    } else {
        _ = std.fmt.bufPrint(buf, "{d:.0}{s}", .{ v, units[ui] }) catch return buf[0..0];
    }
    return std.mem.sliceTo(buf, 0);
}

fn getNetBandwidthPathOut(out: *[256]u8) []u8 {
    if (c.getenv("XDG_CONFIG_HOME")) |x| {
        const dir = std.mem.sliceTo(x, 0);
        _ = std.fmt.bufPrintZ(out, "{s}/zigshell/netbandwidth.dat", .{dir}) catch return out[0..0];
    } else {
        const home_raw = c.getenv("HOME");
        const home = if (home_raw != null) std.mem.sliceTo(home_raw.?, 0) else "/tmp";
        _ = std.fmt.bufPrintZ(out, "{s}/.config/zigshell/netbandwidth.dat", .{home}) catch return out[0..0];
    }
    return out;
}

fn saveNetBandwidth(w: *Widget) void {
    var pbuf: [256]u8 = std.mem.zeroes([256]u8);
    _ = getNetBandwidthPathOut(&pbuf);
    const f = c.fopen(@as([*:0]const u8, @ptrCast(&pbuf)), "wb") orelse return;
    defer _ = c.fclose(f);
    const magic: u32 = 0x4E455442;
    const ver: u32 = 1;
    _ = c.fwrite(@as(*const anyopaque, @ptrCast(&magic)), 4, 1, f);
    _ = c.fwrite(@as(*const anyopaque, @ptrCast(&ver)), 4, 1, f);
    _ = c.fwrite(@as(*const anyopaque, @ptrCast(&w.net_day_rx)), 8, 1, f);
    _ = c.fwrite(@as(*const anyopaque, @ptrCast(&w.net_day_tx)), 8, 1, f);
    _ = c.fwrite(@as(*const anyopaque, @ptrCast(&w.net_hist_day_rx)), 8, 7, f);
    _ = c.fwrite(@as(*const anyopaque, @ptrCast(&w.net_hist_day_tx)), 8, 7, f);
    _ = c.fwrite(@as(*const anyopaque, @ptrCast(&w.net_day_idx)), 8, 1, f);
}

fn loadNetBandwidth(w: *Widget) void {
    var pbuf: [256]u8 = std.mem.zeroes([256]u8);
    _ = getNetBandwidthPathOut(&pbuf);
    const f = c.fopen(@as([*:0]const u8, @ptrCast(&pbuf)), "rb") orelse return;
    defer _ = c.fclose(f);
    var magic: u32 = 0;
    var ver: u32 = 0;
    if (c.fread(@as(*anyopaque, @ptrCast(&magic)), 4, 1, f) != 1) return;
    if (c.fread(@as(*anyopaque, @ptrCast(&ver)), 4, 1, f) != 1) return;
    if (magic != 0x4E455442 or ver != 1) return;
    _ = c.fread(@as(*anyopaque, @ptrCast(&w.net_day_rx)), 8, 1, f);
    _ = c.fread(@as(*anyopaque, @ptrCast(&w.net_day_tx)), 8, 1, f);
    _ = c.fread(@as(*anyopaque, @ptrCast(&w.net_hist_day_rx)), 8, 7, f);
    _ = c.fread(@as(*anyopaque, @ptrCast(&w.net_hist_day_tx)), 8, 7, f);
    _ = c.fread(@as(*anyopaque, @ptrCast(&w.net_day_idx)), 8, 1, f);
}

fn netDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "📶", x, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);

    // Sparkline of rx (top) and tx (bottom)
    const sp_x = x + 18;
    const sp_w: f64 = 56.0;
    const sp_h: f64 = @floatFromInt(@max(h - 18, 1));
    const sp_y: f64 = @floatFromInt(@divTrunc(h - 18, 2) + 2);

    var maxv: f64 = 1.0;
    for (w.net_hist_rx) |v| maxv = @max(maxv, v);
    for (w.net_hist_tx) |v| maxv = @max(maxv, v);

    const bw = sp_w / 16.0;
    var k: usize = 0;
    while (k < 16) : (k += 1) {
        const rxh = (w.net_hist_rx[k] / maxv) * sp_h * 0.5;
        const txh = (w.net_hist_tx[k] / maxv) * sp_h * 0.5;
        theme.setSource(cr, theme.current.success_color);
        c.cairo_rectangle(cr, @as(f64, @floatFromInt(sp_x)) + @as(f64, @floatFromInt(k)) * bw, sp_y, bw - 1, rxh);
        c.cairo_fill(cr);
        theme.setSource(cr, theme.current.accent_color);
        c.cairo_rectangle(cr, @as(f64, @floatFromInt(sp_x)) + @as(f64, @floatFromInt(k)) * bw, sp_y + sp_h * 0.5, bw - 1, txh);
        c.cairo_fill(cr);
    }

    _ = widgetText(cr, @ptrCast(&w.net_txt), x + 80, h, "Sans 8", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn netClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 272) return false;
    _ = spawn("nm-applet &");
    return true;
}

fn mediaMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    if (w.media_txt[0] == 0) return 0;
    const wpx = widgetTextWidth(cr, @ptrCast(&w.media_txt), "Sans 9");
    if (wpx > 0) return wpx + 20;
    const len = std.mem.indexOfScalar(u8, &w.media_txt, 0) orelse w.media_txt.len;
    return @intCast(len * 6 + 20);
}

fn mediaDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    if (w.media_txt[0] == 0) return;
    widgetIconGlyph(cr, if (w.media_playing) "▶" else "❚❚", x, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
    _ = widgetText(cr, @ptrCast(&w.media_txt), x + 18, h, "Sans 9", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn mediaClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 272) return false;
    _ = spawn("playerctl play-pause &");
    return true;
}

// P1: poll MPRIS via playerctl so the widget shows the current track/artist
// instead of staying empty. Runs from widgetListUpdate (1s tick); playerctl may
// be absent, so failures silently leave the widget empty.
fn mediaUpdate(w: *Widget) void {
    var status: [32]u8 = std.mem.zeroes([32]u8);
    var title: [64]u8 = std.mem.zeroes([64]u8);
    var artist: [64]u8 = std.mem.zeroes([64]u8);
    _ = captureCmd("playerctl status 2>/dev/null", &status);
    _ = captureCmd("playerctl metadata xesam:title 2>/dev/null", &title);
    _ = captureCmd("playerctl metadata xesam:artist 2>/dev/null", &artist);
    w.media_playing = std.mem.eql(u8, std.mem.sliceTo(&status, 0), "Playing");
    if (title[0] == 0) {
        w.media_txt[0] = 0;
        return;
    }
    const t = std.mem.sliceTo(&title, 0);
    const a = std.mem.sliceTo(&artist, 0);
    const written = if (a.len > 0)
        std.fmt.bufPrint(&w.media_txt, "{s} - {s}", .{ a, t })
    else
        std.fmt.bufPrint(&w.media_txt, "{s}", .{t});
    if (written) |txt| {
        w.media_txt[txt.len] = 0;
    } else |_| {
        @memcpy(&w.media_txt, t.ptr);
        w.media_txt[t.len] = 0;
    }
}

// Run a command, capture its stdout first line into `out` (NUL-terminated).
// Reuses the temp-file pattern from ccUpdate (issue #19 hardening). Returns the
// number of bytes written (excluding NUL), or 0 on failure.
fn captureCmd(cmd: []const u8, out: []u8) usize {
    var tmpl: [32]u8 = std.mem.zeroes([32]u8);
    _ = std.fmt.bufPrintZ(&tmpl, "/tmp/.zigshell-cap-XXXXXX", .{}) catch return 0;
    const fd = c.mkstemp(@ptrCast(&tmpl));
    if (fd < 0) return 0;
    _ = c.fchmod(fd, 0o600);
    _ = c.close(fd);
    var escaped_cmd: [256]u8 = undefined;
    var e_idx: usize = 0;
    for (cmd) |ch| {
        if (e_idx >= escaped_cmd.len - 4) break;
        if (ch == '\'') {
            @memcpy(escaped_cmd[e_idx..e_idx+4], "'\\''");
            e_idx += 4;
        } else {
            escaped_cmd[e_idx] = ch;
            e_idx += 1;
        }
    }
    const escaped_slice = escaped_cmd[0..e_idx];

    var full: [384]u8 = std.mem.zeroes([384]u8);
    const full_slice = std.fmt.bufPrintZ(&full, "sh -c '{s}' > '{s}' 2>/dev/null", .{ escaped_slice, std.mem.sliceTo(&tmpl, 0) }) catch {
        _ = c.unlink(@ptrCast(&tmpl));
        return 0;
    };
    _ = spawn(@ptrCast(&full_slice));
    const f = c.fopen(@ptrCast(&tmpl), "r") orelse {
        _ = c.unlink(@ptrCast(&tmpl));
        return 0;
    };
    defer {
        _ = c.fclose(f);
        _ = c.unlink(@ptrCast(&tmpl));
    }
    var buf: [256]u8 = std.mem.zeroes([256]u8);
    if (c.fgets(@ptrCast(&buf), buf.len, f)) |line| {
        const raw = std.mem.sliceTo(line, 0);
        var end = raw.len;
        while (end > 0 and (raw[end - 1] == '\n' or raw[end - 1] == '\r')) : (end -= 1) {}
        const n = @min(end, out.len - 1);
        @memcpy(out[0..n], raw[0..n]);
        out[n] = 0;
        return n;
    }
    return 0;
}

fn clkMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    const wpx = widgetTextWidth(cr, @ptrCast(&w.clock_txt), "Sans 10");
    if (wpx > 0) return wpx + 16;
    const len = std.mem.indexOfScalar(u8, &w.clock_txt, 0) orelse w.clock_txt.len;
    return @intCast(len * 7 + 16);
}

fn clkDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    _ = widgetText(cr, @ptrCast(&w.clock_txt), x, h, "Sans 10", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

pub var request_calendar_modal: bool = false;

/// Wayland protocol version discovered during registry binding.
/// Set by main_shell.zig after roundtrip; read by versionsUpdate.
pub var global_wayland_ver: u32 = 0;

fn clkClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 272) return false;
    request_calendar_modal = true;
    return true;
}

fn pwrMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = cr;
    _ = w;
    _ = h;
    return 22;
}

fn pwrDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = w;
    _ = y;
    widgetIconGlyph(cr, "⏻", x + 4, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn pwrClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = x;
    _ = y;
    if (btn != 272) return false;
    _ = spawn(@ptrCast(&w.cmd));
    return true;
}

// Global toggle for the session-action popup, owned by the widget module so both
// the session widget's click_fn and the main shell (which draws/handles the
// popup) can read and flip it without a circular dependency.
pub var session_open: bool = false;

fn sessionMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = w;
    _ = h;
    _ = cr;
    return 22;
}

fn sessionDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = w;
    _ = y;
    const c_open = session_open;
    if (c_open) {
        widgetIconGlyph(cr, "⏻", x + 4, h, theme.current.warning_color[0], theme.current.warning_color[1], theme.current.warning_color[2]);
    } else {
        widgetIconGlyph(cr, "⏻", x + 4, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
    }
}

fn sessionClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn != 272) return false;
    session_open = true;
    return true;
}

// ---- Settings gear widget (always-present gear icon) ----
// The main shell checks request_settings_modal after widget dispatch (like
// request_calendar_modal) so there is no circular import.
pub var request_settings_modal: bool = false;

fn settingsMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = w;
    _ = h;
    _ = cr;
    return 28;
}

fn settingsDraw(_: *Widget, cr: *c.cairo_t, x: i32, _: i32, h: i32) void {
    // Small background pill so the gear stands out as a button
    c.cairo_set_source_rgba(cr, 0.3, 0.3, 0.35, 0.8);
    c.cairo_rectangle(cr, @floatFromInt(x), 0, 28, @floatFromInt(h));
    c.cairo_fill(cr);

    widgetIconGlyph(cr, "⚙", x + 4, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn settingsClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn == 3) {
        request_settings_modal = true;
        return true;
    }
    if (btn == 272) {
        // Left-click: launch the GTK settings app (out of process).
        _ = spawn("zigshell-settings-gtk &");
        return true;
    }
    return false;
}

fn wallpaperMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = w;
    _ = h;
    _ = cr;
    return 28;
}

fn wallpaperDraw(_: *Widget, cr: *c.cairo_t, x: i32, _: i32, h: i32) void {
    c.cairo_set_source_rgba(cr, 0.2, 0.5, 0.8, 0.8);
    c.cairo_rectangle(cr, @floatFromInt(x), 0, 28, @floatFromInt(h));
    c.cairo_fill(cr);

    widgetIconGlyph(cr, "🖼", x + 4, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn wallpaperWorker() void {
    const filters = [_][*:0]const u8{ "*.png", "*.jpg", "*.jpeg", "*.webp" };
    const res = c.tinyfd_openFileDialog(
        "Select Wallpaper",
        "",
        4,
        @ptrCast(&filters),
        "Image files",
        0,
    );
    if (res != null) {
        var cmd: [1024]u8 = undefined;
        _ = std.fmt.bufPrintZ(&cmd, "$HOME/dotfiles/wallpaper set '{s}'", .{std.mem.span(res)}) catch return;
        _ = spawnCmd(@ptrCast(&cmd));
    }
}

fn wallpaperClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = btn;
    _ = x;
    _ = y;
    const thread = std.Thread.spawn(.{}, wallpaperWorker, .{}) catch return true;
    thread.detach();
    return true;
}

// ---- Versions widget (wayland + labwc) ----

fn versionsMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    const wpx = widgetTextWidth(cr, @ptrCast(&w.ver_txt), "Sans 9");
    if (wpx > 0) return wpx + 8;
    return 80; // Fixed width fallback for "WL:1.26.90 LC:0.8.0"
}

fn versionsDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    // Display wayland and labwc versions (P2/P8: own buffer, real data)
    const text = w.ver_txt[0..std.mem.indexOfScalar(u8, &w.ver_txt, 0) orelse w.ver_txt.len];
    _ = widgetText(cr, @ptrCast(text.ptr), x, h, "Sans 9", theme.current.text_dim_color[0], theme.current.text_dim_color[1], theme.current.text_dim_color[2]);
}

fn versionsUpdate(w: *Widget) void {
    if (w.ver_txt[0] != 0) return;
    var buf: [256]u8 = std.mem.zeroes([256]u8);
    if (captureCmd("labwc --version", &buf) == 0) {
        _ = std.fmt.bufPrintZ(&w.ver_txt, "LC:? WR:?", .{}) catch {};
        return;
    }
    const line = std.mem.sliceTo(&buf, 0);
    var lv: []const u8 = "?";
    var wv: []const u8 = "?";
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next(); // "labwc"
    if (it.next()) |tok| lv = tok;
    // find "wlroots-" in remaining tokens
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "wlroots-")) {
            wv = tok["wlroots-".len..];
        }
    }
    _ = std.fmt.bufPrintZ(&w.ver_txt, "LC:{s} WR:{s}", .{ lv, wv }) catch {};
}

fn versionsClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    _ = btn;
    return false;
}

// ===== New widgets extracted from lxqt-panel plugins =====

// ---- Spacer (plugin-spacer) ----
fn spacerMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = cr;
    _ = h;
    return w.spacer_w;
}

fn spacerDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = w;
    _ = cr;
    _ = x;
    _ = y;
    _ = h;
}

fn spacerClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = btn;
    _ = x;
    _ = y;
    return false;
}

// ---- Keyboard layout indicator (plugin-kbindicator) ----
fn kbMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = cr;
    _ = h;
    const len = std.mem.indexOfScalar(u8, &w.kb_txt, 0) orelse w.kb_txt.len;
    return @intCast(len * 8 + 12);
}

fn kbUpdate(w: *Widget) void {
    // P7: detect externally-selected layout (e.g. set via another tool) by
    // parsing `setxkbmap -query`'s `layout:` line, and align kb_idx to it when
    // it matches one of our configured layouts. Falls back to the last
    // self-selected index if setxkbmap is absent or reports something unknown.
    var qbuf: [256]u8 = std.mem.zeroes([256]u8);
    if (captureCmd("setxkbmap -query 2>/dev/null", &qbuf) > 0) {
        const q = std.mem.sliceTo(&qbuf, 0);
        if (std.mem.indexOf(u8, q, "layout:")) |pos| {
            const rest = q[pos + "layout:".len ..];
            const eol = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            var cur = std.mem.trim(u8, rest[0..eol], " \t");
            if (std.mem.indexOfScalar(u8, cur, ',')) |comma| cur = cur[0..comma];
            var seg: usize = 0;
            var seg_start: usize = 0;
            var si: usize = 0;
            while (si < w.kb_layouts.len) : (si += 1) {
                if (w.kb_layouts[si] == ',') {
                    const lay = std.mem.trim(u8, w.kb_layouts[seg_start..si], " \t");
                    if (lay.len > 0 and std.mem.eql(u8, cur, lay)) {
                        w.kb_idx = @intCast(seg);
                        break;
                    }
                    seg += 1;
                    seg_start = si + 1;
                }
            }
            // Also check final segment (after last comma).
            if (seg_start < w.kb_layouts.len) {
                const lay = std.mem.trim(u8, w.kb_layouts[seg_start..], " \t");
                if (lay.len > 0 and std.mem.eql(u8, cur, lay)) {
                    w.kb_idx = @intCast(seg);
                }
            }
        }
    }

    // Show the layout at kb_idx.
    var i: usize = 0;
    var seg: usize = 0;
    var seg_start: usize = 0;
    while (i < w.kb_layouts.len) : (i += 1) {
        if (w.kb_layouts[i] == ',') {
            if (seg == @as(usize, @intCast(w.kb_idx))) {
                const slice = w.kb_layouts[seg_start..i];
                const n = @min(slice.len, w.kb_txt.len - 1);
                @memcpy(w.kb_txt[0..n], slice[0..n]);
                w.kb_txt[n] = 0;
                return;
            }
            seg += 1;
            seg_start = i + 1;
        }
    }
    // Final segment (after last comma).
    if (seg == @as(usize, @intCast(w.kb_idx)) and seg_start < w.kb_layouts.len) {
        const slice = w.kb_layouts[seg_start..];
        const n = @min(slice.len, w.kb_txt.len - 1);
        @memcpy(w.kb_txt[0..n], slice[0..n]);
        w.kb_txt[n] = 0;
        return;
    }
    std.mem.copyForwards(u8, &w.kb_txt, "??");
}

fn kbDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    widgetIconGlyph(cr, "⌨", x, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
    _ = widgetText(cr, @ptrCast(&w.kb_txt), x + 18, h, "Sans Bold 10", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn kbClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = x;
    _ = y;
    if (btn != 272) return false;
    // Count layouts
    var count: i32 = 1;
    for (w.kb_layouts) |ch| {
        if (ch == ',') count += 1;
    }
    w.kb_idx = @mod(w.kb_idx + 1, count);
    kbUpdate(w);
    var layout: [64]u8 = std.mem.zeroes([64]u8);
    const n = std.mem.indexOfScalar(u8, &w.kb_txt, 0) orelse w.kb_txt.len;
    @memcpy(layout[0..n], w.kb_txt[0..n]);
    layout[n] = 0;
    var cmd: [128]u8 = std.mem.zeroes([128]u8);
    _ = std.fmt.bufPrintZ(&cmd, "setxkbmap -layout {s} &", .{std.mem.sliceTo(&layout, 0)}) catch |err| {
        std.log.err("layout cmd format error: {}", .{err});
    };
    _ = spawn(@ptrCast(&cmd));
    return true;
}

// ---- Custom command (plugin-customcommand) ----
fn ccMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = cr;
    _ = h;
    const len = std.mem.indexOfScalar(u8, &w.cc_out, 0) orelse w.cc_out.len;
    return @intCast(len * 7 + 12);
}

fn ccUpdate(w: *Widget) void {
    const cmd_slice = std.mem.sliceTo(&w.cmd, 0);
    // Run command and capture first line of stdout into cc_out.
    // Use captureCmd which is C-based and avoids Zig std process issues.
    var buf: [256]u8 = std.mem.zeroes([256]u8);
    _ = captureCmd(cmd_slice, &buf);
    const raw = std.mem.sliceTo(&buf, 0);
    var end = raw.len;
    while (end > 0 and (raw[end - 1] == '\n' or raw[end - 1] == '\r')) : (end -= 1) {}
    const trimmed = raw[0..end];
    const n = @min(trimmed.len, w.cc_out.len - 1);
    @memcpy(w.cc_out[0..n], trimmed[0..n]);
    w.cc_out[n] = 0;
}

fn ccDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    if (w.cc_out[0] == 0) return;
    _ = widgetText(cr, @ptrCast(&w.cc_out), x, h, "Sans 9", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn ccClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = x;
    _ = y;
    if (btn != 272) return false;
    ccUpdate(w);
    return true;
}

// ---- Show Desktop (plugin-showdesktop) ----
fn sdMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = cr;
    _ = w;
    _ = h;
    return 22;
}

fn sdDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = w;
    _ = y;
    widgetIconGlyph(cr, "▣", x + 4, h, theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn sdClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = x;
    _ = y;
    if (btn != 272) return false;
    _ = spawn(@ptrCast(&w.cmd));
    return true;
}

// ---- World clock (plugin-worldclock) ----
fn wcMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = h;
    // Measure label + clock text widths for accurate layout
    const lbl_w = widgetTextWidth(cr, @ptrCast(&w.wc_label), "Sans Bold 9");
    const clk_w = widgetTextWidth(cr, @ptrCast(&w.clock_txt), "Sans 10");
    if (lbl_w > 0 and clk_w > 0) return lbl_w + clk_w + 28;
    const lbl_len = std.mem.indexOfScalar(u8, &w.wc_label, 0) orelse w.wc_label.len;
    return @intCast(lbl_len * 7 + 56);
}

fn wcUpdate(w: *Widget) void {
    const old = c.getenv("TZ");
    var old_buf: [64]u8 = std.mem.zeroes([64]u8);
    var had_old = false;
    if (old) |o| {
        const os = std.mem.sliceTo(o, 0);
        const n = @min(os.len, old_buf.len - 1);
        @memcpy(old_buf[0..n], os[0..n]);
        old_buf[n] = 0;
        had_old = true;
    }
    _ = c.setenv("TZ", @ptrCast(&w.wc_tz), 1);
    c.tzset();
    const now = c.time(null);
    var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
    _ = c.localtime_r(&now, &tm);
    _ = c.strftime(&w.clock_txt, w.clock_txt.len, "%H:%M", &tm);
    if (had_old) {
        _ = c.setenv("TZ", @ptrCast(&old_buf), 1);
    } else {
        _ = c.unsetenv("TZ");
    }
    c.tzset();
}

fn wcDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    _ = y;
    _ = widgetText(cr, @ptrCast(&w.wc_label), x, h, "Sans Bold 9", theme.current.text_dim_color[0], theme.current.text_dim_color[1], theme.current.text_dim_color[2]);
    _ = widgetText(cr, @ptrCast(&w.clock_txt), x + 28, h, "Sans 10", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

// ---- Backlight (plugin-backlight) ----
fn blMeasure(w: *Widget, h: i32, cr: *c.cairo_t) i32 {
    _ = cr;
    _ = w;
    _ = h;
    return 64;
}

fn blUpdate(w: *Widget) void {
    // Locate first backlight device under /sys/class/backlight
    const dir = c.opendir("/sys/class/backlight") orelse {
        w.bl_lvl = -1;
        return;
    };
    defer _ = c.closedir(dir);
    var ent: ?*c.struct_dirent = null;
    var chosen: [256]u8 = std.mem.zeroes([256]u8);
    var chosen_len: usize = 0;
    while (true) {
        ent = c.readdir(dir);
        if (ent == null) break;
        const dname = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(@alignCast(&ent.?.d_name[0]))), 0);
        if (dname.len == 0 or std.mem.eql(u8, dname, ".") or std.mem.eql(u8, dname, "..")) continue;
        const n = @min(dname.len, chosen.len - 32);
        @memcpy(chosen[0..n], dname[0..n]);
        chosen_len = n;
        break;
    }
    if (chosen_len == 0) {
        w.bl_lvl = -1;
        return;
    }
    var path: [320]u8 = std.mem.zeroes([320]u8);
    _ = std.fmt.bufPrintZ(&path, "/sys/class/backlight/{s}/brightness", .{chosen[0..chosen_len]}) catch |err| {
        std.log.err("bl path format error: {}", .{err});
        w.bl_lvl = -1;
        return;
    };
    const fb = c.fopen(@ptrCast(&path), "r") orelse {
        w.bl_lvl = -1;
        return;
    };
    defer _ = c.fclose(fb);
    var cur: i32 = 0;
    _ = c.fscanf(fb, "%d", &cur);

    _ = std.fmt.bufPrintZ(&path, "/sys/class/backlight/{s}/max_brightness", .{chosen[0..chosen_len]}) catch |err| {
        std.log.err("bl max path format error: {}", .{err});
        w.bl_lvl = -1;
        return;
    };
    const fm = c.fopen(@ptrCast(&path), "r") orelse {
        w.bl_lvl = -1;
        return;
    };
    defer _ = c.fclose(fm);
    var maxv: i32 = 0;
    _ = c.fscanf(fm, "%d", &maxv);

    if (maxv > 0) {
        w.bl_lvl = @divTrunc(100 * cur, maxv);
    } else {
        w.bl_lvl = -1;
    }
}

fn blDraw(w: *Widget, cr: *c.cairo_t, x: i32, y: i32, h: i32) void {
    widgetIconGlyph(cr, "☀", x, h, theme.current.warning_color[0], theme.current.warning_color[1], theme.current.warning_color[2]);
    const bar_w: f64 = 26.0;
    const bar_h: f64 = 10.0;
    const bar_y: f64 = @floatFromInt(y + @divTrunc(h - 10, 2));
    theme.setSource(cr, theme.current.bg_gradient_end);
    c.cairo_rectangle(cr, @floatFromInt(x + 18), bar_y, bar_w, bar_h);
    c.cairo_fill(cr);
    if (w.bl_lvl >= 0) {
        const fill_w = (bar_w - 2.0) * @as(f64, @floatFromInt(w.bl_lvl)) / 100.0;
        theme.setSource(cr, theme.current.warning_color);
        c.cairo_rectangle(cr, @floatFromInt(x + 19), bar_y + 1, fill_w, bar_h - 2);
        c.cairo_fill(cr);
    }
    var txt: [16]u8 = std.mem.zeroes([16]u8);
    if (w.bl_lvl >= 0) {
        _ = std.fmt.bufPrintZ(&txt, "{d}%", .{w.bl_lvl}) catch |err| {
            std.log.err("bl txt format error: {}", .{err});
        };
    } else {
        std.mem.copyForwards(u8, &txt, "n/a");
    }
    _ = widgetText(cr, @ptrCast(&txt), x + 48, h, "Sans 9", theme.current.text_color[0], theme.current.text_color[1], theme.current.text_color[2]);
}

fn blClick(w: *Widget, btn: u32, x: i32, y: i32) bool {
    _ = w;
    _ = x;
    _ = y;
    if (btn == 272) {
        _ = spawn("brightnessctl set +5% &");
    } else if (btn == 3) {
        _ = spawn("brightnessctl set 5%- &");
    } else {
        return false;
    }
    return true;
}

fn blScroll(w: *Widget, dir: i32) bool {
    _ = w;
    if (dir > 0) {
        _ = spawn("brightnessctl set +5% &");
    } else if (dir < 0) {
        _ = spawn("brightnessctl set 5%- &");
    }
    return true;
}

// ---- Widget Creation ----

pub const WidgetList = struct {
    widgets: *[MAX_WIDGETS]Widget,
    count: *i32,
};

pub fn widgetCreateDefault(out: *[MAX_WIDGETS]Widget) i32 {
    // Default: essential widgets on each side. Additional widgets (temp, disk,
    // network, media, world clock, backlight, etc.) remain available via the
    // config file but are omitted from the default bar to keep it slim.
    const defaults = [_]struct { wtype: WidgetType, side: u8 }{
        .{ .wtype = .workspaces, .side = 0 },
        .{ .wtype = .versions, .side = 0 },
        .{ .wtype = .cpu, .side = 1 },
        .{ .wtype = .mem, .side = 1 },
        .{ .wtype = .battery, .side = 1 },
        .{ .wtype = .volume, .side = 1 },
        .{ .wtype = .clock, .side = 1 },
        .{ .wtype = .session, .side = 1 },
        .{ .wtype = .wallpaper, .side = 1 },
        .{ .wtype = .settings, .side = 1 },
    };

    for (defaults, 0..) |d, i| {
        out[i] = createWidget(d.wtype);
        out[i].side = d.side;
    }

    return @intCast(defaults.len);
}

pub fn widgetCreateCompact(out: *[MAX_WIDGETS]Widget) i32 {
    // Compact layout: only essential widgets
    // Left: workspaces + launcher
    // Right: clock + battery + volume + network
    const compact = [_]struct { wtype: WidgetType, side: u8 }{
        .{ .wtype = .workspaces, .side = 0 },
        .{ .wtype = .launcher, .side = 0 },
        .{ .wtype = .clock, .side = 1 },
        .{ .wtype = .battery, .side = 1 },
        .{ .wtype = .volume, .side = 1 },
        .{ .wtype = .network, .side = 1 },
        .{ .wtype = .settings, .side = 1 },
    };

    for (compact, 0..) |d, i| {
        out[i] = createWidget(d.wtype);
        out[i].side = d.side;
    }

    return @intCast(compact.len);
}

pub fn createWidget(wtype: WidgetType) Widget {
    var w: Widget = std.mem.zeroes(Widget);
    w.wtype = wtype;
    w.bat_lvl = -1;
    w.bl_lvl = -1;

    switch (wtype) {
        .workspaces => {
            std.mem.copyForwards(u8, &w.ws_labels, " 1 2 3 4 ");
            w.measure_fn = wsMeasure;
            w.draw_fn = wsDraw;
            w.click_fn = wsClick;
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
            w.click_fn = cpuClick;
        },
        .mem => {
            std.mem.copyForwards(u8, &w.mem_txt, "MEM --");
            w.measure_fn = memMeasure;
            w.draw_fn = memDraw;
            w.update_fn = memUpdate;
            w.click_fn = memClick;
        },
        .temp => {
            std.mem.copyForwards(u8, &w.temp_txt, "--\xc2\xb0C");
            w.measure_fn = tempMeasure;
            w.draw_fn = tempDraw;
            w.update_fn = tempUpdate;
            w.click_fn = tempClick;
        },
        .disk => {
            std.mem.copyForwards(u8, &w.disk_txt, "SSD --");
            w.measure_fn = diskMeasure;
            w.draw_fn = diskDraw;
            w.click_fn = diskClick;
        },
        .battery => {
            std.mem.copyForwards(u8, &w.bat_txt, "BAT ?");
            w.measure_fn = batMeasure;
            w.draw_fn = batDraw;
            w.click_fn = batClick;
            w.update_fn = batUpdate;
        },
        .volume => {
            w.measure_fn = volMeasure;
            w.draw_fn = volDraw;
            w.click_fn = volClick;
            w.update_fn = volUpdate;
        },
        .network => {
            std.mem.copyForwards(u8, &w.net_txt, "-- KB/s");
            w.measure_fn = netMeasure;
            w.draw_fn = netDraw;
            w.click_fn = netClick;
            w.update_fn = netUpdate;
        },
        .media => {
            w.measure_fn = mediaMeasure;
            w.draw_fn = mediaDraw;
            w.click_fn = mediaClick;
            w.update_fn = mediaUpdate;
        },
        .clock => {
            std.mem.copyForwards(u8, &w.clock_fmt, "%H:%M");
            w.measure_fn = clkMeasure;
            w.draw_fn = clkDraw;
            w.update_fn = clkUpdate;
            w.click_fn = clkClick;
        },
        .power => {
            std.mem.copyForwards(u8, &w.cmd, "loginctl poweroff &");
            w.measure_fn = pwrMeasure;
            w.draw_fn = pwrDraw;
            w.click_fn = pwrClick;
        },
        .session => {
            w.measure_fn = sessionMeasure;
            w.draw_fn = sessionDraw;
            w.click_fn = sessionClick;
        },
        .versions => {
            std.mem.copyForwards(u8, &w.ver_txt, "WL:? LC:?");
            w.measure_fn = versionsMeasure;
            w.draw_fn = versionsDraw;
            w.update_fn = versionsUpdate;
            w.click_fn = versionsClick;
        },
        .spacer => {
            w.spacer_w = 20;
            w.measure_fn = spacerMeasure;
            w.draw_fn = spacerDraw;
            w.click_fn = spacerClick;
        },
        .kbindicator => {
            std.mem.copyForwards(u8, &w.kb_layouts, "us,ru");
            w.kb_idx = 0;
            std.mem.copyForwards(u8, &w.kb_txt, "us");
            w.measure_fn = kbMeasure;
            w.draw_fn = kbDraw;
            w.update_fn = kbUpdate;
            w.click_fn = kbClick;
        },
        .customcommand => {
            std.mem.copyForwards(u8, &w.cmd, "date +%H:%M:%S");
            w.measure_fn = ccMeasure;
            w.draw_fn = ccDraw;
            w.update_fn = ccUpdate;
            w.click_fn = ccClick;
        },
        .showdesktop => {
            std.mem.copyForwards(u8, &w.cmd, "wlrctl window minimize all &");
            w.measure_fn = sdMeasure;
            w.draw_fn = sdDraw;
            w.click_fn = sdClick;
        },
        .worldclock => {
            std.mem.copyForwards(u8, &w.wc_tz, "America/New_York");
            std.mem.copyForwards(u8, &w.wc_label, "NYC");
            w.measure_fn = wcMeasure;
            w.draw_fn = wcDraw;
            w.update_fn = wcUpdate;
        },
        .backlight => {
            w.measure_fn = blMeasure;
            w.draw_fn = blDraw;
            w.update_fn = blUpdate;
            w.click_fn = blClick;
            w.scroll_fn = blScroll;
        },
        .settings => {
            w.measure_fn = settingsMeasure;
            w.draw_fn = settingsDraw;
            w.click_fn = settingsClick;
        },
        .wallpaper => {
            w.measure_fn = wallpaperMeasure;
            w.draw_fn = wallpaperDraw;
            w.click_fn = wallpaperClick;
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
        if (w.hidden) continue;
        if (w.update_fn) |fn_ptr| fn_ptr(w);
    }
}

pub fn widgetListWidth(widgets: []Widget, h: i32, pad: i32, cr: *c.cairo_t) i32 {
    var total: i32 = 0;
    for (widgets) |*w| {
        if (w.hidden) {
            w.cached_w = 0;
            continue;
        }
        const width = if (w.measure_fn) |fn_ptr| fn_ptr(w, h, cr) else 0;
        w.cached_w = width;
        total += width + pad;
    }
    return total;
}

/// Append a new widget of `wtype` to a WidgetList (used by the settings
/// "Add Widget" menu). No-op if the list is full.
pub fn widgetListAdd(list: *WidgetList, wtype: WidgetType) void {
    const n = list.count.*;
    if (n >= MAX_WIDGETS) return;
    list.widgets[@intCast(n)] = createWidget(wtype);
    list.count.* = n + 1;
}

/// Remove the widget at `idx`, shifting the rest down.
pub fn widgetListRemoveAt(list: *WidgetList, idx: i32) void {
    const n = list.count.*;
    if (idx < 0 or idx >= n) return;
    var i = idx;
    while (i < n - 1) : (i += 1) {
        list.widgets[@intCast(i)] = list.widgets[@intCast(i + 1)];
    }
    list.count.* = n - 1;
}

/// Move the widget at `idx` by `dir` (-1 = up, +1 = down), clamped.
pub fn widgetListMove(list: *WidgetList, idx: i32, dir: i32) void {
    const n = list.count.*;
    if (idx < 0 or idx >= n) return;
    const j = idx + dir;
    if (j < 0 or j >= n) return;
    const tmp = list.widgets[@intCast(idx)];
    list.widgets[@intCast(idx)] = list.widgets[@intCast(j)];
    list.widgets[@intCast(j)] = tmp;
}

/// Toggle the visibility of the widget at `idx`. Returns the new hidden state.
pub fn widgetListToggleHidden(list: *WidgetList, idx: i32) bool {
    if (idx < 0 or idx >= list.count.*) return false;
    list.widgets[@intCast(idx)].hidden = !list.widgets[@intCast(idx)].hidden;
    return list.widgets[@intCast(idx)].hidden;
}

/// True if the widget at `idx` is hidden.
pub fn widgetListIsHidden(list: *WidgetList, idx: i32) bool {
    if (idx < 0 or idx >= list.count.*) return false;
    return list.widgets[@intCast(idx)].hidden;
}

/// Human-readable name for a widget type (used in the settings UI).
pub fn widgetTypeName(wt: WidgetType) []const u8 {
    return switch (wt) {
        .workspaces => "Workspaces",
        .launcher => "Launcher",
        .cpu => "CPU",
        .mem => "Memory",
        .temp => "Temperature",
        .disk => "Disk",
        .battery => "Battery",
        .volume => "Volume",
        .network => "Network",
        .media => "Media",
        .clock => "Clock",
        .power => "Power",
        .spacer => "Spacer",
        .kbindicator => "Keyboard",
        .customcommand => "Command",
        .showdesktop => "Show Desktop",
        .worldclock => "World Clock",
        .backlight => "Backlight",
        .session => "Session",
        .versions => "Versions",
        .settings => "Settings",
        .wallpaper => "Wallpaper",
    };
}

// ---- Config Loading ----

pub const LoadedWidgets = struct {
    widgets: [MAX_WIDGETS]Widget,
    count: i32,
};

pub fn configLoadWidgets(allocator: std.mem.Allocator, path: []const u8) ?LoadedWidgets {
    const path_z = allocator.dupeZ(u8, path) catch |err| {
        std.log.err("allocator dupeZ error: {}", .{err});
        return null;
    };
    defer allocator.free(path_z);
    const f = c.fopen(path_z, "r") orelse return null;
    defer _ = c.fclose(f);

    var result: LoadedWidgets = .{
        .widgets = std.mem.zeroes([MAX_WIDGETS]Widget),
        .count = 0,
    };

    var cur_type: [64]u8 = std.mem.zeroes([64]u8);
    var opts_buf: [1024]u8 = std.mem.zeroes([1024]u8);
    var opts_len: usize = 0;

    var line_buf: [1024]u8 = std.mem.zeroes([1024]u8);
    while (c.fgets(&line_buf, line_buf.len, f) != null) {
        const trimmed = std.mem.trimStart(u8, std.mem.sliceTo(&line_buf, 0), " \t\r");
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

pub fn parseWidgetType(name: []const u8) ?WidgetType {
    const map = [_]struct { n: []const u8, t: WidgetType }{
        .{ .n = "workspaces", .t = .workspaces },
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
        .{ .n = "wallpaper", .t = .wallpaper },
        .{ .n = "spacer", .t = .spacer },
        .{ .n = "kbindicator", .t = .kbindicator },
        .{ .n = "customcommand", .t = .customcommand },
        .{ .n = "showdesktop", .t = .showdesktop },
        .{ .n = "worldclock", .t = .worldclock },
        .{ .n = "backlight", .t = .backlight },
        .{ .n = "session", .t = .session },
        .{ .n = "versions", .t = .versions },
        .{ .n = "settings", .t = .settings },
    };
    for (map) |entry| {
        if (std.mem.eql(u8, name, entry.n)) return entry.t;
    }
    return null;
}

test "panel parseWidgetType" {
    try std.testing.expectEqual(WidgetType.clock, parseWidgetType("clock").?);
    try std.testing.expectEqual(WidgetType.cpu, parseWidgetType("cpu").?);
    try std.testing.expectEqual(@as(?WidgetType, null), parseWidgetType("unknown"));
}

test "widgetListToggleHidden flips visibility" {
    var list: [MAX_WIDGETS]Widget = undefined;
    var count: i32 = 0;
    var wl = WidgetList{ .widgets = &list, .count = &count };
    widgetListAdd(&wl, .cpu);
    widgetListAdd(&wl, .clock);
    try std.testing.expect(!widgetListIsHidden(&wl, 0));
    // Hide the first widget.
    try std.testing.expect(widgetListToggleHidden(&wl, 0));
    try std.testing.expect(widgetListIsHidden(&wl, 0));
    // Unhide it again.
    try std.testing.expect(!widgetListToggleHidden(&wl, 0));
    try std.testing.expect(!widgetListIsHidden(&wl, 0));
    // Out-of-range indices are safe no-ops.
    try std.testing.expect(!widgetListToggleHidden(&wl, 99));
}

test "widgetListWidth skips hidden widgets" {
    var list: [MAX_WIDGETS]Widget = undefined;
    var count: i32 = 0;
    var wl = WidgetList{ .widgets = &list, .count = &count };
    // Use a trivial measure fn (no cairo deref) so the test needs no cr.
    const measure = struct {
        fn f(_: *Widget, _: i32, _: *c.cairo_t) i32 {
            return 40;
        }
    }.f;
    widgetListAdd(&wl, .cpu);
    widgetListAdd(&wl, .clock);
    list[0].measure_fn = measure;
    list[1].measure_fn = measure;
    const full = widgetListWidth(list[0..@as(usize, @intCast(count))], 24, 8, undefined);
    // Hide one and remeasure — total must drop.
    _ = widgetListToggleHidden(&wl, 0);
    const hidden_one = widgetListWidth(list[0..@as(usize, @intCast(count))], 24, 8, undefined);
    try std.testing.expect(hidden_one < full);
    try std.testing.expectEqual(@as(i32, 96), full); // 2 * (40 + 8)
}

test "configLoadWidgets parses sections" {
    const path = "/tmp/zigshell_test_config.ini";
    const f = c.fopen(path, "w") orelse return;
    defer {
        _ = c.fclose(f);
        _ = c.remove(path);
    }
    _ = c.fputs("[cpu]\n[clock]\n[spacer]\n[unknown_skip]\n", f);
    _ = c.fflush(f);
    const res = configLoadWidgets(std.testing.allocator, path) orelse return;
    // Unknown sections are skipped; valid ones are created.
    try std.testing.expect(res.count >= 3);
    try std.testing.expectEqual(WidgetType.cpu, res.widgets[0].wtype);
    try std.testing.expectEqual(WidgetType.clock, res.widgets[1].wtype);
    try std.testing.expectEqual(WidgetType.spacer, res.widgets[2].wtype);
}


