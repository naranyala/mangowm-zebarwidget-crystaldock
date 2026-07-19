// apps.zig — Shared application catalog for the launcher.
//
// Discovers launchable entries from two sources:
//   1. .desktop files in the standard XDG application directories.
//   2. Globally available executables found by walking $PATH.
//
// The result is a flat, de-duplicated list of `AppEntry` values that both the
// cairo-pango and blend2d shells render inside the floating launcher panel.
//
// Uses a minimal C import (dirent/stdlib) so it has no dependency on the
// host shell's Wayland C bindings.

const std = @import("std");
const apps_log = std.log.scoped(.apps);

const c = @cImport({
    @cInclude("dirent.h");
    @cInclude("sys/stat.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("stdio.h");
});

pub const AppEntry = struct {
    name: [128]u8,
    name_len: usize,
    exec: [256]u8,
    exec_len: usize,
    icon: [128]u8,
    icon_len: usize,
    // true when sourced from a .desktop file, false for a bare executable.
    from_desktop: bool,
};

pub const MAX_APPS = 512;

var apps: [MAX_APPS]AppEntry = std.mem.zeroes([MAX_APPS]AppEntry);
var app_count: usize = 0;
var scanned: bool = false;

const desktop_dirs = [_][]const u8{
    "/usr/share/applications/",
    "/usr/local/share/applications/",
    "/var/lib/flatpak/exports/share/applications/",
    "/.local/share/flatpak/exports/share/applications/",
    "/.local/share/applications/",
};

fn addEntry(name: []const u8, exec: []const u8, icon: []const u8, from_desktop: bool) void {
    if (app_count >= MAX_APPS) return;
    if (name.len == 0) return;

    // De-duplicate by name (first occurrence wins).
    for (0..app_count) |i| {
        const e = &apps[i];
        if (std.mem.eql(u8, e.name[0..e.name_len], name)) return;
    }

    const idx: usize = app_count;
    app_count += 1;
    const e = &apps[idx];
    const nlen = @min(name.len, e.name.len - 1);
    @memcpy(e.name[0..nlen], name[0..nlen]);
    e.name[nlen] = 0;
    e.name_len = nlen;
    const elen = @min(exec.len, e.exec.len - 1);
    @memcpy(e.exec[0..elen], exec[0..elen]);
    e.exec[elen] = 0;
    e.exec_len = elen;
    const ilen = @min(icon.len, e.icon.len - 1);
    @memcpy(e.icon[0..ilen], icon[0..ilen]);
    e.icon[ilen] = 0;
    e.icon_len = ilen;
    e.from_desktop = from_desktop;
}

fn trimNewline(s: []const u8) []const u8 {
    var end = s.len;
    while (end > 0 and (s[end - 1] == '\n' or s[end - 1] == '\r')) end -= 1;
    return s[0..end];
}

fn stripFieldCode(exec: []const u8, out: []u8) []const u8 {
    // Remove common .desktop field codes like %f, %F, %u, %U, %i, %c, %k, %%.
    var olen: usize = 0;
    var i: usize = 0;
    while (i < exec.len) {
        const ch = exec[i];
        if (ch == '%' and i + 1 < exec.len) {
            const n = exec[i + 1];
            if (n == '%') {
                if (olen < out.len) {
                    out[olen] = '%';
                    olen += 1;
                }
                i += 2;
                continue;
            }
            // Skip the whole token until whitespace.
            i += 1;
            while (i < exec.len and exec[i] != ' ' and exec[i] != '\t') i += 1;
            
            // If the preceding char was a space, and we skipped a % code,
            // we remove the preceding space from the output so we don't leave double spaces.
            if (olen > 0 and (out[olen - 1] == ' ' or out[olen - 1] == '\t')) {
                olen -= 1;
            }
            continue;
        }
        if (olen < out.len) {
            out[olen] = ch;
            olen += 1;
        }
        i += 1;
    }
    // Trim any trailing whitespace (not just newlines)
    while (olen > 0 and (out[olen - 1] == ' ' or out[olen - 1] == '\t' or out[olen - 1] == '\n' or out[olen - 1] == '\r')) {
        olen -= 1;
    }
    return out[0..olen];
}

fn parseDesktopFile(path: [*:0]const u8) void {
    const file = c.fopen(path, "r") orelse {
        apps_log.debug("skipping unreadable .desktop file: {s}", .{std.mem.sliceTo(path, 0)});
        return;
    };
    defer _ = c.fclose(file);

    var buf: [4096]u8 = std.mem.zeroes([4096]u8);
    const read = c.fread(@ptrCast(&buf), 1, buf.len, file);
    const content = buf[0..read];

    var in_desktop_entry = false;
    var name: [128]u8 = std.mem.zeroes([128]u8);
    var name_len: usize = 0;
    var exec: [256]u8 = std.mem.zeroes([256]u8);
    var exec_len: usize = 0;
    var icon: [128]u8 = std.mem.zeroes([128]u8);
    var icon_len: usize = 0;
    var no_display = false;

    var line_it = std.mem.splitScalar(u8, content, '\n');
    while (line_it.next()) |raw_line| {
        const line = trimNewline(raw_line);
        if (line.len == 0) continue;
        if (line[0] == '[') {
            in_desktop_entry = std.mem.eql(u8, line, "[Desktop Entry]");
            continue;
        }
        if (!in_desktop_entry) continue;

        if (std.mem.startsWith(u8, line, "Name=")) {
            const v = line[5..];
            name_len = @min(v.len, name.len - 1);
            @memcpy(name[0..name_len], v[0..name_len]);
        } else if (std.mem.startsWith(u8, line, "Exec=")) {
            const v = stripFieldCode(line[5..], exec[0..]);
            exec_len = v.len;
        } else if (std.mem.startsWith(u8, line, "Icon=")) {
            const v = line[5..];
            icon_len = @min(v.len, icon.len - 1);
            @memcpy(icon[0..icon_len], v[0..icon_len]);
        } else if (std.mem.startsWith(u8, line, "NoDisplay=")) {
            const v = line[10..];
            if (std.mem.eql(u8, v, "true")) no_display = true;
        } else if (std.mem.startsWith(u8, line, "Hidden=")) {
            const v = line[7..];
            if (std.mem.eql(u8, v, "true")) no_display = true;
        }
    }

    if (no_display) return;
    if (name_len == 0 or exec_len == 0) return;
    addEntry(name[0..name_len], exec[0..exec_len], icon[0..icon_len], true);
}

fn scanDesktopDirs() void {
    for (desktop_dirs) |dir| {
        const d = c.opendir(dir.ptr) orelse continue;
        defer _ = c.closedir(d);
        while (true) {
            const ent = c.readdir(d) orelse break;
            const name_slice = entryName(ent[0]);
            if (!std.mem.endsWith(u8, name_slice, ".desktop")) continue;
            var full: [1024]u8 = std.mem.zeroes([1024]u8);
            const total = dir.len + name_slice.len;
            if (total >= full.len) continue; // path too long, skip
            @memcpy(full[0..dir.len], dir);
            @memcpy(full[dir.len .. dir.len + name_slice.len], name_slice);
            full[dir.len + name_slice.len] = 0;
            parseDesktopFile(@ptrCast(&full));
        }
    }
}

fn isExecutable(mode: c.mode_t) bool {
    return (mode & 0o111) != 0;
}

/// Extract a `[]const u8` name from a `struct dirent` entry.
fn entryName(ent: anytype) []const u8 {
    const name_ptr: [*]const u8 = @ptrCast(&ent.d_name);
    var n: usize = 0;
    while (name_ptr[n] != 0 and n < ent.d_name.len) : (n += 1) {}
    return name_ptr[0..n];
}

fn scanPath() void {
    const path_env = c.getenv("PATH") orelse {
        apps_log.warn("PATH is unset; $PATH executables will not appear in the launcher", .{});
        return;
    };
    const path_str = std.mem.span(path_env);
    var comps = std.mem.splitScalar(u8, path_str, ':');
    while (comps.next()) |dir_str| {
        if (dir_str.len == 0) continue;
        const d = c.opendir(dir_str.ptr) orelse continue;
        defer _ = c.closedir(d);
        while (true) {
            const ent = c.readdir(d) orelse break;
            const name_slice = entryName(ent[0]);
            if (name_slice.len == 0) continue;
            // Stat to confirm it is an executable regular file.
            var st: c.struct_stat = std.mem.zeroes(c.struct_stat);
            var full: [1024]u8 = std.mem.zeroes([1024]u8);
            @memcpy(full[0..dir_str.len], dir_str);
            full[dir_str.len] = '/';
            @memcpy(full[dir_str.len + 1 .. dir_str.len + 1 + name_slice.len], name_slice);
            full[dir_str.len + 1 + name_slice.len] = 0;
            if (c.stat(@ptrCast(&full), &st) != 0) continue;
            if (!isExecutable(st.st_mode)) continue;
            if ((st.st_mode & c.S_IFMT) != c.S_IFREG) continue;
            addEntry(name_slice, name_slice, name_slice, false);
        }
    }
}

pub fn scan() void {
    if (scanned) return;
    scanDesktopDirs();
    scanPath();
    scanned = true;
}

pub fn list() []AppEntry {
    scan();
    return apps[0..app_count];
}

pub fn count() usize {
    scan();
    return app_count;
}

// Reset internal catalog state so tests are independent of scan ordering.
fn testReset() void {
    apps = std.mem.zeroes([MAX_APPS]AppEntry);
    app_count = 0;
    scanned = false;
}

test "apps scan is idempotent" {
    // Do not assert a positive count: sandboxes may expose no PATH or
    // application directories. Assert scanning is stable and non-destructive.
    testReset();
    scan();
    const first = count();
    scan();
    try std.testing.expectEqual(first, count());
    try std.testing.expect(count() <= MAX_APPS);
}

test "addEntry stores name, exec, icon and flag" {
    testReset();
    addEntry("Firefox", "firefox", "firefox-icon", true);
    try std.testing.expectEqual(@as(usize, 1), app_count);
    const e = apps[0];
    try std.testing.expectEqualStrings("Firefox", e.name[0..e.name_len]);
    try std.testing.expectEqualStrings("firefox", e.exec[0..e.exec_len]);
    try std.testing.expectEqualStrings("firefox-icon", e.icon[0..e.icon_len]);
    try std.testing.expect(e.from_desktop);
    // Null terminators present.
    try std.testing.expectEqual(@as(u8, 0), e.name[e.name_len]);
}

test "addEntry de-duplicates by name (first wins)" {
    testReset();
    addEntry("Term", "foot", "", true);
    addEntry("Term", "alacritty", "", false);
    try std.testing.expectEqual(@as(usize, 1), app_count);
    const e = apps[0];
    try std.testing.expectEqualStrings("foot", e.exec[0..e.exec_len]);
    try std.testing.expect(e.from_desktop);
}

test "addEntry ignores empty names" {
    testReset();
    addEntry("", "x", "", false);
    try std.testing.expectEqual(@as(usize, 0), app_count);
}

test "addEntry respects MAX_APPS cap" {
    testReset();
    var buf: [8]u8 = undefined;
    for (0..MAX_APPS + 10) |i| {
        const name = std.fmt.bufPrint(&buf, "a{d}", .{i}) catch unreachable;
        addEntry(name, "e", "", false);
    }
    try std.testing.expectEqual(@as(usize, MAX_APPS), app_count);
}

test "addEntry truncates over-long fields" {
    testReset();
    var long: [400]u8 = undefined;
    @memset(&long, 'x');
    addEntry(long[0..300], long[0..400], long[0..300], true);
    const e = apps[0];
    try std.testing.expect(e.name_len <= e.name.len - 1);
    try std.testing.expect(e.exec_len <= e.exec.len - 1);
    try std.testing.expect(e.icon_len <= e.icon.len - 1);
    try std.testing.expectEqual(@as(u8, 0), e.name[e.name_len]);
    try std.testing.expectEqual(@as(u8, 0), e.exec[e.exec_len]);
}

test "stripFieldCode removes field codes" {
    var buf: [256]u8 = undefined;
    buf = std.mem.zeroes([256]u8);
    try std.testing.expectEqualStrings("firefox", stripFieldCode("firefox %u", &buf));
    buf = std.mem.zeroes([256]u8);
    try std.testing.expectEqualStrings("foot", stripFieldCode("foot %F", &buf));
    buf = std.mem.zeroes([256]u8);
    try std.testing.expectEqualStrings("app arg", stripFieldCode("app %f arg", &buf));
}

test "stripFieldCode keeps literal percent" {
    var buf: [256]u8 = std.mem.zeroes([256]u8);
    try std.testing.expectEqualStrings("100% cpu", stripFieldCode("100%% cpu", &buf));
}

test "stripFieldCode leaves plain commands intact" {
    var buf: [256]u8 = std.mem.zeroes([256]u8);
    try std.testing.expectEqualStrings("gimp", stripFieldCode("gimp", &buf));
    buf = std.mem.zeroes([256]u8);
    try std.testing.expectEqualStrings("code --new-window", stripFieldCode("code --new-window", &buf));
}

test "trimNewline strips trailing CR/LF" {
    try std.testing.expectEqualStrings("hello", trimNewline("hello\n"));
    try std.testing.expectEqualStrings("hello", trimNewline("hello\r\n"));
    try std.testing.expectEqualStrings("hello", trimNewline("hello"));
}

test "parseDesktopFile reads Name/Exec/Icon" {
    testReset();
    const path = "/tmp/zigshell_apps_test_ok.desktop";
    const f = c.fopen(path, "w") orelse return error.SkipZigTest;
    _ = c.fputs("[Desktop Entry]\nName=Editor\nExec=nano %F\nIcon=text-editor\n", f);
    _ = c.fflush(f);
    _ = c.fclose(f);
    defer _ = c.remove(path);

    parseDesktopFile(path);
    try std.testing.expectEqual(@as(usize, 1), app_count);
    const e = apps[0];
    try std.testing.expectEqualStrings("Editor", e.name[0..e.name_len]);
    try std.testing.expectEqualStrings("text-editor", e.icon[0..e.icon_len]);
    try std.testing.expect(e.from_desktop);
    // Field code stripped from Exec.
    try std.testing.expect(std.mem.startsWith(u8, e.exec[0..e.exec_len], "nano"));
}

test "parseDesktopFile skips NoDisplay entries" {
    testReset();
    const path = "/tmp/zigshell_apps_test_nodisplay.desktop";
    const f = c.fopen(path, "w") orelse return error.SkipZigTest;
    _ = c.fputs("[Desktop Entry]\nName=Hidden\nExec=x\nNoDisplay=true\n", f);
    _ = c.fflush(f);
    _ = c.fclose(f);
    defer _ = c.remove(path);

    parseDesktopFile(path);
    try std.testing.expectEqual(@as(usize, 0), app_count);
}

test "parseDesktopFile skips Hidden entries" {
    testReset();
    const path = "/tmp/zigshell_apps_test_hidden.desktop";
    const f = c.fopen(path, "w") orelse return error.SkipZigTest;
    _ = c.fputs("[Desktop Entry]\nName=Gone\nExec=x\nHidden=true\n", f);
    _ = c.fflush(f);
    _ = c.fclose(f);
    defer _ = c.remove(path);

    parseDesktopFile(path);
    try std.testing.expectEqual(@as(usize, 0), app_count);
}

test "parseDesktopFile skips entries without Name or Exec" {
    testReset();
    const path = "/tmp/zigshell_apps_test_incomplete.desktop";
    const f = c.fopen(path, "w") orelse return error.SkipZigTest;
    _ = c.fputs("[Desktop Entry]\nName=OnlyName\n", f);
    _ = c.fflush(f);
    _ = c.fclose(f);
    defer _ = c.remove(path);

    parseDesktopFile(path);
    try std.testing.expectEqual(@as(usize, 0), app_count);
}

test "list returns a slice sized to count" {
    testReset();
    const l = list();
    try std.testing.expectEqual(count(), l.len);
}
