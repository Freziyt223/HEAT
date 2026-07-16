const std = @import("std");
const Async = @import("Async");

pub const Bool = enum(c_int) {
    false = 0,
    true = 1,
    _,
};

pub const Action = enum(c_int) {
    release = 0,
    press = 1,
    repeat = 2,
};

pub const MouseButton = enum(c_int) {
    left = 0,
    right = 1,
    middle = 2,
    four = 3,
    five = 4,
    six = 5,
    seven = 6,
    eight = 7,
};

pub const Key = enum(c_int) {
    unknown = -1,

    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave_accent = 96,
    world_1 = 161,
    world_2 = 162,

    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    F1 = 290,
    F2 = 291,
    F3 = 292,
    F4 = 293,
    F5 = 294,
    F6 = 295,
    F7 = 296,
    F8 = 297,
    F9 = 298,
    F10 = 299,
    F11 = 300,
    F12 = 301,
    F13 = 302,
    F14 = 303,
    F15 = 304,
    F16 = 305,
    F17 = 306,
    F18 = 307,
    F19 = 308,
    F20 = 309,
    F21 = 310,
    F22 = 311,
    F23 = 312,
    F24 = 313,
    F25 = 314,
    kp_0 = 320,
    kp_1 = 321,
    kp_2 = 322,
    kp_3 = 323,
    kp_4 = 324,
    kp_5 = 325,
    kp_6 = 326,
    kp_7 = 327,
    kp_8 = 328,
    kp_9 = 329,
    kp_decimal = 330,
    kp_divide = 331,
    kp_multiply = 332,
    kp_subtract = 333,
    kp_add = 334,
    kp_enter = 335,
    kp_equal = 336,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,
    menu = 348,
};

pub const Mods = packed struct(c_int) {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    super: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    _padding: i26 = 0,
};

pub const CursorMode = enum(c_int) {
    normal = 0x00034001,
    hidden = 0x00034002,
    disabled = 0x00034003,
    captured = 0x00034004,
};

pub const InputMode = enum(c_int) {
    cursor = 0x00033001,
    sticky_keys = 0x00033002,
    sticky_mouse_buttons = 0x00033003,
    lock_key_mods = 0x00033004,
    raw_mouse_motion = 0x00033005,
};

pub const Cursor = opaque {};

// Callbacks
pub const FramebufferSizeFn = *const fn (window: *Window, width: c_int, height: c_int) callconv(.c) void;
pub const WindowSizeFn = *const fn (window: *Window, width: c_int, height: c_int) callconv(.c) void;
pub const WindowPosFn = *const fn (window: *Window, x: c_int, y: c_int) callconv(.c) void;
pub const WindowFocusFn = *const fn (window: *Window, focused: Bool) callconv(.c) void;
pub const IconifyFn = *const fn (window: *Window, iconified: Bool) callconv(.c) void;
pub const WindowContentScaleFn = *const fn (window: *Window, xscale: f32, yscale: f32) callconv(.c) void;
pub const WindowCloseFn = *const fn (window: *Window) callconv(.c) void;
pub const KeyFn = *const fn (window: *Window, key: Key, scancode: c_int, action: Action, mods: Mods) callconv(.c) void;
pub const CharFn = *const fn (window: *Window, codepoint: u32) callconv(.c) void;
pub const DropFn = *const fn (window: *Window, path_count: i32, paths: [*][*:0]const u8) callconv(.c) void;
pub const MouseButtonFn = *const fn (window: *Window, button: MouseButton, action: Action, mods: Mods) callconv(.c) void;
pub const ScrollFn = *const fn (window: *Window, xoffset: f64, yoffset: f64) callconv(.c) void;
pub const CursorPosFn = *const fn (window: *Window, xpos: f64, ypos: f64) callconv(.c) void;
pub const CursorEnterFn = *const fn (window: *Window, entered: i32) callconv(.c) void;

