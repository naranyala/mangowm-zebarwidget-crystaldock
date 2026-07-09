const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_flags = &[_][]const u8{
        "-std=gnu11",
        "-Wall",
        "-Wextra",
        "-Wno-deprecated-declarations",
        "-O2",
        "-Isrc/gui",
        "-Isrc/libocws",
    };

    // ocws-equalizer-enhanced: GTK3 audio equalizer with audio_stream + audio_analysis
    {
        const exe = b.addExecutable(.{
            .name = "ocws-equalizer-enhanced",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        exe.root_module.addCSourceFile(.{ .file = b.path("src/gui/ocws-equalizer-enhanced.c"), .flags = c_flags });
        exe.root_module.addCSourceFile(.{ .file = b.path("src/libocws/audio_analysis.c"), .flags = c_flags });
        exe.root_module.addCSourceFile(.{ .file = b.path("src/libocws/audio_stream.c"), .flags = c_flags });

        exe.root_module.linkSystemLibrary("gtk+-3.0", .{});
        exe.root_module.linkSystemLibrary("glib-2.0", .{});
        exe.root_module.linkSystemLibrary("pulse", .{});
        exe.root_module.linkSystemLibrary("pulse-simple", .{});
        exe.root_module.linkSystemLibrary("fftw3", .{});
        exe.root_module.linkSystemLibrary("m", .{});
        exe.root_module.linkSystemLibrary("ayatana-appindicator3-0.1", .{});

        b.installArtifact(exe);
        const step = b.step("ocws-equalizer-enhanced", "Build the enhanced OCWS Equalizer");
        step.dependOn(&exe.step);
    }

    // ocws-equalizer: original GTK3 equalizer (backward compat)
    {
        const exe = b.addExecutable(.{
            .name = "ocws-equalizer",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        exe.root_module.addCSourceFile(.{ .file = b.path("src/gui/ocws-equalizer.c"), .flags = c_flags });
        exe.root_module.linkSystemLibrary("gtk+-3.0", .{});
        exe.root_module.linkSystemLibrary("glib-2.0", .{});
        exe.root_module.linkSystemLibrary("pulse", .{});
        exe.root_module.linkSystemLibrary("pulse-simple", .{});
        exe.root_module.linkSystemLibrary("fftw3", .{});
        exe.root_module.linkSystemLibrary("m", .{});
        exe.root_module.linkSystemLibrary("ayatana-appindicator3-0.1", .{});

        b.installArtifact(exe);
        const step = b.step("ocws-equalizer", "Build the original OCWS Equalizer");
        step.dependOn(&exe.step);
    }
}
