const std = @import("std");
const IO = @import("IO");
const Async = @import("Async");
const luajit = @import("LuaJIT");
const TrackingAllocator = @import("TrackingAllocator");
const Conf = @import("Conf");
pub var Allocator: TrackingAllocator = undefined;
pub const LuaStruct = luajit.Lua;
pub var Lua: *LuaStruct = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    Allocator = TrackingAllocator.init(allocator, "LuaAllocator");
    Lua = try LuaStruct.init(Allocator.allocator());
    Lua.openBaseLib();
    Lua.pushCFunction(IO_print);
    registerEngineModules(Lua);
}
pub fn deinit() void {
    Lua.deinit();
}

fn IO_print(lua: *LuaStruct) callconv(.c) i32 {
    const string: [*:0]const u8 = lua.checkString(-1);
    IO.print("{s}", .{string}) catch {
        std.debug.print("Write failed!\n", .{});
        lua.pushString("Write failed at IO_print!\n");
        lua.raiseError();
        unreachable;
    };
    return 0;
}
fn IO_read(lua: *LuaStruct) callconv(.c) i32 {
    const n = lua.checkInteger(-1);

    if (n <= 0) {
        lua.pushString("");
        return 1;
    }
    const allocator = Allocator.allocator();
    const size: usize = @intCast(n);
    var buf = allocator.alloc(u8, size + 1) catch {
        std.debug.print("Got an error in IO_read: OutOfMem!\n", .{});
        lua.pushString("Got an error in IO_read: OutOfMem!\n");
        lua.raiseError();
    };
    defer allocator.free(buf);
    const bytes_read = IO.read(buf) catch |err| {
        allocator.free(buf);
        const ErrorMessage = "Got an error in IO.read: ";
        const name = @errorName(err);

        var err_buf: [ErrorMessage.len + 125:0]u8 = undefined;
        const msg = std.fmt.bufPrintSentinel(&err_buf, "{s}{s}!\n", .{ ErrorMessage, name }, 0) catch "IO.read failed";

        lua.pushString(msg);
        lua.raiseError();
        unreachable;
    };
    buf[bytes_read] = 0;
    const to_return = buf[0..bytes_read];
    lua.pushInteger(@intCast(bytes_read));
    lua.pushLString(to_return);
    return 2;
}
const WrapperArgs = struct {
    func_ref: i32,
    table_ref: i32,
};
// i32 is a reference in lua(address)
const LuaFuture = Async.Future(i32);
const SizeOfLuaFuture = @sizeOf(LuaFuture);
fn Async_call(lua: *LuaStruct) callconv(.c) i32 {
    if (!lua.isFunction(1)) {
        lua.pushString("First argument must be a function!");
        lua.raiseError();
        unreachable;
    }
    if (!lua.isTable(2)) {
        lua.pushString("Second Argument must be a table(array)!");
        lua.raiseError();
        unreachable;
    }
    const allocator = Allocator.allocator();
    // Making future for the user
    var future_ptr: *LuaFuture = undefined;
    if (lua.getTop() >= 3 and lua.isUserdata(3)) {
        // if 3rd argument exists and it's a reference then it should be Future
        future_ptr = @ptrCast(@alignCast(if (lua.toUserdata(3)) |ret| ret else {
            lua.pushString("Arg 3 must be a valid Future object!");
            lua.raiseError();
            unreachable;
        }));
        future_ptr.reset();
        lua.pushValue(3);
    } else {
        // if no argument make new Future
        future_ptr = @ptrCast(@alignCast(lua.newUserdata(SizeOfLuaFuture)));
        lua.getMetatableRegistry("Engine.Async.Future");
        lua.setMetatable(-2);
    }
    lua.getMetatableRegistry("Engine.Async.Future");
    lua.setMetatable(-2);

    lua.pushValue(1);
    const function_reference = lua.ref(LuaStruct.PseudoIndex.Registry);
    lua.pushValue(2);
    const table_reference = lua.ref(LuaStruct.PseudoIndex.Registry);
    if (!Conf.is_singlethreaded()) {
        const args_ptr = allocator.create(WrapperArgs) catch {
            lua.unref(LuaStruct.PseudoIndex.Registry, function_reference);
            lua.unref(LuaStruct.PseudoIndex.Registry, table_reference);
            lua.pushString("Out of memory");
            lua.raiseError();
            unreachable;
        };
        args_ptr.* = .{ .func_ref = function_reference, .table_ref = table_reference };

        const wrapper = struct {
            pub fn exec(self: Async.Task.Call) void {
                const args: *WrapperArgs = @ptrCast(@alignCast(self.args.?));
                _ = Lua.getTableIndexRaw(LuaStruct.PseudoIndex.Registry, args.func_ref); // Stack: [ function ]
                _ = Lua.getTableIndexRaw(LuaStruct.PseudoIndex.Registry, args.table_ref); // Stack: [ function, args ]
                const res_ref = blk: {
                    Lua.callProtected(1, 1, 0) catch |err| {
                        std.debug.print("Error on async call: {s}\n", .{@errorName(err)});

                        Lua.pop(1);
                        Lua.pushNil();

                        break :blk Lua.ref(LuaStruct.PseudoIndex.Registry);
                    };
                    break :blk Lua.ref(LuaStruct.PseudoIndex.Registry);
                };
                if (self.return_to) |address| {
                    const future: *LuaFuture = @ptrCast(@alignCast(address));
                    future.set(res_ref);
                }
            }
            pub fn destroy(self: Async.Task.Call) void {
                if (self.allocator) |alloc| {
                    const allocat = alloc.allocator();
                    const args: *WrapperArgs = @ptrCast(@alignCast(self.args.?));
                    Lua.unref(LuaStruct.PseudoIndex.Registry, args.func_ref);
                    Lua.unref(LuaStruct.PseudoIndex.Registry, args.table_ref);
                    allocat.destroy(args);
                }
            }
        };
        const item = Async.Task.Call{
            .function = &wrapper.exec,
            .destroy = &wrapper.destroy,
            .allocator = &Allocator,
            .args = args_ptr,
            .return_to = @ptrCast(@alignCast(future_ptr)),
        };
        Async.call_thread_select(item) catch {
            // Queue is full
            wrapper.destroy(item);
            lua.pushString("Async queue is full");
            lua.raiseError();
            unreachable;
        };
    }
    // future table is already on stack so just return it
    return 1;
}
fn Async_reserve(lua: *LuaStruct) callconv(.c) i32 {
    const n = lua.checkInteger(1);
    const reserved = Async.reserve(@intCast(n)) catch |err| {
        const Message = "Couldn't reserve a thread because of an error: ";
        var buf: [Message.len + 125:0]u8 = undefined;
        const msg = std.fmt.bufPrintSentinel(&buf, "{s}{s}", .{ Message, @errorName(err) }, 0) catch "Reserve failed";
        lua.pushString(msg);
        lua.raiseError();
        unreachable;
    };
    const res_ptr: *Async.Task.Reserve = @ptrCast(@alignCast(lua.newUserdata(@sizeOf(Async.Task.Reserve))));
    res_ptr.* = reserved;
    lua.getMetatableRegistry("Engine.Async.Reserve");
    lua.setMetatable(-2);

    return 1;
}
fn Async_call_reserve(lua: *LuaStruct) callconv(.c) i32 {
    if (!lua.isUserdata(1)) {
        lua.pushString("First argument must be a Reserve object!");
        lua.raiseError();
        unreachable;
    }
    if (!lua.isFunction(2)) {
        lua.pushString("Second argument must be a function!");
        lua.raiseError();
        unreachable;
    }
    if (!lua.isTable(3)) {
        lua.pushString("Third Argument must be a table(array)!");
        lua.raiseError();
        unreachable;
    }
    const reserved: *Async.Task.Reserve = if (lua.toUserdata(1)) |ret| @ptrCast(@alignCast(ret)) else unreachable;
    const allocator = Allocator.allocator();
    // Making future for the user
    var future_ptr: *LuaFuture = undefined;
    if (lua.getTop() >= 4 and lua.isUserdata(4)) {
        // if 3rd argument exists and it's a reference then it should be Future
        future_ptr = if (lua.toUserdata(4)) |ret| @ptrCast(@alignCast(ret)) else {
            lua.pushString("Fourth must be a valid Future object!");
            lua.raiseError();
            unreachable;
        };
        future_ptr.reset();
        lua.pushValue(4);
    } else {
        // if no argument make new Future
        future_ptr = @ptrCast(@alignCast(lua.newUserdata(SizeOfLuaFuture)));
        lua.getMetatableRegistry("Engine.Async.Future");
        lua.setMetatable(-2);
    }
    lua.getMetatableRegistry("Engine.Async.Future");
    lua.setMetatable(-2);

    lua.pushValue(2);
    const function_reference = lua.ref(LuaStruct.PseudoIndex.Registry);
    lua.pushValue(3);
    const table_reference = lua.ref(LuaStruct.PseudoIndex.Registry);
    if (!Conf.is_singlethreaded()) {
        const args_ptr = allocator.create(WrapperArgs) catch {
            lua.unref(LuaStruct.PseudoIndex.Registry, function_reference);
            lua.unref(LuaStruct.PseudoIndex.Registry, table_reference);
            lua.pushString("Out of memory");
            lua.raiseError();
            unreachable;
        };
        args_ptr.* = .{ .func_ref = function_reference, .table_ref = table_reference };

        const wrapper = struct {
            pub fn exec(self: Async.Task.Call) void {
                const args: *WrapperArgs = @ptrCast(@alignCast(self.args.?));
                _ = Lua.getTableIndexRaw(LuaStruct.PseudoIndex.Registry, args.func_ref); // Stack: [ function ]
                _ = Lua.getTableIndexRaw(LuaStruct.PseudoIndex.Registry, args.table_ref); // Stack: [ function, args ]
                const res_ref = blk: {
                    Lua.callProtected(1, 1, 0) catch |err| {
                        std.debug.print("Error on async call: {s}\n", .{@errorName(err)});

                        Lua.pop(1);
                        Lua.pushNil();

                        break :blk Lua.ref(LuaStruct.PseudoIndex.Registry);
                    };
                    break :blk Lua.ref(LuaStruct.PseudoIndex.Registry);
                };
                if (self.return_to) |address| {
                    const future: *LuaFuture = @ptrCast(@alignCast(address));
                    future.set(res_ref);
                }
            }
            pub fn destroy(self: Async.Task.Call) void {
                if (self.allocator) |alloc| {
                    const allocat = alloc.allocator();
                    const args: *WrapperArgs = @ptrCast(@alignCast(self.args.?));
                    Lua.unref(LuaStruct.PseudoIndex.Registry, args.func_ref);
                    Lua.unref(LuaStruct.PseudoIndex.Registry, args.table_ref);
                    allocat.destroy(args);
                }
            }
        };
        const item = Async.Task.Call{
            .function = &wrapper.exec,
            .destroy = &wrapper.destroy,
            .allocator = &Allocator,
            .args = args_ptr,
            .return_to = @ptrCast(@alignCast(future_ptr)),
        };
        Async.Task.call_thread(reserved.thread, item) catch {
            // Queue is full
            wrapper.destroy(item);
            lua.pushString("Async queue is full");
            lua.raiseError();
            unreachable;
        };
    }
    // future table is already on stack so just return it
    return 1;
}
const LuaFutureMetatable = struct {
    pub fn wait(lua: *LuaStruct) callconv(.c) i32 {
        // User will write future:wait() or future.wait(future)
        const future: *LuaFuture = if (lua.toUserdata(1)) |ret| @ptrCast(@alignCast(ret)) else return 0;
        const result_ref = future.wait();
        _ = lua.getTableIndexRaw(LuaStruct.PseudoIndex.Registry, result_ref);
        // Cleanup
        lua.unref(LuaStruct.PseudoIndex.Registry, result_ref);
        // getTableIndexRaw pushed returned value to stack
        return 1;
    }
    pub fn reset(lua: *LuaStruct) callconv(.c) i32 {
        const future: *LuaFuture = if (lua.toUserdata(1)) |ret| @ptrCast(@alignCast(ret)) else return 0;
        future.reset();
        return 0;
    }
    pub fn tryValue(lua: *LuaStruct) callconv(.c) i32 {
        const future: *LuaFuture = if (lua.toUserdata(1)) |ret| @ptrCast(@alignCast(ret)) else return 0;
        const value = future.tryValue();
        if (value) |val| {
            _ = lua.getTableIndexRaw(LuaStruct.PseudoIndex.Registry, val);
            return 1;
        }
        return 0;
    }
    pub fn setup_metatable(lua: *LuaStruct) void {
        _ = lua.newMetatable("Engine.Async.Future");
        lua.pushCFunction(wait);
        lua.setField(-2, "wait");

        lua.pushCFunction(reset);
        lua.setField(-2, "reset");

        lua.pushCFunction(tryValue);
        lua.setField(-2, "tryValue");
        // duplicating this metatable to set it to self.__index so we can use future:wait()
        lua.pushValue(-1);
        lua.setField(-2, "__index");
        // Metatable is stil on stack so just pop it
        lua.pop(1);
    }
    pub fn gc(lua: *LuaStruct) callconv(.c) i32 {
        const future: *LuaFuture = if (lua.toUserdata(1)) |ret| @ptrCast(@alignCast(ret)) else return 0;

        if (future.tryValue()) |val| {
            lua.unref(LuaStruct.PseudoIndex.Registry, val);
        }
        return 0;
    }
    pub fn create(lua: *LuaStruct) callconv(.c) i32 {
        _ = lua.newUserdata(SizeOfLuaFuture);
        lua.getMetatableRegistry("Engine.Async.Future");
        lua.setMetatable(-2);
        return 1;
    }
};
const LuaReserveMetatable = struct {
    pub fn gc(lua: *LuaStruct) callconv(.c) i32 {
        const res: *Async.Task.Reserve = if (lua.toUserdata(1)) |ret| @ptrCast(@alignCast(ret)) else return 0;
        res.thread.reserved = false;
        return 0;
    }

    pub fn setup_metatable(lua: *LuaStruct) void {
        _ = lua.newMetatable("Engine.Async.Reserve");
        lua.pushCFunction(Async_call_reserve);
        lua.setField(-2, "call");

        lua.pushCFunction(gc);
        lua.setField(-2, "__gc");

        lua.pushValue(-1);
        lua.setField(-2, "__index");

        lua.pop(1);
    }
};

