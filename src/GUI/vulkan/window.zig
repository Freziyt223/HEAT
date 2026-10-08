const std = @import("std");
const vulkan = @import("vulkan");
const glfw = @import("glfw");
const Interface = @import("Interface");
const shared = @import("root.zig");
const Self = @This();
const GraphicsContext = @import("global.zig");

graphics_mutex: std.Io.Mutex = .init,
window: *Interface.Window,

allocator: std.mem.Allocator,

// ------------------------------------------------------------
// Queue
// ------------------------------------------------------------

queue_index: u32,

graphics_queue: vulkan.Queue,

present_queue: vulkan.Queue,

// ------------------------------------------------------------
// Resources
// ------------------------------------------------------------

shader_modules: std.ArrayListUnmanaged(ShaderResource) = .empty,

graphics_pipelines: std.ArrayListUnmanaged(GraphicsPipelineResource) = .empty,

index_buffer: std.ArrayListUnmanaged(IndexBufferResource) = .empty,
vertex_buffers: std.ArrayListUnmanaged(VertexBufferResource) = .empty,

// ------------------------------------------------------------
// Objects
// ------------------------------------------------------------

surface: vulkan.SurfaceKHR = .null_handle,

device: *shared.DeviceInfo,

device_type: std.atomic.Value(DeviceType) = .init(.global),

swapchain: vulkan.SwapchainKHR = .null_handle,

swapchain_images: []vulkan.Image = &.{},

swapchain_image_views: []vulkan.ImageView = &.{},

swapchain_format: vulkan.Format,

swapchain_extent: vulkan.Extent2D,

pipeline_layout: vulkan.PipelineLayout = .null_handle,

render_pass: vulkan.RenderPass = .null_handle,

command_pool: vulkan.CommandPool = .null_handle,

command_buffer: vulkan.CommandBuffer = .null_handle,

framebuffers: []vulkan.Framebuffer = &.{},

image_available_semaphore: vulkan.Semaphore = .null_handle,

render_finished_semaphores: []vulkan.Semaphore = undefined,

in_flight_fence: vulkan.Fence = .null_handle,

resized: bool = false,

current_image: u32 = 0,

frame_state: std.atomic.Value(Interface.Renderer.FrameState) = .init(.idle),

// Rendering variables
rasterizaton_samples: vulkan.SampleCountFlags = .{ .@"1_bit" = true },

const DeviceType = enum(u8) {
    global,
    local,
};

pub const ShaderResource = struct {
    handle: vulkan.ShaderModule = .null_handle,
    generation: u32 = 1,
};

pub const GraphicsPipelineResource = struct {
    handle: vulkan.Pipeline = .null_handle,
    layout: vulkan.PipelineLayout = .null_handle,
    generation: u32 = 1,
};
pub const VertexBufferResource = struct {
    handle: vulkan.Buffer = .null_handle,
    memory: vulkan.DeviceMemory = .null_handle,
    size: vulkan.DeviceSize = 0,
    generation: u32 = 1,
};
pub const IndexBufferResource = struct {
    handle: vulkan.Buffer = .null_handle,
    memory: vulkan.DeviceMemory = .null_handle,
    size: vulkan.DeviceSize = 0,
    generation: u32 = 1,
};

pub fn init(
    allocator: std.mem.Allocator,
    global: *GraphicsContext,
    window: *Interface.Window,
    queue_index: u32,
) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .window = window,
        .allocator = allocator,
        .queue_index = queue_index,
        .graphics_queue = .null_handle,
        .present_queue = .null_handle,
        .device = undefined,
        .swapchain_format = undefined,
        .swapchain_extent = undefined,
    };
    glfw.setWindowUserPointer(@ptrCast(@alignCast(window)), @ptrCast(@alignCast(self)));
    _ = glfw.setFramebufferSizeCallback(@ptrCast(@alignCast(window)), &frameBufferCallback);

    errdefer self.deinit(global);

    try self.createSurface(global);

    try self.initDevice(
        null,
        global,
    );

    self.graphics_queue =
        self.device.device.getDeviceQueue(
            self.device
                .queueFamilyIndices
                .graphics_family,
            queue_index,
        );

    self.present_queue =
        self.device.device.getDeviceQueue(
            self.device
                .queueFamilyIndices
                .present_family,
            queue_index,
        );

    try self.createSwapchain(global);
    try self.createImageViews();
    try self.createRenderPass();
    try self.createFramebuffers();
    try self.createCommandPool();
    try self.createCommandBuffer();
    try self.createSyncObjects();

    return self;
}
pub fn deinit(self: *Self, global: *GraphicsContext) void {
    while (true) {
        switch (self.frame_state.load(.acquire)) {
            .idle => {
                if (self.frame_state.cmpxchgStrong(
                    .idle,
                    .destroyed,
                    .acq_rel,
                    .acquire,
                ) == null) {
                    break;
                }
            },

            .recording, .closing => {
                std.atomic.spinLoopHint();
            },

            .destroyed => return,
        }
    }

    self.device.device.deviceWaitIdle() catch |err| {
        std.debug.print(
            "deviceWaitIdle failed during Self.deinit: {}\n",
            .{err},
        );
        return;
    };
    self.destroyCommandPool();
    self.destroySyncObjects();
    for (self.graphics_pipelines.items) |item| {
        if (item.handle != .null_handle) {
            self.device.device.destroyPipeline(item.handle, null);
        }

        if (item.layout != .null_handle) {
            self.device.device.destroyPipelineLayout(item.layout, null);
        }
    }

    for (self.shader_modules.items) |item| {
        if (item.handle != .null_handle) {
            self.device.device.destroyShaderModule(item.handle, null);
        }
    }

    for (self.index_buffer.items) |item| {
        if (item.handle != .null_handle) {
            self.device.device.destroyBuffer(item.handle, null);
        }

        if (item.memory != .null_handle) {
            self.device.device.freeMemory(item.memory, null);
        }
    }

    for (self.vertex_buffers.items) |item| {
        if (item.handle != .null_handle) {
            self.device.device.destroyBuffer(item.handle, null);
        }

        if (item.memory != .null_handle) {
            self.device.device.freeMemory(item.memory, null);
        }
    }

    self.graphics_pipelines.deinit(self.allocator);
    self.shader_modules.deinit(self.allocator);
    self.index_buffer.deinit(self.allocator);
    self.vertex_buffers.deinit(self.allocator);

    self.destroyFramebuffers();
    self.destroyRenderPass();
    self.destroyImageViews();
    self.destroySwapchain();
    self.destroySurface(global);

    self.allocator.destroy(self);
}
fn frameBufferCallback(window: ?*glfw.Window, _: c_int, _: c_int) callconv(.c) void {
    if (window) |w| {
        const self: ?*Self = w.getUserPointer(Self);
        if (self) |s| {
            s.resized = true;
        }
    }
}

