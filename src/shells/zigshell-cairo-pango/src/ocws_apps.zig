// ocws_apps.zig — Hardcoded catalog of OCWS GUI applications
//
// Used by the dock's launcher button to show a curated floating panel
// of only the OCWS homepage apps. This is separate from the generic
// app catalog (apps.zig) which discovers all system applications.

const std = @import("std");

pub const OcwsApp = struct {
    name: []const u8,
    exec: []const u8,
    icon: []const u8,
    category: []const u8,
};

pub const OCWS_APPS = [_]OcwsApp{
    .{ .name = "Settings", .exec = "ocws-settings", .icon = "preferences-desktop", .category = "System" },
    .{ .name = "Welcome", .exec = "ocws-welcome --force", .icon = "help-about", .category = "System" },
    .{ .name = "Theme Center", .exec = "ocws-theme-center", .icon = "preferences-desktop-theme", .category = "Customize" },
    .{ .name = "Font Manager", .exec = "ocws-fonts-mgr", .icon = "preferences-desktop-font", .category = "Customize" },
    .{ .name = "Dock Manager", .exec = "ocws-dock-mgr", .icon = "preferences-desktop-panel", .category = "Customize" },
    .{ .name = "Workspace Manager", .exec = "ocws-workspace-mgr", .icon = "preferences-desktop-workspaces", .category = "Customize" },
    .{ .name = "Package Manager", .exec = "ocws-pkgmgr", .icon = "system-software-install", .category = "System" },
    .{ .name = ".desktop Manager", .exec = "ocws-dotdesktop-mgr", .icon = "application-x-executable", .category = "System" },
    .{ .name = "LLM Runner", .exec = "ocws-llm-runner", .icon = "utilities-terminal", .category = "Tools" },
};

pub const OCWS_APP_COUNT = OCWS_APPS.len;
