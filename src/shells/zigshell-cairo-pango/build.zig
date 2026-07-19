const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_flags: []const []const u8 = &.{ "-std=gnu11", "-Wall" };

    // === zigshell-cairo-pango (merged panel + dock) ===
    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main_shell.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "zigshell-cairo-pango",
        .root_module = root_mod,
    });

    // Shared cross-shell module (damage/toplevel), single source of truth.
    const shellcore = b.createModule(.{
        .root_source_file = b.path("../shared/shellcore.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root_mod.addImport("shellcore", shellcore);

    // Shared app catalog (launcher) module.
    const apps = b.createModule(.{
        .root_source_file = b.path("../shared/apps.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root_mod.addImport("apps", apps);

    // Shared logging configuration (env-controlled level, custom logFn).
    const log_mod = b.createModule(.{
        .root_source_file = b.path("../shared/log.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root_mod.addImport("log", log_mod);

    linkDeps(root_mod, b);
    addProtocolSources(root_mod, b, c_flags);

    b.installArtifact(exe);

    // === settings_gtk — out-of-process GTK3 settings panel (C + thin Zig entry) ===
    // Edits the shared INI config file and signals the running shell via SIGHUP.
    // Launched on demand from the shell's gear button. No Wayland coupling.
    const gtk_mod = b.createModule(.{
        .root_source_file = b.path("src/settings_gtk_main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    gtk_mod.addCSourceFiles(.{ .files = &.{"src/settings_gtk.c"}, .flags = c_flags });
    gtk_mod.linkSystemLibrary("gtk+-3.0", .{});
    gtk_mod.linkSystemLibrary("glib-2.0", .{});
    gtk_mod.linkSystemLibrary("gobject-2.0", .{});
    const gtk_exe = b.addExecutable(.{ .name = "zigshell-settings-gtk", .root_module = gtk_mod });
    b.installArtifact(gtk_exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run zigshell-cairo-pango");
    run_step.dependOn(&run_cmd.step);

    // Tests
    root_mod.addImport("shellcore", shellcore);
    const exe_unit_tests = b.addTest(.{
        .root_module = root_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // Shared app-catalog module tests (parsing, dedup, field codes).
    const apps_tests_mod = b.createModule(.{
        .root_source_file = b.path("../shared/apps.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const apps_unit_tests = b.addTest(.{ .root_module = apps_tests_mod });
    const run_apps_unit_tests = b.addRunArtifact(apps_unit_tests);
    test_step.dependOn(&run_apps_unit_tests.step);

    // Public-API app-catalog tests (shared with the blend2d shell).
    const apps_api_mod = b.createModule(.{
        .root_source_file = b.path("../shared/apps_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    apps_api_mod.addImport("apps", apps);
    const apps_api_tests = b.addTest(.{ .root_module = apps_api_mod });
    const run_apps_api_tests = b.addRunArtifact(apps_api_tests);
    test_step.dependOn(&run_apps_api_tests.step);

    // Cross-shell dock contract tests — the SAME assertions run against this
    // shell's dock.zig and against zigshell-blend2d's, guarding click/hit-test
    // parity. The `dock` import alias points at this shell's implementation.
    const dock_mod = b.createModule(.{
        .root_source_file = b.path("src/dock.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dock_mod.addImport("shellcore", shellcore);
    const dock_val_mod = b.createModule(.{
        .root_source_file = b.path("../shared/dock_validation.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dock_val_mod.addImport("shellcore", shellcore);
    dock_val_mod.addImport("dock", dock_mod);
    const dock_val_tests = b.addTest(.{ .root_module = dock_val_mod });
    const run_dock_val_tests = b.addRunArtifact(dock_val_tests);
    test_step.dependOn(&run_dock_val_tests.step);

    // Cross-shell widget contract tests — the SAME assertions run against this
    // shell's panel.zig and against zigshell-blend2d's, guarding widget
    // creation/type/structure parity.
    const panel_for_val = b.createModule(.{
        .root_source_file = b.path("src/panel.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    panel_for_val.addImport("shellcore", shellcore);
    linkDeps(panel_for_val, b);
    addProtocolSources(panel_for_val, b, &.{ "-std=gnu11", "-Wall" });
    const widget_val_mod = b.createModule(.{
        .root_source_file = b.path("../shared/widget_validation.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    widget_val_mod.addImport("panel", panel_for_val);
    widget_val_mod.addImport("shellcore", shellcore);
    const widget_val_tests = b.addTest(.{ .root_module = widget_val_mod });
    const run_widget_val_tests = b.addRunArtifact(widget_val_tests);
    test_step.dependOn(&run_widget_val_tests.step);
}

fn linkDeps(root_mod: *std.Build.Module, b: *std.Build) void {
    root_mod.linkSystemLibrary("wayland-client", .{});
    root_mod.linkSystemLibrary("cairo", .{});
    root_mod.linkSystemLibrary("pangocairo-1.0", .{});
    root_mod.linkSystemLibrary("pango-1.0", .{});
    root_mod.linkSystemLibrary("glib-2.0", .{});
    root_mod.linkSystemLibrary("gobject-2.0", .{});
    root_mod.linkSystemLibrary("gio-2.0", .{});
    root_mod.linkSystemLibrary("librsvg-2.0", .{});
    root_mod.addIncludePath(b.path("src"));
    root_mod.addIncludePath(b.path("."));
    root_mod.addIncludePath(b.path("../shared/protocol"));
    root_mod.addIncludePath(b.path("../../../libs/tinyfiledialogs"));
}

fn addProtocolSources(root_mod: *std.Build.Module, b: *std.Build, c_flags: []const []const u8) void {
    root_mod.addCSourceFile(.{
        .file = b.path("src/dock_c_impl.c"),
        .flags = c_flags,
    });
    // Single-source Wayland protocol bindings shared by both shells.
    root_mod.addCSourceFile(.{
        .file = b.path("../shared/protocol/wlr-layer-shell-unstable-v1-client-protocol.c"),
        .flags = c_flags,
    });
    root_mod.addCSourceFile(.{
        .file = b.path("../shared/protocol/wlr-foreign-toplevel-management-unstable-v1-client-protocol.c"),
        .flags = c_flags,
    });
    root_mod.addCSourceFile(.{
        .file = b.path("../shared/protocol/xdg-shell-client-protocol.c"),
        .flags = c_flags,
    });
    root_mod.addCSourceFile(.{
        .file = b.path("../../../libs/tinyfiledialogs/tinyfiledialogs.c"),
        .flags = c_flags,
    });
}
