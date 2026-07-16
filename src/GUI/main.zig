const std = @import("std");
const Conf = @import("Conf");
const Interface = @import("interface.zig").Interface;
const Async = @import("Async");
var lib: *anyopaque = undefined;
pub var backend: *const Interface = undefined;

extern "kernel32" fn LoadLibraryA(lpLibFileName: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetProcAddress(hModule: *anyopaque, lpProcName: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn FreeLibrary(hModule: *anyopaque) callconv(.winapi) c_int;

pub fn init(allocator: std.mem.Allocator, reserve: Async.Reserve) !void {
    lib = blk: {
        switch (Conf.BuildOptions.renderer) {
            .automatic => {},
            .vulkan => {
                const returned = LoadLibraryA("vulkan.dll");
                if (returned) |ret| break :blk ret;
                @panic("failed");
            },
            .opengl => {},
            .directx => {},
        }
    };
    const function: ?*const fn () callconv(.c) *const Interface = @ptrCast(GetProcAddress(lib, "getApi"));
    if (function) |getApi| {
        backend = getApi();
        try backend.init(allocator, reserve);
    } else @panic("Renderer must have getApi function");
}

pub fn deinit(reserve: Async.Reserve) void {
    backend.deinit(reserve);
}

pub const Window = @import("interface.zig").Window(backend);

pub fn pollEvents(reserve: Async.Reserve) void {
    backend.pollEvents(reserve);
}
