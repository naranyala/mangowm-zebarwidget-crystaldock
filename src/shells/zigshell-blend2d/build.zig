const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_flags: []const []const u8 = &.{ "-std=gnu11", "-Wall" };

    // Build options
    const static = b.option(bool, "static", "Build Blend2D as static library") orelse false;

    // Step 1: Build Blend2D via CMake
    var cmake_base_args = [_][]const u8{ "cmake", "-B", "build/deps", "-S", ".", "-DCMAKE_BUILD_TYPE=Release", "-DBLEND2D_NO_JIT=ON" };
    var cmake_all_args: [8][]const u8 = undefined;
    var cmake_arg_count: usize = cmake_base_args.len;

    @memcpy(cmake_all_args[0..cmake_base_args.len], &cmake_base_args);
    if (static) {
        cmake_all_args[cmake_arg_count] = "-DBLEND2D_TARGET_TYPE=STATIC";
        cmake_arg_count += 1;
    }

    const cmake_configure = b.addSystemCommand(cmake_all_args[0..cmake_arg_count]);
    const cmake_build = b.addSystemCommand(&.{ "make", "-C", "build/deps", "blend2d", "-j4" });
    cmake_build.step.dependOn(&cmake_configure.step);

    // Step 2: Build the Zig shell executable
    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main_shell.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "zigshell-blend2d",
        .root_module = root_mod,
    });
    exe.step.dependOn(&cmake_build.step);

    // Link Wayland
    root_mod.linkSystemLibrary("wayland-client", .{});
    root_mod.addIncludePath(b.path("src"));
    root_mod.addIncludePath(b.path("."));
    root_mod.addIncludePath(b.path("deps/blend2d"));

    // Link Blend2D
    root_mod.addLibraryPath(b.path("build/deps/blend2d"));
    root_mod.linkSystemLibrary("blend2d", .{});
    root_mod.linkSystemLibrary("stdc++", .{});

    // Add protocol C sources
    addProtocolSources(root_mod, b, c_flags);

    // Add dock_c_impl.c (includes Blend2D implementation)
    root_mod.addCSourceFile(.{
        .file = b.path("src/dock_c_impl.c"),
        .flags = &.{ "-std=gnu11", "-Wall", "-DBLEND2D_STATIC" },
    });

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run zigshell-blend2d");
    run_step.dependOn(&run_cmd.step);

    // ============================================================
    // Test targets — one per module
    // ============================================================

    // Pure logic tests (no Blend2D dependency)
    const toplevel_mod = b.createModule(.{
        .root_source_file = b.path("src/toplevel_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const toplevel_tests = b.addTest(.{ .root_module = toplevel_mod });
    const run_toplevel_tests = b.addRunArtifact(toplevel_tests);

    const dock_mod = b.createModule(.{
        .root_source_file = b.path("src/dock_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dock_tests = b.addTest(.{ .root_module = dock_mod });
    const run_dock_tests = b.addRunArtifact(dock_tests);

    const panel_mod_test = b.createModule(.{
        .root_source_file = b.path("src/panel_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    panel_mod_test.addIncludePath(b.path("src"));
    panel_mod_test.addIncludePath(b.path("."));
    panel_mod_test.addIncludePath(b.path("deps/blend2d"));
    panel_mod_test.addLibraryPath(b.path("build/deps/blend2d"));
    panel_mod_test.linkSystemLibrary("blend2d", .{});
    panel_mod_test.linkSystemLibrary("stdc++", .{});
    panel_mod_test.linkSystemLibrary("wayland-client", .{});
    panel_mod_test.addCSourceFile(.{
        .file = b.path("src/dock_c_impl.c"),
        .flags = &.{ "-std=gnu11", "-Wall", "-DBLEND2D_STATIC" },
    });
    const panel_tests = b.addTest(.{ .root_module = panel_mod_test });
    const run_panel_tests = b.addRunArtifact(panel_tests);
    run_panel_tests.step.dependOn(&cmake_build.step);

    // Tests that need Blend2D linked
    const render_mod = b.createModule(.{
        .root_source_file = b.path("src/blend2d_render_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    render_mod.addIncludePath(b.path("src"));
    render_mod.addIncludePath(b.path("."));
    render_mod.addIncludePath(b.path("deps/blend2d"));
    render_mod.addLibraryPath(b.path("build/deps/blend2d"));
    render_mod.linkSystemLibrary("blend2d", .{});
    render_mod.linkSystemLibrary("stdc++", .{});
    render_mod.addCSourceFile(.{
        .file = b.path("src/dock_c_impl.c"),
        .flags = &.{ "-std=gnu11", "-Wall", "-DBLEND2D_STATIC" },
    });
    const render_tests = b.addTest(.{ .root_module = render_mod });
    const run_render_tests = b.addRunArtifact(render_tests);
    run_render_tests.step.dependOn(&cmake_build.step);

    const icon_mod = b.createModule(.{
        .root_source_file = b.path("src/icon_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    icon_mod.addIncludePath(b.path("src"));
    icon_mod.addIncludePath(b.path("."));
    icon_mod.addIncludePath(b.path("deps/blend2d"));
    icon_mod.addLibraryPath(b.path("build/deps/blend2d"));
    icon_mod.linkSystemLibrary("blend2d", .{});
    icon_mod.linkSystemLibrary("stdc++", .{});
    icon_mod.addCSourceFile(.{
        .file = b.path("src/dock_c_impl.c"),
        .flags = &.{ "-std=gnu11", "-Wall", "-DBLEND2D_STATIC" },
    });
    const icon_tests = b.addTest(.{ .root_module = icon_mod });
    const run_icon_tests = b.addRunArtifact(icon_tests);
    run_icon_tests.step.dependOn(&cmake_build.step);

    // ============================================================
    // Test steps
    // ============================================================

    // Run all tests
    const test_all = b.step("test", "Run all tests");
    test_all.dependOn(&run_toplevel_tests.step);
    test_all.dependOn(&run_dock_tests.step);
    test_all.dependOn(&run_panel_tests.step);
    test_all.dependOn(&run_render_tests.step);
    test_all.dependOn(&run_icon_tests.step);

    // Individual test targets
    const test_toplevel = b.step("test-toplevel", "Run toplevel tests");
    test_toplevel.dependOn(&run_toplevel_tests.step);

    const test_dock = b.step("test-dock", "Run dock layout tests");
    test_dock.dependOn(&run_dock_tests.step);

    const test_panel = b.step("test-panel", "Run panel widget tests");
    test_panel.dependOn(&run_panel_tests.step);

    const test_render = b.step("test-render", "Run Blend2D renderer tests");
    test_render.dependOn(&run_render_tests.step);

    const test_icon = b.step("test-icon", "Run icon loading tests");
    test_icon.dependOn(&run_icon_tests.step);
}

fn addProtocolSources(root_mod: *std.Build.Module, b: *std.Build, c_flags: []const []const u8) void {
    root_mod.addCSourceFile(.{
        .file = b.path("wlr-layer-shell-unstable-v1-client-protocol.c"),
        .flags = c_flags,
    });
    root_mod.addCSourceFile(.{
        .file = b.path("wlr-foreign-toplevel-management-unstable-v1-client-protocol.c"),
        .flags = c_flags,
    });
    root_mod.addCSourceFile(.{
        .file = b.path("xdg-shell-client-protocol.c"),
        .flags = c_flags,
    });
}