// ============================================================
// Surface
// ============================================================

fn createSurface(self: *Self, global: *GraphicsContext) !void {
    try glfw.createWindowSurface(
        global.instance.handle,
        @ptrCast(
            @alignCast(self.window),
        ),
        null,
        &self.surface,
    );
}

fn destroySurface(self: *Self, global: *GraphicsContext) void {
    if (self.surface != .null_handle) {
        global.instance.destroySurfaceKHR(
            self.surface,
            null,
        );
        self.surface = .null_handle;
    }
}

// ============================================================
// Device
// ============================================================

pub fn selectPhysicalDevice(
    self: *Self,
    selection: ?Interface.DeviceSelection,
    global: *GraphicsContext,
) !void {
    if (selection) {
        self.deinitDevice();
        errdefer self.deinitDevice();

        try self.initDevice(
            selection,
            global,
        );

        self.graphics_queue =
            self.device.device.getDeviceQueue(
                self.device
                    .queueFamilyIndices
                    .graphics_family,
                self.queue_index,
            );

        self.present_queue =
            self.device.device.getDeviceQueue(
                self.device
                    .queueFamilyIndices
                    .present_family,
                self.queue_index,
            );
    } else {
        self.device_type.store(
            .global,
            .release,
        );

        self.device = global.device;

        self.graphics_queue =
            self.device.device.getDeviceQueue(
                self.device
                    .queueFamilyIndices
                    .graphics_family,
                self.queue_index,
            );

        self.present_queue =
            self.device.device.getDeviceQueue(
                self.device
                    .queueFamilyIndices
                    .present_family,
                self.queue_index,
            );
    }
}

fn initDevice(
    self: *Self,
    selection: ?Interface.DeviceSelection,
    global: *GraphicsContext,
) !void {
    if (selection) |select| {
        const device =
            try global.pickPhysicalDevice(
                select,
                self.surface,
            );

        self.device = device;
        self.device_type.store(
            .local,
            .release,
        );
        return;
    }

    self.device_type.store(
        .global,
        .release,
    );

    self.device = global.device;
}

fn deinitDevice(self: *Self) void {
    if (self.device_type.load(.acquire) == .local) {
        if (self.device.device != .null_handle) {
            self.device.device.destroyDevice(null);
            self.device.device = .null_handle;
        }
    }
}

// ============================================================
// Swapchain
// ============================================================

fn createSwapchain(self: *Self, global: *GraphicsContext) !void {
    const capabilities =
        try global.instance
            .getPhysicalDeviceSurfaceCapabilitiesKHR(
            self.device.physicalDevice,
            self.surface,
        );

    var image_count_create = capabilities.min_image_count + 1;

    if (capabilities.max_image_count != 0)
        image_count_create = @min(image_count_create, capabilities.max_image_count);

    const queue_families = [_]u32{
        self.device.queueFamilyIndices.graphics_family,
        self.device.queueFamilyIndices.present_family,
    };

    const separate_families =
        self.device.queueFamilyIndices.graphics_family != self.device.queueFamilyIndices.present_family;

    const CreateInfo =
        vulkan.SwapchainCreateInfoKHR{
            .s_type = .swapchain_create_info_khr,
            .surface = self.surface,
            .min_image_count = image_count_create,
            .image_format = .b8g8r8a8_srgb,
            .image_color_space = .srgb_nonlinear_khr,
            .image_extent = capabilities.current_extent,
            .image_array_layers = 1,
            .image_usage = .{
                .color_attachment_bit = true,

                .transfer_dst_bit = true,
            },

            .image_sharing_mode = if (separate_families) .concurrent else .exclusive,
            .queue_family_index_count = if (separate_families) 2 else 0,
            .p_queue_family_indices = if (separate_families) &queue_families else null,
            .pre_transform = capabilities.current_transform,

            .composite_alpha = .{
                .opaque_bit_khr = true,
            },

            .present_mode = .fifo_khr,
            .clipped = .true,
            .old_swapchain = .null_handle,
        };

    self.swapchain =
        try self.device.device.createSwapchainKHR(
            &CreateInfo,
            null,
        );

    var image_count: u32 = 0;

    _ = try self.device.device
        .getSwapchainImagesKHR(
        self.swapchain,
        &image_count,
        null,
    );

    self.swapchain_images =
        try self.allocator.alloc(
            vulkan.Image,
            image_count,
        );

    _ = try self.device.device
        .getSwapchainImagesKHR(
        self.swapchain,
        &image_count,
        self.swapchain_images.ptr,
    );

    self.swapchain_extent = capabilities.current_extent;
    self.swapchain_format = CreateInfo.image_format;
}

fn destroySwapchain(self: *Self) void {
    if (self.swapchain != .null_handle) {
        self.device.device.destroySwapchainKHR(
            self.swapchain,
            null,
        );

        self.swapchain = .null_handle;
    }

    if (self.swapchain_images.len != 0) {
        self.allocator.free(self.swapchain_images);
        self.swapchain_images = &.{};
    }
}

