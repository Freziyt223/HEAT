const std = @import("std");
const atomic = std.atomic.Value;

const Engine = @import("Engine");
const GUI = Engine.GUI;
const Async = Engine.Async;
const TrackingAllocator = Engine.TrackingAllocator;
const Window = GUI.Window;
const Renderer = GUI.Renderer;
const ShaderModule = Renderer.ShaderModule;
const GraphicsPipeline = Renderer.GraphicsPipeline;
const VertexBuffer = Renderer.VertexBuffer;
const IndexBuffer = Renderer.IndexBuffer;
const vert = @embedFile("shaders/vert.spirv");
const frag = @embedFile("shaders/frag.spirv");
const VertexType = Renderer.MakeVertexType(2, f32, 3, f32);
const verticies = [_]VertexType{
    .{
        .position = .{ -0.5, -0.5 },
        .colour = .{ 1.0, 0.0, 0.0 },
    },
    .{
        .position = .{ 0.5, -0.5 },
        .colour = .{ 0.0, 1.0, 0.0 },
    },
    .{
        .position = .{ 0.5, 0.5 },
        .colour = .{ 0.0, 0.0, 1.0 },
    },
    .{
        .position = .{ -0.5, 0.5 },
        .colour = .{ 1.0, 1.0, 1.0 },
    },
};

const indicies = [_]u16{ 0, 1, 2, 2, 3, 0 };
pub var Allocator: TrackingAllocator = undefined;

const WindowContext = struct {
    window: ?*Window = null,
    renderer: ?Renderer = null,

    shaders: [2]?ShaderModule = .{
        null,
        null,
    },

    graphicsPipeline: ?GraphicsPipeline = null,
    index_buffer: ?IndexBuffer = null,
    vertex_buffer: ?VertexBuffer = null,

    is_window_available: atomic(bool) = .init(false),
    is_renderer_available: atomic(bool) = .init(false),
    is_graphics_pipeline_available: atomic(bool) = .init(false),
    is_index_buffer_available: atomic(bool) = .init(false),
    is_vertex_buffer_available: atomic(bool) = .init(false),
    is_shaders_available: atomic(bool) = .init(false),

    is_destroyed: atomic(bool) = .init(false),
    update_running: atomic(bool) = .init(false),
    closing: atomic(bool) = .init(false),

    pub fn init(
        self: *WindowContext,
        i: usize,
        impl: GUI.Interface,
    ) !void {
        const allocator = Allocator.allocator();

        const title = try std.fmt.allocPrintSentinel(
            allocator,
            "Window {}",
            .{i},
            0,
        );
        defer allocator.free(title);

        const window_handle = try Window.create(
            800,
            800,
            title,
            null,
            null,
        );

        const window = window_handle orelse
            return error.WindowIsNull;

        errdefer window.destroy();

        const renderer = try window.setupRenderer(
            impl,
            @intCast(i),
        );

        errdefer renderer.deinit();

        const vertex_shader =
            try renderer.createShaderModule(vert);

        errdefer renderer.destroyShaderModule(vertex_shader);

        const fragment_shader =
            try renderer.createShaderModule(frag);

        errdefer renderer.destroyShaderModule(fragment_shader);
        const bindings = [_]Renderer.VertexBinding{VertexType.getBindingDescription()};
        const attributes = VertexType.getAttributeDescription();
        const pipeline =
            try renderer.createGraphicsPipeline(.{
                .vertex_shader = vertex_shader,
                .fragment_shader = fragment_shader,
                .vertex_input = .{
                    .bindings = &bindings,
                    .attributes = &attributes,
                },
                .front_face = .clockwise,
            });

        errdefer renderer.destroyGraphicsPipeline(pipeline);
        const index_buffer =
            try renderer.createIndexBuffer(u16, indicies[0..]);
        const buffer =
            try renderer.createVertexBuffer(VertexType, verticies[0..]);
        self.window = window;
        self.renderer = renderer;

        self.shaders = .{
            vertex_shader,
            fragment_shader,
        };

        self.graphicsPipeline = pipeline;
        self.index_buffer = index_buffer;
        self.vertex_buffer = buffer;

        self.is_window_available.store(true, .release);
        self.is_renderer_available.store(true, .release);
        self.is_shaders_available.store(true, .release);
        self.is_graphics_pipeline_available.store(true, .release);
        self.is_index_buffer_available.store(true, .release);
        self.is_vertex_buffer_available.store(true, .release);

        self.closing.store(false, .release);
        self.is_destroyed.store(false, .release);
    }

    pub fn requestClose(self: *WindowContext) void {
        self.closing.store(true, .release);
    }

    pub fn deinit(self: *WindowContext) void {
        if (self.is_destroyed.swap(true, .acq_rel)) {
            return;
        }

        self.is_window_available.store(false, .release);
        self.is_renderer_available.store(false, .release);
        self.is_graphics_pipeline_available.store(false, .release);
        self.is_shaders_available.store(false, .release);

        const renderer = self.renderer;
        const window = self.window;

        self.closing.store(true, .release);

        if (renderer) |r| {
            r.deinit();
        }

        if (window) |w| {
            w.destroy();
        }

        self.renderer = null;
        self.window = null;
    }
};

const WindowAlloc = struct {
    ctx: WindowContext = .{},
    node: std.DoublyLinkedList.Node = .{},
};

var WindowContexts: std.DoublyLinkedList = .{};

