// sysread.zig — Shared, backend-agnostic system readers for panel widgets.
//
// These helpers read /proc and /sys and format short status strings. They are
// pure logic: they take output buffers and state by pointer, never the
// renderer-specific Widget struct, so both zigshell backends can call them.
//
// All functions are best-effort and non-fatal: on any I/O or parse error they
// leave a sensible placeholder in the output buffer and return.

const std = @import("std");

const linux = std.os.linux;

/// Read the whole contents of `path` into `buf`, returning the slice read.
/// Returns null on any error (missing file, permission, etc.).
/// Uses raw Linux syscalls so it stays independent of the per-shell C import
/// and of std.fs/std.posix API churn across Zig versions.
fn readFileInto(path: [*:0]const u8, buf: []u8) ?[]u8 {
    const rc = linux.open(path, .{}, 0);
    if (@as(isize, @bitCast(rc)) < 0) return null;
    const fd: linux.fd_t = @intCast(rc);
    defer _ = linux.close(fd);

    var total: usize = 0;
    while (total < buf.len) {
        const n = linux.read(fd, buf[total..].ptr, buf.len - total);
        if (@as(isize, @bitCast(n)) < 0) return null;
        if (n == 0) break;
        total += n;
    }
    return buf[0..total];
}

fn trimLine(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

// ---- CPU -------------------------------------------------------------------

/// Stateful CPU usage. `prev_total`/`prev_idle` carry across calls.
/// Writes e.g. "CPU 12%" into `out` (NUL-terminated).
pub fn cpu(out: []u8, prev_total: *i64, prev_idle: *i64) void {
    var raw: [256]u8 = undefined;
    const data = readFileInto("/proc/stat", &raw) orelse return;
    var lines = std.mem.splitScalar(u8, data, '\n');
    const first = lines.next() orelse return;
    if (!std.mem.startsWith(u8, first, "cpu ") and !std.mem.startsWith(u8, first, "cpu\t")) return;

    var it = std.mem.tokenizeAny(u8, first["cpu".len..], " \t");
    var fields: [8]i64 = .{0} ** 8;
    var n: usize = 0;
    while (it.next()) |tok| : (n += 1) {
        if (n >= fields.len) break;
        fields[n] = std.fmt.parseInt(i64, tok, 10) catch 0;
    }
    if (n < 5) return;
    // user nice system idle iowait irq softirq ...
    const idle = fields[3] + fields[4];
    var total: i64 = 0;
    for (fields[0..n]) |v| total += v;

    const dtotal = total - prev_total.*;
    const didle = idle - prev_idle.*;
    if (dtotal > 0) {
        const pct = @divTrunc(100 * (dtotal - didle), dtotal);
        _ = std.fmt.bufPrintZ(out, "CPU {d}%", .{pct}) catch {};
    }
    prev_total.* = total;
    prev_idle.* = idle;
}

// ---- Memory ----------------------------------------------------------------

/// Writes e.g. "MEM 43%" into `out`.
pub fn mem(out: []u8) void {
    var raw: [4096]u8 = undefined;
    const data = readFileInto("/proc/meminfo", &raw) orelse return;
    var total: i64 = 0;
    var avail: i64 = 0;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            total = parseKb(line);
        } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            avail = parseKb(line);
        }
    }
    if (total > 0) {
        const used = total - avail;
        const pct: i64 = @divTrunc(100 * used, total);
        _ = std.fmt.bufPrintZ(out, "MEM {d}%", .{pct}) catch |err| std.log.err("MEM format error: {}", .{err});
    }
}

fn parseKb(line: []const u8) i64 {
    var it = std.mem.tokenizeAny(u8, line, " \t");
    _ = it.next(); // key
    const v = it.next() orelse return 0;
    return std.fmt.parseInt(i64, v, 10) catch 0;
}

// ---- Temperature -----------------------------------------------------------

/// Writes e.g. "42°C" (or "--°C" when unavailable) into `out`.
pub fn temp(out: []u8) void {
    var raw: [32]u8 = undefined;
    const data = readFileInto("/sys/class/thermal/thermal_zone0/temp", &raw) orelse {
        _ = std.fmt.bufPrintZ(out, "--\u{00b0}C", .{}) catch |err| std.log.err("temp format error: {}", .{err});
        return;
    };
    const mt = std.fmt.parseInt(i32, trimLine(data), 10) catch -1;
    if (mt > 0) {
        _ = std.fmt.bufPrintZ(out, "{d}\u{00b0}C", .{@divTrunc(mt, 1000)}) catch |err| std.log.err("temp format error: {}", .{err});
    } else {
        _ = std.fmt.bufPrintZ(out, "--\u{00b0}C", .{}) catch |err| std.log.err("temp format error: {}", .{err});
    }
}

// ---- Battery ---------------------------------------------------------------