pub fn Interface(interface: type) type {
    const window = Window(interface);
    return struct {
        init: *const fn (std.mem.Allocator, reserve: Async.Reserve) anyerror!void,
        deinit: *const fn (reserve: Async.Reserve) void,

        // Window management
        createWindow: *const fn (width: c_int, height: c_int, title: [:0]const u8, monitor: ?*Monitor, share: ?*window, reserve: Async.Reserve) anyerror!*window,
        destroyWindow: *const fn (window: *window, reserve: Async.Reserve) void,
        windowShouldClose: *const fn (window: *window, reserve: Async.Reserve) bool,
        setWindowShouldClose: *const fn (window: *window, should_close: bool, reserve: Async.Reserve) void,
        setWindowTitle: *const fn (window: *window, title: [:0]const u8, reserve: Async.Reserve) void,
        getWindowSize: *const fn (window: *window, reserve: Async.Reserve) [2]c_int,
        setWindowSize: *const fn (window: *Window, width: c_int, height: c_int, reserve: Async.Reserve) void,
        getWindowFramebufferSize: *const fn (window: *Window, reserve: Async.Reserve) [2]c_int,
        getWindowPos: *const fn (window: *Window, reserve: Async.Reserve) [2]c_int,
        setWindowPos: *const fn (window: *Window, xpos: i32, ypos: i32, reserve: Async.Reserve) void,
        swapBuffers: *const fn (window: *Window, reserve: Async.Reserve) void,
        pollEvents: *const fn (reserve: Async.Reserve) void,

        getWindowUserPointer: *const fn (window: *Window, reserve: Async.Reserve) ?*anyopaque,
        setWindowUserPointer: *const fn (window: *Window, pointer: ?*anyopaque, reserve: Async.Reserve) void,
        getWindowAttributeUntyped: *const fn (window: *Window, attrib: Window.Attribute, reserve: Async.Reserve) c_int,
        setWindowAttributeUntyped: *const fn (window: *Window, attrib: Window.Attribute, value: c_int, reserve: Async.Reserve) void,

        iconifyWindow: *const fn (window: *Window, reserve: Async.Reserve) void,
        restoreWindow: *const fn (window: *Window, reserve: Async.Reserve) void,
        maximizeWindow: *const fn (window: *Window, reserve: Async.Reserve) void,
        showWindow: *const fn (window: *Window, reserve: Async.Reserve) void,
        hideWindow: *const fn (window: *Window, reserve: Async.Reserve) void,
        focusWindow: *const fn (window: *Window, reserve: Async.Reserve) void,
        requestWindowAttention: *const fn (window: *Window, reserve: Async.Reserve) void,

        getKey: *const fn (window: *Window, key: Key, reserve: Async.Reserve) Action,
        getMouseButton: *const fn (window: *Window, button: MouseButton, reserve: Async.Reserve) Action,
        getCursorPos: *const fn (window: *Window, reserve: Async.Reserve) [2]f64,
        setCursorPos: *const fn (window: *Window, xpos: f64, ypos: f64, reserve: Async.Reserve) void,

        setSizeLimits: *const fn (window: *Window, min_w: c_int, min_h: c_int, max_w: c_int, max_h: c_int, reserve: Async.Reserve) void,
        setAspectRatio: *const fn (window: *Window, numer: c_int, denom: c_int, reserve: Async.Reserve) void,
        getWindowOpacity: *const fn (window: *Window, reserve: Async.Reserve) f32,
        setWindowOpacity: *const fn (window: *Window, opacity: f32, reserve: Async.Reserve) void,
        getWindowContentScale: *const fn (window: *Window, reserve: Async.Reserve) [2]f32,
        getWindowFrameSize: *const fn (window: *Window, reserve: Async.Reserve) [4]c_int,

        getClipboardString: *const fn (window: *Window, reserve: Async.Reserve) ?[:0]const u8,
        setClipboardString: *const fn (window: *Window, string: [:0]const u8, reserve: Async.Reserve) void,
        setWindowCursor: *const fn (window: *Window, cursor: ?*Cursor, reserve: Async.Reserve) void,

        getWindowInputModeUntyped: *const fn (window: *Window, mode: InputMode, reserve: Async.Reserve) c_int,
        setWindowInputModeUntyped: *const fn (window: *Window, mode: InputMode, value: c_int, reserve: Async.Reserve) void,

        // Callbacks
        setFramebufferSizeCallback: *const fn (window: *Window, callback: ?FramebufferSizeFn, reserve: Async.Reserve) ?FramebufferSizeFn,
        setSizeCallback: *const fn (window: *Window, callback: ?WindowSizeFn, reserve: Async.Reserve) ?WindowSizeFn,
        setPosCallback: *const fn (window: *Window, callback: ?WindowPosFn, reserve: Async.Reserve) ?WindowPosFn,
        setFocusCallback: *const fn (window: *Window, callback: ?WindowFocusFn, reserve: Async.Reserve) ?WindowFocusFn,
        setIconifyCallback: *const fn (window: *Window, callback: ?IconifyFn, reserve: Async.Reserve) ?IconifyFn,
        setContentScaleCallback: *const fn (window: *Window, callback: ?WindowContentScaleFn, reserve: Async.Reserve) ?WindowContentScaleFn,
        setCloseCallback: *const fn (window: *Window, callback: ?WindowCloseFn, reserve: Async.Reserve) ?WindowCloseFn,
        setKeyCallback: *const fn (window: *Window, callback: ?KeyFn, reserve: Async.Reserve) ?KeyFn,
        setCharCallback: *const fn (window: *Window, callback: ?CharFn, reserve: Async.Reserve) ?CharFn,
        setDropCallback: *const fn (window: *Window, callback: ?DropFn, reserve: Async.Reserve) ?DropFn,
        setMouseButtonCallback: *const fn (window: *Window, callback: ?MouseButtonFn, reserve: Async.Reserve) ?MouseButtonFn,
        setScrollCallback: *const fn (window: *Window, callback: ?ScrollFn, reserve: Async.Reserve) ?ScrollFn,
        setCursorPosCallback: *const fn (window: *Window, callback: ?CursorPosFn, reserve: Async.Reserve) ?CursorPosFn,
        setCursorEnterCallback: *const fn (window: *Window, callback: ?CursorEnterFn, reserve: Async.Reserve) ?CursorEnterFn,

        config: *anyopaque,
        config_t: fn () type,

        pub fn Config(self: Interface) self.config_t() {
            return @as(*self.config_t(), @ptrCast(@alignCast(self.config)));
        }
    };
}

