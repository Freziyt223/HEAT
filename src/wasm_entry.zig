//! Browser entry points exported for the basic-web host page.
const std = @import("std");
const Engine = @import("Engine");
const User = @import("User");

// Emscripten owns startup; prevent Zig 0.16's .emscripten fallback from
// generating its unsupported wasm32 _start implementation.
pub extern "c" fn _start() void;

// The browser runtime has no std.Threaded implementation for debug output.
pub const std_options_debug_io: std.Io = .failing;
pub const std_options: std.Options = .{ .allow_stack_tracing = false };

// Zig's Debug-mode allocator ABI asks Emscripten for a return address. The
// browser build does not include emscripten's JS glue, and stack traces are
// disabled above, so a zero address is sufficient for this diagnostic hook.
pub export fn emscripten_return_address(_: c_int) usize {
    return 0;
}

var allocator_storage: [512 * 1024]u8 align(16) = undefined;
var fixed_allocator = std.heap.FixedBufferAllocator.init(&allocator_storage);
var started = false;

pub export fn heat_main() callconv(.c) c_int {
    if (started) return 0;
    const allocator = fixed_allocator.allocator();
    Engine.init(@as(void, {}), allocator) catch return 1;

    if (@hasDecl(User, "init")) {
        User.init(.{
            .args = .{ .vector = &.{} },
            .allocator = allocator,
        }) catch {
            Engine.deinit();
            return 1;
        };
    }

    started = true;
    return 0;
}

pub export fn heat_frame() callconv(.c) void {
    if (!started or !@hasDecl(User, "update")) return;
    User.update() catch Engine.State.store(.ErrorQutting, .release);
}

pub export fn heat_deinit() callconv(.c) void {
    if (!started) return;
    if (@hasDecl(User, "deinit")) User.deinit();
    Engine.deinit();
    started = false;
}