fn recreateSwapChain(self: *Self, global: *GraphicsContext) !void {
    // Resize wait
    var width, var height = blk: {
        const size = self.window.getFramebufferSize();
        break :blk .{ size[0], size[1] };
    };
    while (width == 0 or height == 0) {
        width, height = blk: {
            const size = self.window.getFramebufferSize();
            break :blk .{ size[0], size[1] };
        };
        glfw.waitEvents();
        try self.device.device.deviceWaitIdle();
    }
    try self.device.device.deviceWaitIdle();

    self.destroyFramebuffers();
    self.destroyImageViews();
    self.destroySwapchain();
    try self.createSwapchain(global);
    try self.createImageViews();
    try self.createFramebuffers();
}

// ============================================================
// Image views
// ============================================================

fn createImageViews(self: *Self) !void {
    self.swapchain_image_views =
        try self.allocator.alloc(
            vulkan.ImageView,
            self.swapchain_images.len,
        );

    for (0..self.swapchain_image_views.len) |i| {
        const ImageViewCreateInfo =
            vulkan.ImageViewCreateInfo{
                .s_type = .image_view_create_info,
                .image = self.swapchain_images[i],
                .view_type = .@"2d",
                .format = self.swapchain_format,
                .components = .{
                    .r = .identity,
                    .g = .identity,
                    .b = .identity,
                    .a = .identity,
                },

                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            };

        self.swapchain_image_views[i] =
            try self.device.device
                .createImageView(
                &ImageViewCreateInfo,
                null,
            );
    }
}

fn destroyImageViews(self: *Self) void {
    for (self.swapchain_image_views) |image_view| {
        if (image_view != .null_handle) {
            self.device.device.destroyImageView(
                image_view,
                null,
            );
        }
    }

    if (self.swapchain_image_views.len != 0) {
        self.allocator.free(self.swapchain_image_views);
        self.swapchain_image_views = &.{};
    }
}

// ============================================================
// Render pass
// ============================================================

fn createRenderPass(self: *Self) !void {
    const ColorAttachment =
        vulkan.AttachmentDescription{
            .format = .b8g8r8a8_srgb,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        };

    const ColorAttachmentRef =
        vulkan.AttachmentReference{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        };

    const Subpass =
        vulkan.SubpassDescription{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &.{ColorAttachmentRef},
        };

    const Dependency =
        vulkan.SubpassDependency{
            .src_subpass = vulkan.SUBPASS_EXTERNAL,
            .dst_subpass = 0,

            .src_stage_mask = .{
                .color_attachment_output_bit = true,
            },

            .src_access_mask = .{},

            .dst_stage_mask = .{
                .color_attachment_output_bit = true,
            },

            .dst_access_mask = .{
                .color_attachment_write_bit = true,
            },
        };

    const CreateInfo =
        vulkan.RenderPassCreateInfo{
            .s_type = .render_pass_create_info,
            .p_subpasses = &.{Subpass},
            .subpass_count = 1,
            .p_attachments = &.{ColorAttachment},
            .attachment_count = 1,
            .p_dependencies = &.{Dependency},
            .dependency_count = 1,
        };

    self.render_pass =
        try self.device.device.createRenderPass(
            &CreateInfo,
            null,
        );
}

fn destroyRenderPass(self: *Self) void {
    if (self.render_pass != .null_handle) {
        self.device.device.destroyRenderPass(
            self.render_pass,
            null,
        );

        self.render_pass = .null_handle;
    }
}

// ============================================================
// Shaders
// ============================================================

pub fn createShaderModule(self: *Self, spirv: []const u8) !Interface.Renderer.ShaderModule {
    if (spirv.len == 0) return error.EmptyShader;
    if (spirv.len % 4 != 0) return error.WrongShaderAlignment;

    const code =
        try self.allocator.alignedAlloc(
            u32,
            std.mem.Alignment.fromByteUnits(
                @alignOf(u32),
            ),
            spirv.len / 4,
        );

    defer self.allocator.free(code);

    @memcpy(std.mem.sliceAsBytes(code), spirv);

    const create_info =
        vulkan.ShaderModuleCreateInfo{
            .s_type = .shader_module_create_info,
            .code_size = spirv.len,
            .p_code = code.ptr,
        };

    const handle =
        try self.device.device
            .createShaderModule(
            &create_info,
            null,
        );

    const resource = ShaderResource{
        .handle = handle,
        .generation = 1,
    };

    const index: u32 = @intCast(self.shader_modules.items.len);

    errdefer self.device.device
        .destroyShaderModule(
        handle,
        null,
    );

    try self.shader_modules.append(
        self.allocator,
        resource,
    );

    return .{
        .index = index,
        .generation = resource.generation,
    };
}

pub fn destroyShaderModule(self: *Self, shader: Interface.Renderer.ShaderModule) void {
    const resource = self.getShaderModule(shader) catch return;
    self.device.device.destroyShaderModule(
        resource.handle,
        null,
    );
    resource.handle = .null_handle;
    resource.generation +%= 1;
}

// ============================================================
// Graphics pipeline
// ============================================================

