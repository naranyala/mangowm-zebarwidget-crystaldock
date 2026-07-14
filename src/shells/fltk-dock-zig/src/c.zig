// c.zig — Single shared C import for all Zig modules
pub const c = @cImport({
    @cInclude("dock_c.h");
});
