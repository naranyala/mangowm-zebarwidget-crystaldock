const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Helper function to build a C executable
    const c_utils = [_][]const u8{
        "ocws-shot",
        "ocws-clip",
        "ocws-lock",
        "ocws-sysmon",
    };

    for (c_utils) |util_name| {
        const exe = b.addExecutable(.{
            .name = util_name,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        // Path to the C source file
        const src_path = b.fmt("src/{s}.c", .{util_name});
        
        exe.root_module.addCSourceFile(.{ 
            .file = b.path(src_path), 
            .flags = &[_][]const u8{
                "-std=gnu99", 
                "-Wall", 
                "-Wextra", 
                "-O2"
            } 
        });
        
        // Install the binary to zig-out/bin/
        b.installArtifact(exe);
    }
}