pub fn createGraphicsPipeline(self: *Self, info: Interface.Renderer.GraphicsPipelineCreateInfo) !Interface.Renderer.GraphicsPipeline {
    const vertex_module =
        try self.getShaderModule(info.vertex_shader);

    const fragment_module =
        try self.getShaderModule(info.fragment_shader);

    // ------------------------------------------------------------
    // Vertex input
    // ------------------------------------------------------------
    const bindings = try self.allocator.alloc(
        vulkan.VertexInputBindingDescription,
        info.vertex_input.bindings.len,
    );
    defer self.allocator.free(bindings);

    for (info.vertex_input.bindings, bindings) |source, *target| {
        target.* = .{
            .binding = source.binding,
            .stride = source.stride,
            .input_rate = switch (source.input_rate) {
                .vertex => .vertex,
                .instance => .instance,
            },
        };
    }

    const attributes = try self.allocator.alloc(
        vulkan.VertexInputAttributeDescription,
        info.vertex_input.attributes.len,
    );
    defer self.allocator.free(attributes);

    for (info.vertex_input.attributes, attributes) |source, *target| {
        target.* = .{
            .location = source.location,
            .binding = source.binding,
            .format = vertexFormat(source.format),
            .offset = source.offset,
        };
    }

    const vertex_input = vulkan.PipelineVertexInputStateCreateInfo{
        .s_type = .pipeline_vertex_input_state_create_info,

        .vertex_binding_description_count = @intCast(bindings.len),
        .p_vertex_binding_descriptions = if (bindings.len != 0)
            bindings.ptr
        else
            null,

        .vertex_attribute_description_count = @intCast(attributes.len),
        .p_vertex_attribute_descriptions = if (attributes.len != 0)
            attributes.ptr
        else
            null,
    };
    // ------------------------------------------------------------
    // Shader stages
    // ------------------------------------------------------------

    const stages =
        [_]vulkan.PipelineShaderStageCreateInfo{
            .{
                .s_type = .pipeline_shader_stage_create_info,
                .stage = .{
                    .vertex_bit = true,
                },
                .module = vertex_module.handle,
                .p_name = "main",
            },
            .{
                .s_type = .pipeline_shader_stage_create_info,
                .stage = .{
                    .fragment_bit = true,
                },
                .module = fragment_module.handle,
                .p_name = "main",
            },
        };

    // ------------------------------------------------------------
    // Input assembly
    // ------------------------------------------------------------

    const input_assembly =
        vulkan.PipelineInputAssemblyStateCreateInfo{
            .s_type = .pipeline_input_assembly_state_create_info,
            .topology = primitiveTopology(info.topology),
            .primitive_restart_enable = .false,
        };

    // ------------------------------------------------------------
    // Viewport / scissor
    //
    // They are dynamic and are set in beginFrame().
    // ------------------------------------------------------------

    const viewport_state =
        vulkan.PipelineViewportStateCreateInfo{
            .s_type = .pipeline_viewport_state_create_info,

            .viewport_count = 1,
            .scissor_count = 1,

            .p_viewports = null,
            .p_scissors = null,
        };

    // ------------------------------------------------------------
    // Rasterizer
    // ------------------------------------------------------------

    const rasterizer =
        vulkan.PipelineRasterizationStateCreateInfo{
            .s_type = .pipeline_rasterization_state_create_info,
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .line_width = 1.0,

            .cull_mode = switch (info.cull_mode) {
                .none => .{},
                .back => .{ .back_bit = true },
                .front => .{ .front_bit = true },
                .front_and_back => .{ .back_bit = true, .front_bit = true },
            },
            .front_face = switch (info.front_face) {
                .clockwise => .clockwise,
                .counter_clockwise => .counter_clockwise,
            },

            .depth_bias_enable = .false,

            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
        };

    // ------------------------------------------------------------
    // Multisampling
    // ------------------------------------------------------------

    const multisample =
        vulkan.PipelineMultisampleStateCreateInfo{
            .s_type = .pipeline_multisample_state_create_info,
            .sample_shading_enable = .false,
            .min_sample_shading = 1.0,
            .rasterization_samples = self.rasterizaton_samples,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };

    const depth_stencil =
        vulkan.PipelineDepthStencilStateCreateInfo{
            .s_type = .pipeline_depth_stencil_state_create_info,

            .depth_test_enable = if (info.depth_test) .true else .false,
            .depth_write_enable = if (info.depth_write) .true else .false,
            .depth_compare_op = .less,
            .depth_bounds_test_enable = .false,
            .stencil_test_enable = .false,

            .front = .{
                .fail_op = .keep,
                .pass_op = .keep,
                .depth_fail_op = .keep,
                .compare_op = .always,

                .compare_mask = 0,
                .write_mask = 0,
                .reference = 0,
            },

            .back = .{
                .fail_op = .keep,
                .pass_op = .keep,
                .depth_fail_op = .keep,
                .compare_op = .always,

                .compare_mask = 0,
                .write_mask = 0,
                .reference = 0,
            },

            .min_depth_bounds = 0.0,
            .max_depth_bounds = 1.0,
        };

    // ------------------------------------------------------------
    // Color blending
    // ------------------------------------------------------------

    const blend_attachment = blk: {
        if (info.blend.enabled) {
            break :blk vulkan.PipelineColorBlendAttachmentState{
                .blend_enable = .true,

                .src_color_blend_factor = .src_alpha,
                .dst_color_blend_factor = .one_minus_src_alpha,
                .color_blend_op = .add,

                .src_alpha_blend_factor = .one,
                .dst_alpha_blend_factor = .one_minus_src_alpha,
                .alpha_blend_op = .add,

                .color_write_mask = .{
                    .r_bit = true,
                    .g_bit = true,
                    .b_bit = true,
                    .a_bit = true,
                },
            };
        } else {
            break :blk vulkan.PipelineColorBlendAttachmentState{
                .blend_enable = .false,

                .src_color_blend_factor = .one,
                .dst_color_blend_factor = .zero,
                .color_blend_op = .add,

                .src_alpha_blend_factor = .one,
                .dst_alpha_blend_factor = .zero,
                .alpha_blend_op = .add,

                .color_write_mask = .{
                    .r_bit = true,
                    .g_bit = true,
                    .b_bit = true,
                    .a_bit = true,
                },
            };
        }
    };
    const blend =
        vulkan.PipelineColorBlendStateCreateInfo{
            .s_type = .pipeline_color_blend_state_create_info,

            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = &.{blend_attachment},
            .blend_constants = .{
                0.0,
                0.0,
                0.0,
                0.0,
            },
        };

    // ------------------------------------------------------------
    // Dynamic state
    // ------------------------------------------------------------

    const dynamic_states = [_]vulkan.DynamicState{ .viewport, .scissor };

    const dynamic_state =
        vulkan.PipelineDynamicStateCreateInfo{
            .s_type = .pipeline_dynamic_state_create_info,
            .dynamic_state_count = dynamic_states.len,
            .p_dynamic_states = &dynamic_states,
        };

    const layout =
        try self.device.device.createPipelineLayout(
            &.{
                .s_type = .pipeline_layout_create_info,

                .set_layout_count = 0,
                .p_set_layouts = null,

                .push_constant_range_count = 0,
                .p_push_constant_ranges = null,
            },
            null,
        );

    errdefer self.device.device.destroyPipelineLayout(
        layout,
        null,
    );

    // ------------------------------------------------------------
    // Graphics pipeline
    // ------------------------------------------------------------

    var native_pipelines = [_]vulkan.Pipeline{.null_handle};

    const pipeline_info =
        vulkan.GraphicsPipelineCreateInfo{
            .s_type = .graphics_pipeline_create_info,

            .stage_count = stages.len,
            .p_stages = &stages,

            .p_vertex_input_state = &vertex_input,
            .p_input_assembly_state = &input_assembly,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &rasterizer,
            .p_multisample_state = &multisample,
            .p_depth_stencil_state = &depth_stencil,
            .p_color_blend_state = &blend,
            .p_dynamic_state = &dynamic_state,
            .layout = layout,
            .render_pass = self.render_pass,

            .subpass = 0,

            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

    _ = try self.device.device.createGraphicsPipelines(
        .null_handle,
        &.{pipeline_info},
        null,
        &native_pipelines,
    );

    const native_pipeline = native_pipelines[0];

    errdefer self.device.device.destroyPipeline(
        native_pipeline,
        null,
    );
    const index: u32 = @intCast(self.graphics_pipelines.items.len);

    try self.graphics_pipelines.append(self.allocator, .{
        .handle = native_pipeline,
        .layout = layout,
    });

    return .{
        .index = index,
        .generation = self.graphics_pipelines.items[index].generation,
    };
}

pub fn destroyGraphicsPipeline(self: *Self, pipeline: Interface.Renderer.GraphicsPipeline) void {
    const resource = self.getGraphicsPipeline(pipeline) catch return;
    self.device.device.destroyPipeline(resource.handle, null);
    self.device.device.destroyPipelineLayout(resource.layout, null);

    resource.handle = .null_handle;
    resource.layout = .null_handle;
    resource.generation +%= 1;
}

// ============================================================
// Vertex buffer
// ============================================================

pub fn createVertexBuffer(
    self: *Self,
    global: *GraphicsContext,
    indicies: []const u8,
) !Interface.Renderer.VertexBuffer {
    if (indicies.len == 0) return error.EmptyVertexBuffer;

    var stagingBuffer: vulkan.Buffer = undefined;
    var stagingMemory: vulkan.DeviceMemory = undefined;
    try self.createBuffer(
        global,
        indicies.len,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &stagingBuffer,
        &stagingMemory,
    );

    const data =
        try self.device.device.mapMemory(
            stagingMemory,
            0,
            indicies.len,
            .{},
        );

    if (data) |d| {
        @memcpy(@as([*]u8, @ptrCast(d))[0..indicies.len], std.mem.sliceAsBytes(indicies));
    }

    self.device.device.unmapMemory(stagingMemory);
    var buffer: vulkan.Buffer = undefined;
    var device_memory: vulkan.DeviceMemory = undefined;
    try self.createBuffer(
        global,
        indicies.len,
        .{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
        .{ .device_local_bit = true },
        &buffer,
        &device_memory,
    );

    try self.copyBuffer(stagingBuffer, buffer, indicies.len);

    self.device.device.destroyBuffer(stagingBuffer, null);
    self.device.device.freeMemory(stagingMemory, null);

    const resource =
        VertexBufferResource{
            .handle = buffer,

            .memory = device_memory,

            .size = indicies.len,

            .generation = 1,
        };

    const index: u32 = @intCast(self.vertex_buffers.items.len);

    try self.vertex_buffers.append(
        self.allocator,
        resource,
    );

    return .{
        .index = index,
        .generation = resource.generation,
    };
}
pub fn destroyVertexBuffer(self: *Self, buffer: Interface.Renderer.VertexBuffer) void {
    const resource = self.getVertexBuffer(buffer) catch return;
    self.device.device.destroyBuffer(
        resource.handle,
        null,
    );

    self.device.device.freeMemory(
        resource.memory,
        null,
    );

    resource.handle = .null_handle;
    resource.memory = .null_handle;
    resource.size = 0;
    resource.generation +%= 1;
}
fn createBuffer(
    self: *Self,
    global: *GraphicsContext,
    size: vulkan.DeviceSize,
    usage: vulkan.BufferUsageFlags,
    property: vulkan.MemoryPropertyFlags,
    buffer: *vulkan.Buffer,
    bufferMemory: *vulkan.DeviceMemory,
) !void {
    const info =
        vulkan.BufferCreateInfo{
            .s_type = .buffer_create_info,
            .size = size,
            .usage = usage,

            .sharing_mode = .exclusive,
        };

    buffer.* =
        try self.device.device.createBuffer(
            &info,
            null,
        );

    errdefer self.device.device.destroyBuffer(
        buffer.*,
        null,
    );

    const requirements =
        self.device.device.getBufferMemoryRequirements(buffer.*);

    const properties =
        global.instance.getPhysicalDeviceMemoryProperties(self.device.physicalDevice);

    const allocInfo =
        vulkan.MemoryAllocateInfo{
            .s_type = .memory_allocate_info,

            .allocation_size = requirements.size,

            .memory_type_index = try findMemoryType(
                requirements.memory_type_bits,
                properties,
                property,
            ),
        };

    bufferMemory.* =
        try self.device.device.allocateMemory(
            &allocInfo,
            null,
        );

    errdefer self.device.device.freeMemory(
        bufferMemory.*,
        null,
    );

    try self.device.device.bindBufferMemory(
        buffer.*,
        bufferMemory.*,
        0,
    );
}
fn copyBuffer(
    self: *Self,
    src_buffer: vulkan.Buffer,
    dst_buffer: vulkan.Buffer,
    size: vulkan.DeviceSize,
) !void {
    const allocInfo = vulkan.CommandBufferAllocateInfo{
        .s_type = .command_buffer_allocate_info,
        .level = .primary,
        .command_buffer_count = 1,
        .command_pool = self.command_pool,
        .p_next = null,
    };

    var commandBuffers = [_]vulkan.CommandBuffer{undefined};
    try self.device.device.allocateCommandBuffers(&allocInfo, &commandBuffers);

    const beginInfo = vulkan.CommandBufferBeginInfo{
        .s_type = .command_buffer_begin_info,
        .flags = .{ .one_time_submit_bit = true },
    };

    try self.device.device.beginCommandBuffer(commandBuffers[0], &beginInfo);

    const copyRegion = vulkan.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    self.device.device.cmdCopyBuffer(commandBuffers[0], src_buffer, dst_buffer, &.{copyRegion});
    try self.device.device.endCommandBuffer(commandBuffers[0]);

    const submitInfo = vulkan.SubmitInfo{
        .s_type = .submit_info,
        .command_buffer_count = 1,
        .p_command_buffers = &commandBuffers,
    };

    try self.device.device.queueSubmit(self.graphics_queue, &.{submitInfo}, .null_handle);
    try self.device.device.queueWaitIdle(self.graphics_queue);
    self.device.device.freeCommandBuffers(self.command_pool, commandBuffers[0..]);
}
fn findMemoryType(
    type_filter: u32,
    properties: vulkan.PhysicalDeviceMemoryProperties,
    required: vulkan.MemoryPropertyFlags,
) !u32 {
    for (properties.memory_types[0..properties.memory_type_count], 0..) |memory_type, i| {
        if (type_filter & (@as(u32, 1) << @as(u5, @intCast(i))) != 0 and memory_type.property_flags.contains(required))
            return @intCast(i);
    }

    return error.NoSuitableMemoryType;
}

pub fn createIndexBuffer(self: *Self, global: *GraphicsContext, indicies: []const u8) !Interface.Renderer.IndexBuffer {
    if (indicies.len == 0) return error.EmptyIndexBuffer;

    var stagingBuffer: vulkan.Buffer = undefined;
    var stagingMemory: vulkan.DeviceMemory = undefined;
    try self.createBuffer(
        global,
        indicies.len,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &stagingBuffer,
        &stagingMemory,
    );

    const data =
        try self.device.device.mapMemory(
            stagingMemory,
            0,
            indicies.len,
            .{},
        );

    if (data) |d| {
        @memcpy(@as([*]u8, @ptrCast(d))[0..indicies.len], std.mem.sliceAsBytes(indicies));
    }

    self.device.device.unmapMemory(stagingMemory);
    var buffer: vulkan.Buffer = undefined;
    var device_memory: vulkan.DeviceMemory = undefined;
    try self.createBuffer(
        global,
        indicies.len,
        .{ .index_buffer_bit = true, .transfer_dst_bit = true },
        .{ .device_local_bit = true },
        &buffer,
        &device_memory,
    );

    try self.copyBuffer(stagingBuffer, buffer, indicies.len);

    self.device.device.destroyBuffer(stagingBuffer, null);
    self.device.device.freeMemory(stagingMemory, null);

    const resource =
        IndexBufferResource{
            .handle = buffer,
            .memory = device_memory,
            .size = indicies.len,
            .generation = 1,
        };

    const index: u32 = @intCast(self.index_buffer.items.len);

    try self.index_buffer.append(
        self.allocator,
        resource,
    );

    return .{
        .index = index,
        .generation = resource.generation,
    };
}
pub fn destroyIndexBuffer(self: *Self, buffer: Interface.Renderer.IndexBuffer) void {
    const resource = self.getIndexBuffer(buffer) catch return;
    self.device.device.destroyBuffer(
        resource.handle,
        null,
    );

    self.device.device.freeMemory(
        resource.memory,
        null,
    );

    resource.handle = .null_handle;
    resource.memory = .null_handle;
    resource.size = 0;
    resource.generation +%= 1;
}

// ============================================================
// Command pool
// ============================================================

fn createCommandPool(self: *Self) !void {
    const CommandPoolInfo =
        vulkan.CommandPoolCreateInfo{
            .s_type = .command_pool_create_info,
            .queue_family_index = self.device
                .queueFamilyIndices
                .graphics_family,

            .flags = .{
                .reset_command_buffer_bit = true,
            },
        };

    self.command_pool =
        try self.device.device
            .createCommandPool(
            &CommandPoolInfo,
            null,
        );
}

fn destroyCommandPool(self: *Self) void {
    if (self.command_pool != .null_handle) {
        self.device.device.destroyCommandPool(
            self.command_pool,
            null,
        );

        self.command_pool = .null_handle;
        self.command_buffer = .null_handle;
    }
}

fn createCommandBuffer(self: *Self) !void {
    const CommandBuffersInfo =
        vulkan.CommandBufferAllocateInfo{
            .s_type = .command_buffer_allocate_info,
            .command_buffer_count = 1,
            .command_pool = self.command_pool,
            .level = .primary,
        };

    var command_buffers = [_]vulkan.CommandBuffer{self.command_buffer};

    try self.device.device
        .allocateCommandBuffers(
        &CommandBuffersInfo,
        &command_buffers,
    );

    self.command_buffer = command_buffers[0];
}

// ============================================================
// Resource lookup
// ============================================================

fn getShaderModule(self: *const Self, handle: Interface.Renderer.ShaderModule) !*ShaderResource {
    if (handle.index >= self.shader_modules.items.len) return error.InvalidShaderModule;

    const resource = &self.shader_modules.items[handle.index];

    if (resource.generation != handle.generation or resource.handle == .null_handle) return error.InvalidShaderModule;

    return resource;
}

fn getGraphicsPipeline(self: *const Self, handle: Interface.Renderer.GraphicsPipeline) !*GraphicsPipelineResource {
    if (handle.index >= self.graphics_pipelines.items.len) return error.InvalidGraphicsPipeline;

    const resource = &self.graphics_pipelines.items[handle.index];

    if (resource.generation != handle.generation or resource.handle == .null_handle) return error.InvalidGraphicsPipeline;

    return resource;
}

fn getVertexBuffer(self: *const Self, handle: Interface.Renderer.VertexBuffer) !*VertexBufferResource {
    if (handle.index >= self.vertex_buffers.items.len) return error.InvalidVertexBuffer;

    const resource = &self.vertex_buffers.items[handle.index];

    if (resource.generation != handle.generation or resource.handle == .null_handle)
        return error.InvalidVertexBuffer;

    return resource;
}

fn getIndexBuffer(self: *const Self, handle: Interface.Renderer.IndexBuffer) !*IndexBufferResource {
    if (handle.index >= self.index_buffer.items.len) return error.InvalidIndexBuffer;

    const resource = &self.index_buffer.items[handle.index];

    if (resource.generation != handle.generation or resource.handle == .null_handle)
        return error.InvalidIndexBuffer;

    return resource;
}

// ============================================================
// Framebuffers
// ============================================================

fn createFramebuffers(self: *Self) !void {
    self.framebuffers =
        try self.allocator.alloc(
            vulkan.Framebuffer,
            self.swapchain_image_views.len,
        );

    for (self.swapchain_image_views, 0..) |image_view, i| {
        const attachments = [_]vulkan.ImageView{image_view};

        const create_info =
            vulkan.FramebufferCreateInfo{
                .s_type = .framebuffer_create_info,
                .render_pass = self.render_pass,
                .attachment_count = 1,
                .p_attachments = &attachments,
                .width = self.swapchain_extent.width,
                .height = self.swapchain_extent.height,
                .layers = 1,
            };

        self.framebuffers[i] =
            try self.device.device
                .createFramebuffer(
                &create_info,
                null,
            );
    }
}

fn destroyFramebuffers(self: *Self) void {
    for (self.framebuffers) |framebuffer| {
        if (framebuffer != .null_handle) {
            self.device.device.destroyFramebuffer(
                framebuffer,
                null,
            );
        }
    }

    if (self.framebuffers.len != 0) {
        self.allocator.free(self.framebuffers);
        self.framebuffers = &.{};
    }
}

// ============================================================
// Frame
// ============================================================

pub fn beginFrame(self: *Self, global: *GraphicsContext) !void {
    if (self.frame_state.cmpxchgStrong(.idle, .recording, .acquire, .monotonic) != null)
        return error.FrameIsNotIdle;
    errdefer self.frame_state.store(.idle, .release);

    _ = try self.device.device.waitForFences(
        &.{self.in_flight_fence},
        .true,
        std.math.maxInt(u64),
    );
    if (self.resized) {
        try self.recreateSwapChain(global);
        self.resized = false;
        self.frame_state.store(.idle, .release);
        return;
    }
    const result =
        self.device.device.acquireNextImageKHR(
            self.swapchain,
            std.math.maxInt(u64),
            self.image_available_semaphore,
            .null_handle,
        ) catch |err| {
            if (err == error.OutOfDateKHR) {
                try self.recreateSwapChain(global);
                self.resized = false;
                self.frame_state.store(.idle, .release);
                return;
            } else return err;
        };

    self.current_image = result.image_index;

    try self.device.device.resetFences(&.{self.in_flight_fence});

    try self.device.device.resetCommandBuffer(
        self.command_buffer,
        .{},
    );

    const BeginInfo =
        vulkan.CommandBufferBeginInfo{
            .s_type = .command_buffer_begin_info,
            .flags = .{},
        };

    try self.device.device.beginCommandBuffer(
        self.command_buffer,
        &BeginInfo,
    );

    const clear_color =
        vulkan.ClearValue{
            .color = .{
                .float_32 = .{
                    0.05,
                    0.05,
                    0.08,
                    1.0,
                },
            },
        };

    const RenderPassInfo =
        vulkan.RenderPassBeginInfo{
            .s_type = .render_pass_begin_info,
            .render_pass = self.render_pass,
            .framebuffer = self.framebuffers[
                self.current_image
            ],

            .render_area = .{
                .offset = .{
                    .x = 0,
                    .y = 0,
                },

                .extent = self.swapchain_extent,
            },

            .clear_value_count = 1,
            .p_clear_values = &.{clear_color},
        };

    self.device.device.cmdBeginRenderPass(
        self.command_buffer,
        &RenderPassInfo,
        .@"inline",
    );

    const viewport =
        vulkan.Viewport{
            .x = 0.0,

            .y = 0.0,

            .width = @floatFromInt(
                self.swapchain_extent.width,
            ),

            .height = @floatFromInt(
                self.swapchain_extent.height,
            ),

            .min_depth = 0.0,

            .max_depth = 1.0,
        };

    self.device.device.cmdSetViewport(
        self.command_buffer,
        0,
        &.{viewport},
    );

    const scissors =
        vulkan.Rect2D{
            .offset = .{
                .x = 0,
                .y = 0,
            },

            .extent = self.swapchain_extent,
        };
    self.device.device.cmdSetScissor(
        self.command_buffer,
        0,
        &.{scissors},
    );
}

pub fn bindPipeline(self: *Self, pipeline: Interface.Renderer.GraphicsPipeline) !void {
    if (self.frame_state.load(.acquire) != .recording) return error.FrameIsNotReady;
    const resource =
        try self.getGraphicsPipeline(pipeline);

    self.device.device.cmdBindPipeline(
        self.command_buffer,
        .graphics,
        resource.handle,
    );
}

pub fn bindIndexBuffer(
    self: *Self,
    buffer: Interface.Renderer.IndexBuffer,
) !void {
    if (self.frame_state.load(.acquire) != .recording) return error.FrameIsNotReady;

    const resource =
        try self.getIndexBuffer(buffer);

    self.device.device.cmdBindIndexBuffer(
        self.command_buffer,
        resource.handle,
        0,
        .uint16,
    );
}

pub fn bindVertexBuffer(
    self: *Self,
    buffer: Interface.Renderer.VertexBuffer,
) !void {
    if (self.frame_state.load(.acquire) != .recording) return error.FrameIsNotReady;

    const resource =
        try self.getVertexBuffer(buffer);

    self.device.device.cmdBindVertexBuffers(
        self.command_buffer,
        0,
        &.{resource.handle},
        &.{0},
    );
}

pub fn draw(self: *Self, indicies_count: u32, instance_count: u32) !void {
    if (self.frame_state.load(.acquire) != .recording) return error.FrameIsNotReady;
    self.device.device.cmdDrawIndexed(
        self.command_buffer,
        indicies_count,
        instance_count,
        0,
        0,
        0,
    );
}

pub fn endFrame(self: *Self) !void {
    if (self.frame_state.cmpxchgStrong(.recording, .closing, .acquire, .monotonic) != null)
        return error.InvalidFrameState;
    errdefer self.frame_state.store(.recording, .release);
    self.device.device.cmdEndRenderPass(self.command_buffer);
    try self.device.device.endCommandBuffer(self.command_buffer);
}

// ============================================================
// Present
// ============================================================

pub fn present(self: *Self) !void {
    if (self.frame_state.load(.acquire) != .closing) return error.InvalidFrameState;
    defer self.frame_state.store(.idle, .release);
    errdefer self.frame_state.store(.idle, .release);

    const WaitStage = [_]vulkan.PipelineStageFlags{.{ .color_attachment_output_bit = true }};
    const render_finished_semaphore = self.render_finished_semaphores[self.current_image];
    const SubmitInfo =
        vulkan.SubmitInfo{
            .s_type = .submit_info,
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &.{
                self.image_available_semaphore,
            },

            .p_wait_dst_stage_mask = &WaitStage,
            .command_buffer_count = 1,
            .p_command_buffers = &.{
                self.command_buffer,
            },

            .signal_semaphore_count = 1,
            .p_signal_semaphores = &.{
                render_finished_semaphore,
            },
        };
    try self.device.device.queueSubmit(self.graphics_queue, &.{SubmitInfo}, self.in_flight_fence);

    const PresentInfo =
        vulkan.PresentInfoKHR{
            .s_type = .present_info_khr,
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &.{
                render_finished_semaphore,
            },

            .swapchain_count = 1,
            .p_swapchains = &.{
                self.swapchain,
            },

            .p_image_indices = &.{
                self.current_image,
            },
        };
    _ = try self.device.device.queuePresentKHR(
        self.present_queue,
        &PresentInfo,
    );
}

// ============================================================
// Synchronization
// ============================================================

fn createSyncObjects(self: *Self) !void {
    const semaphore_info =
        vulkan.SemaphoreCreateInfo{
            .s_type = .semaphore_create_info,
        };

    self.image_available_semaphore =
        try self.device.device.createSemaphore(
            &semaphore_info,
            null,
        );

    errdefer self.destroySyncObjects();

    self.render_finished_semaphores = try self.allocator.alloc(vulkan.Semaphore, self.swapchain_images.len);
    @memset(self.render_finished_semaphores, vulkan.Semaphore.null_handle);
    for (self.render_finished_semaphores) |*semaphore| {
        semaphore.* = try self.device.device.createSemaphore(
            &vulkan.SemaphoreCreateInfo{ .s_type = .semaphore_create_info },
            null,
        );
    }

    const fence_info =
        vulkan.FenceCreateInfo{
            .s_type = .fence_create_info,

            .flags = .{
                .signaled_bit = true,
            },
        };

    self.in_flight_fence =
        try self.device.device.createFence(
            &fence_info,
            null,
        );
}

fn destroySyncObjects(self: *Self) void {
    if (self.in_flight_fence != .null_handle) {
        self.device.device.destroyFence(
            self.in_flight_fence,
            null,
        );

        self.in_flight_fence = .null_handle;
    }

    for (self.render_finished_semaphores) |semaphore| {
        self.device.device.destroySemaphore(
            semaphore,
            null,
        );
    }

    self.allocator.free(self.render_finished_semaphores);

    if (self.image_available_semaphore != .null_handle) {
        self.device.device.destroySemaphore(
            self.image_available_semaphore,
            null,
        );

        self.image_available_semaphore = .null_handle;
    }
}

// ============================================================
// Physical device info
// ============================================================

pub inline fn getPhysicalDevice(self: *Self) !Interface.shared.DeviceInfo {
    return .{
        .index = self.device.index,
        .name = self.device
            .physicalDeviceProperties
            .device_name,

        .type = @enumFromInt(
            @intFromEnum(
                self.device
                    .physicalDeviceProperties
                    .device_type,
            ),
        ),
    };
}

fn primitiveTopology(
    value: Interface.Renderer.PrimitiveTopology,
) vulkan.PrimitiveTopology {
    return switch (value) {
        .point_list => .point_list,
        .line_list => .line_list,
        .line_strip => .line_strip,
        .triangle_list => .triangle_list,
        .triangle_strip => .triangle_strip,
        .triangle_fan => .triangle_fan,
    };
}

fn cullMode(
    value: Interface.Renderer.CullMode,
) vulkan.CullModeFlags {
    return switch (value) {
        .none => .{},
        .front => .{
            .front_bit = true,
        },
        .back => .{
            .back_bit = true,
        },
        .front_and_back => .{
            .front_bit = true,
            .back_bit = true,
        },
    };
}

fn frontFace(
    value: Interface.Renderer.FrontFace,
) vulkan.FrontFace {
    return switch (value) {
        .counter_clockwise => .counter_clockwise,
        .clockwise => .clockwise,
    };
}

fn vertexFormat(
    value: Interface.Renderer.VertexFormat,
) vulkan.Format {
    return switch (value) {
        .r32_sfloat => .r32_sfloat,
        .r32g32_sfloat => .r32g32_sfloat,
        .r32g32b32_sfloat => .r32g32b32_sfloat,
        .r32g32b32a32_sfloat => .r32g32b32a32_sfloat,

        .r32_uint => .r32_uint,
        .r32g32_uint => .r32g32_uint,
        .r32g32b32_uint => .r32g32b32_uint,
        .r32g32b32a32_uint => .r32g32b32a32_uint,

        .r32_sint => .r32_sint,
        .r32g32_sint => .r32g32_sint,
        .r32g32b32_sint => .r32g32b32_sint,
        .r32g32b32a32_sint => .r32g32b32a32_sint,
    };
}