pub fn Window(interface: type) type {
    return opaque {
        pub const Attribute = enum(c_int) {
            focused = 0x00020001,
            iconified = 0x00020002,
            resizable = 0x00020003,
            visible = 0x00020004,
            decorated = 0x00020005,
            auto_iconify = 0x00020006,
            floating = 0x00020007,
            maximized = 0x00020008,
            center_cursor = 0x00020009,
            transparent_framebuffer = 0x0002000A,
            hovered = 0x0002000B,
            focus_on_show = 0x0002000C,
            _,

            pub fn ValueType(comptime attribute: Attribute) type {
                return switch (attribute) {
                    .focused,
                    .iconified,
                    .resizable,
                    .visible,
                    .decorated,
                    .auto_iconify,
                    .floating,
                    .maximized,
                    .center_cursor,
                    .transparent_framebuffer,
                    .hovered,
                    .focus_on_show,
                    => bool,
                    else => c_int,
                };
            }
        };

        pub fn create(width: c_int, height: c_int, title: [:0]const u8, reserve: Async.Reserve) !*Window {
            return try interface.createWindow(width, height, title, reserve);
        }

        pub fn destroy(self: *Window, reserve: Async.Reserve) void {
            interface.destroyWindow(self, reserve);
        }

        pub fn shouldClose(self: *Window, reserve: Async.Reserve) bool {
            return interface.windowShouldClose(self, reserve);
        }

        pub fn setShouldClose(self: *Window, should_close: bool, reserve: Async.Reserve) void {
            interface.setWindowShouldClose(self, should_close, reserve);
        }

        pub fn setTitle(self: *Window, title: [:0]const u8, reserve: Async.Reserve) void {
            interface.setWindowTitle(self, title, reserve);
        }

        pub fn getSize(self: *Window, reserve: Async.Reserve) [2]c_int {
            return interface.getWindowSize(self, reserve);
        }

        pub fn setSize(self: *Window, width: c_int, height: c_int, reserve: Async.Reserve) void {
            interface.setWindowSize(self, width, height, reserve);
        }

        pub fn getFramebufferSize(self: *Window, reserve: Async.Reserve) [2]c_int {
            return interface.getWindowFramebufferSize(self, reserve);
        }

        pub fn getPos(self: *Window, reserve: Async.Reserve) [2]c_int {
            return interface.getWindowPos(self, reserve);
        }

        pub fn setPos(self: *Window, xpos: i32, ypos: i32, reserve: Async.Reserve) void {
            interface.setWindowPos(self, xpos, ypos, reserve);
        }

        pub fn swapBuffers(self: *Window, reserve: Async.Reserve) void {
            interface.swapBuffers(self, reserve);
        }

        pub fn getUserPointer(self: *Window, comptime T: type, reserve: Async.Reserve) ?*T {
            if (interface.getWindowUserPointer(self, reserve)) |ptr| {
                return @ptrCast(@alignCast(ptr));
            }
            return null;
        }

        pub fn setUserPointer(self: *Window, pointer: ?*anyopaque, reserve: Async.Reserve) void {
            interface.setWindowUserPointer(self, pointer, reserve);
        }

        pub fn getAttribute(self: *Window, comptime attrib: Attribute, reserve: Async.Reserve) Attribute.ValueType(attrib) {
            const val = interface.getWindowAttributeUntyped(self, attrib, reserve);
            return switch (Attribute.ValueType(attrib)) {
                bool => val != 0,
                else => val,
            };
        }

        pub fn setAttribute(self: *Window, comptime attrib: Attribute, value: Attribute.ValueType(attrib), reserve: Async.Reserve) void {
            const val: c_int = switch (Attribute.ValueType(attrib)) {
                bool => if (value) 1 else 0,
                else => value,
            };
            interface.setWindowAttributeUntyped(self, attrib, val, reserve);
        }

        pub fn iconify(self: *Window, reserve: Async.Reserve) void {
            interface.iconifyWindow(self, reserve);
        }

        pub fn restore(self: *Window, reserve: Async.Reserve) void {
            interface.restoreWindow(self, reserve);
        }

        pub fn maximize(self: *Window, reserve: Async.Reserve) void {
            interface.maximizeWindow(self, reserve);
        }

        pub fn show(self: *Window, reserve: Async.Reserve) void {
            interface.showWindow(self, reserve);
        }

        pub fn hide(self: *Window, reserve: Async.Reserve) void {
            interface.hideWindow(self, reserve);
        }

        pub fn focus(self: *Window, reserve: Async.Reserve) void {
            interface.focusWindow(self, reserve);
        }

        pub fn requestAttention(self: *Window, reserve: Async.Reserve) void {
            interface.requestWindowAttention(self, reserve);
        }

        pub fn getKey(self: *Window, key: Key, reserve: Async.Reserve) Action {
            return interface.getKey(self, key, reserve);
        }

        pub fn getMouseButton(self: *Window, button: MouseButton, reserve: Async.Reserve) Action {
            return interface.getMouseButton(self, button, reserve);
        }

        pub fn getCursorPos(self: *Window, reserve: Async.Reserve) [2]f64 {
            return interface.getCursorPos(self, reserve);
        }

        pub fn setCursorPos(self: *Window, xpos: f64, ypos: f64, reserve: Async.Reserve) void {
            interface.setCursorPos(self, xpos, ypos, reserve);
        }

        pub fn setSizeLimits(self: *Window, min_w: c_int, min_h: c_int, max_w: c_int, max_h: c_int, reserve: Async.Reserve) void {
            interface.setSizeLimits(self, min_w, min_h, max_w, max_h, reserve);
        }

        pub fn setAspectRatio(self: *Window, numer: c_int, denom: c_int, reserve: Async.Reserve) void {
            interface.setAspectRatio(self, numer, denom, reserve);
        }

        pub fn getOpacity(self: *Window, reserve: Async.Reserve) f32 {
            return interface.getWindowOpacity(self, reserve);
        }

        pub fn setOpacity(self: *Window, opacity: f32, reserve: Async.Reserve) void {
            interface.setWindowOpacity(self, opacity, reserve);
        }

        pub fn getContentScale(self: *Window, reserve: Async.Reserve) [2]f32 {
            return interface.getWindowContentScale(self, reserve);
        }

        pub fn getFrameSize(self: *Window, reserve: Async.Reserve) [4]c_int {
            return interface.getWindowFrameSize(self, reserve);
        }

        pub fn getClipboardString(self: *Window, reserve: Async.Reserve) ?[:0]const u8 {
            return interface.getClipboardString(self, reserve);
        }

        pub fn setClipboardString(self: *Window, string: [:0]const u8, reserve: Async.Reserve) void {
            interface.setClipboardString(self, string, reserve);
        }

        pub fn setCursor(self: *Window, cursor: ?*Cursor, reserve: Async.Reserve) void {
            interface.setWindowCursor(self, cursor, reserve);
        }

        pub fn getInputModeUntyped(self: *Window, mode: InputMode, reserve: Async.Reserve) c_int {
            return interface.getWindowInputModeUntyped(self, mode, reserve);
        }

        pub fn setInputModeUntyped(self: *Window, mode: InputMode, value: c_int, reserve: Async.Reserve) void {
            interface.setWindowInputModeUntyped(self, mode, value, reserve);
        }

        pub fn getInputMode(self: *Window, comptime mode: InputMode, reserve: Async.Reserve) switch (mode) {
            .cursor => CursorMode,
            else => bool,
        } {
            const val = self.getInputModeUntyped(mode, reserve);
            return switch (mode) {
                .cursor => @enumFromInt(val),
                else => val != 0,
            };
        }

        pub fn setInputMode(self: *Window, comptime mode: InputMode, value: switch (mode) {
            .cursor => CursorMode,
            else => bool,
        }, reserve: Async.Reserve) void {
            const val: c_int = switch (mode) {
                .cursor => @intFromEnum(value),
                else => if (value) 1 else 0,
            };
            self.setInputModeUntyped(mode, val, reserve);
        }

        // Callback Setters
        pub fn setFramebufferSizeCallback(self: *Window, callback: ?FramebufferSizeFn, reserve: Async.Reserve) ?FramebufferSizeFn {
            return interface.setFramebufferSizeCallback(self, callback, reserve);
        }

        pub fn setSizeCallback(self: *Window, callback: ?WindowSizeFn, reserve: Async.Reserve) ?WindowSizeFn {
            return interface.setSizeCallback(self, callback, reserve);
        }

        pub fn setPosCallback(self: *Window, callback: ?WindowPosFn, reserve: Async.Reserve) ?WindowPosFn {
            return interface.setPosCallback(self, callback, reserve);
        }

        pub fn setFocusCallback(self: *Window, callback: ?WindowFocusFn, reserve: Async.Reserve) ?WindowFocusFn {
            return interface.setFocusCallback(self, callback, reserve);
        }

        pub fn setIconifyCallback(self: *Window, callback: ?IconifyFn, reserve: Async.Reserve) ?IconifyFn {
            return interface.setIconifyCallback(self, callback, reserve);
        }

        pub fn setContentScaleCallback(self: *Window, callback: ?WindowContentScaleFn, reserve: Async.Reserve) ?WindowContentScaleFn {
            return interface.setContentScaleCallback(self, callback, reserve);
        }

        pub fn setCloseCallback(self: *Window, callback: ?WindowCloseFn, reserve: Async.Reserve) ?WindowCloseFn {
            return interface.setCloseCallback(self, callback, reserve);
        }

        pub fn setKeyCallback(self: *Window, callback: ?KeyFn, reserve: Async.Reserve) ?KeyFn {
            return interface.setKeyCallback(self, callback, reserve);
        }

        pub fn setCharCallback(self: *Window, callback: ?CharFn, reserve: Async.Reserve) ?CharFn {
            return interface.setCharCallback(self, callback, reserve);
        }

        pub fn setDropCallback(self: *Window, callback: ?DropFn, reserve: Async.Reserve) ?DropFn {
            return interface.setDropCallback(self, callback, reserve);
        }

        pub fn setMouseButtonCallback(self: *Window, callback: ?MouseButtonFn, reserve: Async.Reserve) ?MouseButtonFn {
            return interface.setMouseButtonCallback(self, callback, reserve);
        }

        pub fn setScrollCallback(self: *Window, callback: ?ScrollFn, reserve: Async.Reserve) ?ScrollFn {
            return interface.setScrollCallback(self, callback, reserve);
        }

        pub fn setCursorPosCallback(self: *Window, callback: ?CursorPosFn, reserve: Async.Reserve) ?CursorPosFn {
            return interface.setCursorPosCallback(self, callback, reserve);
        }

        pub fn setCursorEnterCallback(self: *Window, callback: ?CursorEnterFn, reserve: Async.Reserve) ?CursorEnterFn {
            return interface.setCursorEnterCallback(self, callback, reserve);
        }
    };
}
pub const Monitor = opaque {
    pub const getPrimary = zglfw.getPrimaryMonitor;
    pub const getAll = zglfw.getMonitors;
    pub const getName = zglfw.getMonitorName;
    pub const getVideoMode = zglfw.getVideoMode;
    pub const getVideoModes = zglfw.getVideoModes;
    pub const getPhysicalSize = zglfw.getMonitorPhysicalSize;
    pub const getUserPointer = zglfw.getMonitorUserPointer;
    pub const setUserPointer = zglfw.setMonitorUserPointer;

    pub fn getPos(self: *Monitor) [2]c_int {
        var xpos: c_int = 0;
        var ypos: c_int = 0;
        getMonitorPos(self, &xpos, &ypos);
        return .{ xpos, ypos };
    }

    pub const Event = enum(c_int) {
        connected = 0x00040001,
        disconnected = 0x00040002,
    };
};