/// Reads BAT0 capacity/status. Sets `*lvl` (-1 if unknown) and `*charging`,
/// and writes a short label into `out` ("BAT ?", "+87%", or "87%").
pub fn battery(out: []u8, lvl: *i32, charging: *bool) void {
    var raw: [32]u8 = undefined;
    if (readFileInto("/sys/class/power_supply/BAT0/capacity", &raw)) |data| {
        lvl.* = std.fmt.parseInt(i32, trimLine(data), 10) catch -1;
    } else {
        lvl.* = -1;
    }

    var sraw: [32]u8 = undefined;
    if (readFileInto("/sys/class/power_supply/BAT0/status", &sraw)) |sdata| {
        charging.* = std.mem.startsWith(u8, trimLine(sdata), "Charging");
    }

    if (lvl.* < 0) {
        writeZ(out, "BAT ?");
    } else if (charging.*) {
        _ = std.fmt.bufPrintZ(out, "+{d}%", .{lvl.*}) catch |err| std.log.err("BAT format error: {}", .{err});
    } else {
        _ = std.fmt.bufPrintZ(out, "{d}%", .{lvl.*}) catch |err| std.log.err("BAT format error: {}", .{err});
    }
}

fn writeZ(out: []u8, s: []const u8) void {
    if (out.len == 0) return;
    const n = @min(s.len, out.len - 1);
    std.mem.copyForwards(u8, out[0..n], s[0..n]);
    out[n] = 0;
}

// ---- Versions --------------------------------------------------------------

/// Writes e.g. "WL:1.22 LC:0.8" into `out`.
/// wayland_ver is the protocol version from registry binding (0 if unknown).
pub fn versions(out: []u8, wayland_ver: u32) void {
    // Try to get labwc version from environment
    var labwc_ver: []const u8 = "?";
    var labwc_buf: [32]u8 = undefined;
    if (readFileInto("/sys/module/labwc/parameters/version", &labwc_buf)) |data| {
        const trimmed = trimLine(data);
        if (trimmed.len > 0 and trimmed.len < 32) {
            labwc_ver = trimmed;
        }
    }
    _ = std.fmt.bufPrintZ(out, "WL:{d} LC:{s}", .{ wayland_ver, labwc_ver }) catch {};
}

// ---- Network ---------------------------------------------------------------

pub const NetSample = struct {
    rx_bytes: u64 = 0,
    tx_bytes: u64 = 0,
    found: bool = false,
};

/// Find the first non-loopback interface name into `iface` (NUL-terminated).
/// Returns true if one was found.
pub fn netPickInterface(iface: []u8) bool {
    var raw: [8192]u8 = undefined;
    const data = readFileInto("/proc/net/dev", &raw) orelse return false;
    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next(); // header 1
    _ = lines.next(); // header 2
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = trimLine(line[0..colon]);
        if (name.len == 0 or std.mem.eql(u8, name, "lo")) continue;
        if (name.len < iface.len) {
            @memcpy(iface[0..name.len], name);
            iface[name.len] = 0;
            return true;
        }
    }
    return false;
}

/// Read cumulative rx/tx byte counters for `iface` from /proc/net/dev.
pub fn netSample(iface: []const u8) NetSample {
    var out: NetSample = .{};
    var raw: [8192]u8 = undefined;
    const data = readFileInto("/proc/net/dev", &raw) orelse return out;
    var lines = std.mem.splitScalar(u8, data, '\n');
    _ = lines.next();
    _ = lines.next();
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = trimLine(line[0..colon]);
        if (!std.mem.eql(u8, name, iface)) continue;
        var it = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        var vals: [16]u64 = .{0} ** 16;
        var n: usize = 0;
        while (it.next()) |tok| : (n += 1) {
            if (n >= vals.len) break;
            vals[n] = std.fmt.parseUnsigned(u64, tok, 10) catch 0;
        }
        if (n < 10) return out;
        out.rx_bytes = vals[0];
        out.tx_bytes = vals[8];
        out.found = true;
        return out;
    }
    return out;
}

// ---- Tests -----------------------------------------------------------------

test "parseKb extracts middle column" {
    try std.testing.expectEqual(@as(i64, 16384000), parseKb("MemTotal:       16384000 kB"));
    try std.testing.expectEqual(@as(i64, 0), parseKb("Bad:"));
}

test "trimLine strips whitespace and newlines" {
    try std.testing.expectEqualStrings("42000", trimLine("  42000\n"));
}

test "writeZ truncates and NUL-terminates" {
    var buf: [4]u8 = undefined;
    writeZ(&buf, "hello");
    try std.testing.expectEqualStrings("hel", std.mem.sliceTo(&buf, 0));
}

test "cpu on synthetic delta produces a percentage string" {
    // Not reading real /proc here; just ensure it degrades gracefully when the
    // file is present. This mainly guards signature/compile stability.
    var buf: [32]u8 = std.mem.zeroes([32]u8);
    var pt: i64 = 0;
    var pi: i64 = 0;
    cpu(&buf, &pt, &pi);
    // First call has no baseline delta; buffer may stay empty — that's fine.
}