const ThreadContext = struct {
    pub const FutureType =
        Async.Future(
            @typeInfo(@TypeOf(update_fn)).@"fn".return_type.?,
        );

    i: usize = 0,

    windowContext: *WindowAlloc = undefined,

    thread: Async.Reserve,
    handle: Async.Scheduler.Scheduler.Handle = undefined,

    future: FutureType = .{},

    initialized: atomic(bool) = .init(false),
    close_requested: atomic(bool) = .init(false),
    destroyed: atomic(bool) = .init(false),

    pub fn create(i: usize) !ThreadContext {
        return .{
            .i = i,
            .thread = try Async.reserve(@intCast(i), false),
        };
    }

    pub fn init(
        self: *ThreadContext,
        impl: GUI.Interface,
    ) !void {
        const allocator = Allocator.allocator();

        const window = try allocator.create(WindowAlloc);
        errdefer allocator.destroy(window);

        window.* = .{};

        self.windowContext = window;

        try self.windowContext.ctx.init(
            self.i,
            impl,
        );

        WindowContexts.append(
            &self.windowContext.node,
        );

        errdefer {
            WindowContexts.remove(
                &self.windowContext.node,
            );

            self.windowContext.ctx.deinit();
            allocator.destroy(self.windowContext);
        }

        self.handle = try Async.scheduleRepeated(
            call_update,
            .{self},
            .fromMicroseconds(8333),
        );

        self.initialized.store(true, .release);
    }
    pub fn requestClose(self: *ThreadContext) void {
        if (self.destroyed.load(.acquire)) {
            return;
        }

        self.close_requested.store(true, .release);
        self.windowContext.ctx.requestClose();
    }
    pub fn deinit(self: *ThreadContext) void {
        if (self.destroyed.swap(true, .acq_rel)) {
            return;
        }
        self.handle.cancel();

        const allocator = Allocator.allocator();

        self.windowContext.ctx.deinit();

        WindowContexts.remove(
            &self.windowContext.node,
        );

        allocator.destroy(self.windowContext);

        const full: *ThreadAlloc =
            @fieldParentPtr("ctx", self);

        Threads.remove(&full.node);

        allocator.destroy(full);
    }

    pub fn call_update(self: *ThreadContext) !void {
        if (self.destroyed.load(.acquire)) {
            return;
        }

        if (self.close_requested.load(.acquire)) {
            return;
        }

        const ctx = &self.windowContext.ctx;

        if (ctx.is_destroyed.load(.acquire)) {
            return;
        }
        if (ctx.update_running.swap(true, .acq_rel)) {
            return;
        }

        self.thread.call(
            update_fn,
            .{self},
            void,
            null,
        ) catch |err| {
            ctx.update_running.store(false, .release);

            std.debug.print(
                "Error in self.thread.call: {}!\n",
                .{err},
            );
        };
    }

    fn update_fn(self: *ThreadContext) !void {
        const ctx = &self.windowContext.ctx;

        defer ctx.update_running.store(
            false,
            .release,
        );

        if (self.destroyed.load(.acquire)) {
            return;
        }

        if (self.close_requested.load(.acquire)) {
            return;
        }

        if (ctx.is_destroyed.load(.acquire)) {
            return;
        }

        if (!ctx.is_window_available.load(.acquire)) {
            return;
        }

        const window = ctx.window orelse return;

        if (window.shouldClose()) {
            self.requestClose();
            return;
        }

        if (!ctx.is_renderer_available.load(.acquire)) {
            return;
        }

        const renderer = ctx.renderer orelse return;

        if (!ctx.is_graphics_pipeline_available.load(.acquire) or !ctx.is_vertex_buffer_available.load(.acquire)) {
            return;
        }
        const pipeline = ctx.graphicsPipeline orelse return;
        const index_buffer = ctx.index_buffer orelse return;
        const vertex_buffer = ctx.vertex_buffer orelse return;
        var frame = try renderer.beginFrame();

        try frame.bindPipeline(pipeline);
        try frame.bindIndexBuffer(index_buffer);
        try frame.bindVertexBuffer(vertex_buffer);
        try frame.draw(indicies.len, 1);
        try frame.end();
        try frame.present();
    }
};

const ThreadAlloc = struct {
    ctx: ThreadContext,
    node: std.DoublyLinkedList.Node,
};

var Threads: std.DoublyLinkedList = .{};

pub fn init(Init: Engine.Init) !void {
    Allocator = TrackingAllocator.init(
        Init.allocator,
        "BasicWindow",
    );

    const allocator = Allocator.allocator();

    const renderer =
        (try GUI.renderer(.vulkan)).?;

    inline for (0..2) |i| {
        const thread =
            try allocator.create(ThreadAlloc);

        errdefer allocator.destroy(thread);

        thread.* = .{
            .ctx = try ThreadContext.create(i),
            .node = .{},
        };

        Threads.append(&thread.node);

        try thread.ctx.init(renderer);
    }
}

pub fn deinit() void {
    var node = Threads.first;

    while (node) |current| {
        const full: *ThreadAlloc =
            @fieldParentPtr("node", current);

        full.ctx.requestClose();

        node = current.next;
    }
    node = Threads.first;

    while (node) |current| {
        const full: *ThreadAlloc =
            @fieldParentPtr("node", current);

        full.ctx.handle.cancel();

        node = current.next;
    }
}

pub const update = struct {
    pub var finished: atomic(bool) = .init(true);

    pub fn update() !void {
        var node = Threads.first;

        while (node) |current| {
            const full: *ThreadAlloc =
                @fieldParentPtr("node", current);

            const ctx = &full.ctx;

            if (ctx.close_requested.load(.acquire)) {
                if (ctx.windowContext.ctx.update_running.load(.acquire)) {
                    node = current.next;
                    continue;
                }

                ctx.handle.cancel();
                ctx.deinit();
                node = Threads.first;
                continue;
            }

            node = current.next;
        }

        if (Threads.len() == 0) {
            Engine.State.store(
                .Quitting,
                .release,
            );
        }
    }

    pub const tick_rate: ?std.Io.Duration =
        .fromMicroseconds(8333);
};