fn registerEngineModules(lua: *LuaStruct) void {
    lua.newTable(); // Stack: [ Engine_table ]
    lua.newTable(); // Stack: [ Engine_table, IO_table ]

    lua.pushCFunction(IO_print); // Stack: [ Engine_table, IO_table, IO_print_func ]
    lua.setField(-2, "print"); // Push IO_print into -2(IO_table). Stack: [ Engine_table, IO_table ]
    lua.pushCFunction(IO_read); // Stack: [ Engine_table, IO_table, IO_read_func ]
    lua.setField(-2, "read"); // Push IO_read into -2(IO_table). Stack: [ Engine_table, IO_table ]
    // Place "IO" into "Engine" table
    lua.setField(-2, "IO"); // Stack: [ Engine_table ]

    // Same for Async
    lua.newTable();
    LuaFutureMetatable.setup_metatable(lua);
    LuaReserveMetatable.setup_metatable(lua);
    lua.pushCFunction(Async_call);
    lua.setField(-2, "call");
    lua.pushCFunction(LuaFutureMetatable.create);
    lua.setField(-2, "Future");
    lua.pushCFunction(Async_reserve);
    lua.setField(-2, "reserve");

    lua.setField(-2, "Async");
    // Final stack is: [ Engine_table ] and we make it a global table
    lua.setGlobal("Engine");
}
