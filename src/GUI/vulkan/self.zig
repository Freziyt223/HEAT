const std = @import("std");
const builtin = @import("builtin");
const Conf = @import("Conf");
const vulkan = @import("vulkan");
const glfw = @import("glfw");
const Interface = @import("Interface");
const IO = @import("IO");

const enable_validation_layers = true;

const required_layer_names = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const required_device_extensions = [_][*:0]const u8{
    vulkan.extensions.khr_swapchain.name,
};

const BaseWrapper = vulkan.BaseWrapper;
const InstanceWrapper = vulkan.InstanceWrapper;
const DeviceWrapper = vulkan.DeviceWrapper;

pub const QueueFamilyIndices = struct {
    graphics_family: u32 = 0,
    present_family: u32 = 0,
};

pub const DeviceInfo = struct {
    physicalDevice: vulkan.PhysicalDevice = .null_handle,
    physicalDeviceProperties: vulkan.PhysicalDeviceProperties = undefined,

    queueFamilyIndices: QueueFamilyIndices,

    index: usize = 0,

    device: vulkan.DeviceProxy,
};

pub const GraphicsContex = struct {
    allocator: std.mem.Allocator,

    vbw: BaseWrapper,

    instance: vulkan.InstanceProxy,
    debug_messenger: vulkan.DebugUtilsMessengerEXT,

    device: *DeviceInfo,

    pub fn init(allocator: std.mem.Allocator) !GraphicsContex {
        var self: GraphicsContex = undefined;

        self.allocator = allocator;

        self.vbw = BaseWrapper.load(getGlfwInstanceProcAddr);

        if (try self.checkLayerSupport() == false) {
            return error.MissingLayer;
        }

        try self.createInstance();

        errdefer {
            self.instance.destroyInstance(null);
            self.allocator.destroy(self.instance.wrapper);
        }

        try self.setupDebugMessenger();

        errdefer self.instance.destroyDebugUtilsMessengerEXT(
            self.debug_messenger,
            null,
        );

        const selection: Interface.DeviceSelection = switch (Conf.selection) {
            .discrete => .discrete,
            .integrated => .integrated,
            .index => |index| .{ .index = index },
            .name => |name| .{ .name = name },
        };

        try self.initDevice(selection);

        return self;
    }

    pub fn deinit(self: *GraphicsContex) void {
        self.deinitDevice();

        self.instance.destroyDebugUtilsMessengerEXT(
            self.debug_messenger,
            null,
        );

        self.instance.destroyInstance(null);

        self.allocator.destroy(self.instance.wrapper);
    }

    // ============================================================
    // Instance
    // ============================================================

    fn getGlfwInstanceProcAddr(
        instance: ?vulkan.Instance,
        procname: [*:0]const u8,
    ) vulkan.PfnVoidFunction {
        return @ptrCast(glfw.getInstanceProcAddress(
            instance orelse .null_handle,
            procname,
        ));
    }

    fn checkLayerSupport(self: *GraphicsContex) !bool {
        const available_layers =
            try self.vbw.enumerateInstanceLayerPropertiesAlloc(
                self.allocator,
            );

        defer self.allocator.free(available_layers);

        for (required_layer_names) |required| {
            var found = false;

            for (available_layers) |available| {
                const available_name =
                    std.mem.sliceTo(&available.layer_name, 0);

                if (std.mem.eql(
                    u8,
                    std.mem.span(required),
                    available_name,
                )) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                return false;
            }
        }

        return true;
    }

    inline fn createInstance(self: *GraphicsContex) !void {
        const AppInfo = vulkan.ApplicationInfo{
            .p_application_name = "Vulkan app",
            .p_engine_name = "No Engine",

            .application_version = vulkan.makeApiVersion(1, 0, 0, 0).toU32(),

            .engine_version = vulkan.makeApiVersion(1, 0, 0, 0).toU32(),

            .s_type = .application_info,

            .api_version = vulkan.API_VERSION_1_2.toU32(),
        };

        const glfwExtensions =
            try glfw.getRequiredInstanceExtensions();

        const extensions = try self.allocator.alloc(
            [*:0]const u8,
            glfwExtensions.len + 3,
        );

        defer self.allocator.free(extensions);

        extensions[0] =
            vulkan.extensions.ext_debug_utils.name;

        extensions[1] =
            vulkan.extensions.khr_portability_enumeration.name;

        extensions[2] =
            vulkan.extensions.khr_get_physical_device_properties_2.name;

        @memcpy(
            extensions[3..],
            glfwExtensions,
        );

        const CreateInfo = vulkan.InstanceCreateInfo{
            .s_type = .instance_create_info,

            .p_application_info = &AppInfo,

            .enabled_extension_count = @intCast(extensions.len),

            .pp_enabled_extension_names = extensions.ptr,

            .enabled_layer_count = required_layer_names.len,

            .pp_enabled_layer_names = @ptrCast(&required_layer_names),

            .flags = .{
                .enumerate_portability_bit_khr = true,
            },
        };

        const vki =
            try self.allocator.create(InstanceWrapper);

        errdefer self.allocator.destroy(vki);

        const instance =
            try self.vbw.createInstance(
                &CreateInfo,
                null,
            );

        vki.* = InstanceWrapper.load(
            instance,
            self.vbw.dispatch.vkGetInstanceProcAddr.?,
        );

        self.instance =
            vulkan.InstanceProxy.init(
                instance,
                vki,
            );

        errdefer self.instance.destroyInstance(null);
    }

    inline fn setupDebugMessenger(self: *GraphicsContex) !void {
        const DebugMessengerInfo =
            vulkan.DebugUtilsMessengerCreateInfoEXT{
                .message_severity = .{
                    .warning_bit_ext = true,
                    .error_bit_ext = true,
                },

                .message_type = .{
                    .general_bit_ext = true,
                    .validation_bit_ext = true,
                    .performance_bit_ext = true,
                },

                .pfn_user_callback = &debugUtilsMessengerCallback,

                .p_user_data = null,
            };

        self.debug_messenger =
            try self.instance.createDebugUtilsMessengerEXT(
                &DebugMessengerInfo,
                null,
            );
    }

    // ============================================================
    // Device
    // ============================================================

    pub fn selectPhysicalDevice(
        self: *GraphicsContex,
        selection: Interface.DeviceSelection,
    ) !void {
        self.deinitDevice();

        errdefer self.deinitDevice();

        try self.initDevice(selection);
    }

    inline fn initDevice(
        self: *GraphicsContex,
        selection: Interface.DeviceSelection,
    ) !void {
        const device =
            try self.pickPhysicalDevice(
                selection,
                null,
            );

        self.device = device;
    }

    inline fn deinitDevice(self: *GraphicsContex) void {
        if (self.device.device.handle != .null_handle) {
            self.device.device.destroyDevice(null);

            self.allocator.destroy(
                self.device.device.wrapper,
            );

            self.device.device.handle =
                .null_handle;
        }

        self.allocator.destroy(self.device);
    }

    pub inline fn getPhysicalDevice(
        self: *GraphicsContex,
    ) !Interface.DeviceInfo {
        return .{
            .index = @intCast(self.device.index),

            .name = self.device.physicalDeviceProperties.device_name,

            .type = @enumFromInt(
                @intFromEnum(
                    self.device
                        .physicalDeviceProperties
                        .device_type,
                ),
            ),
        };
    }

    pub inline fn enumeratePhysicalDevices(
        self: *GraphicsContex,
        allocator: std.mem.Allocator,
    ) ![]Interface.DeviceInfo {
        var device_count: u32 = 0;

        _ = try self.instance.enumeratePhysicalDevices(
            &device_count,
            null,
        );

        if (device_count == 0) {
            return error.NoSuitableGPU;
        }

        const devices =
            try self.allocator.alloc(
                vulkan.PhysicalDevice,
                device_count,
            );

        defer self.allocator.free(devices);

        _ = try self.instance.enumeratePhysicalDevices(
            &device_count,
            devices.ptr,
        );

        const Devices =
            try allocator.alloc(
                Interface.DeviceInfo,
                device_count,
            );

        for (devices, 0..) |device, i| {
            const properties =
                self.instance.getPhysicalDeviceProperties(
                    device,
                );

            Devices[i] = .{
                .index = @intCast(i),

                .name = properties.device_name,

                .type = @enumFromInt(
                    @intFromEnum(
                        properties.device_type,
                    ),
                ),
            };
        }

        return Devices;
    }

    // ============================================================
    // Physical device + queues
    // ============================================================

    pub inline fn pickPhysicalDevice(
        self: *GraphicsContex,
        selection: Interface.DeviceSelection,
        surface: ?vulkan.SurfaceKHR,
    ) !*DeviceInfo {
        var device_count: u32 = 0;

        _ = try self.instance.enumeratePhysicalDevices(
            &device_count,
            null,
        );

        if (device_count == 0) {
            return error.NoSuitableGPU;
        }

        const devices =
            try self.allocator.alloc(
                vulkan.PhysicalDevice,
                device_count,
            );

        defer self.allocator.free(devices);

        _ = try self.instance.enumeratePhysicalDevices(
            &device_count,
            devices.ptr,
        );

        const selected =
            try self.allocator.create(DeviceInfo);

        errdefer self.allocator.destroy(selected);

        for (devices, 0..) |device, i| {
            const indices =
                (try self.isDeviceSuitable(
                    device,
                    surface,
                )) orelse continue;

            const properties =
                self.instance.getPhysicalDeviceProperties(
                    device,
                );

            const is_candidate =
                switch (selection) {
                    .discrete => properties.device_type ==
                        .discrete_gpu,

                    .integrated => properties.device_type ==
                        .integrated_gpu,

                    .index => |target_idx| i == target_idx,

                    .name => |search_str| blk: {
                        const name_slice =
                            std.mem.sliceTo(
                                &properties.device_name,
                                0,
                            );

                        break :blk std.mem.indexOf(
                            u8,
                            name_slice,
                            search_str,
                        ) != null;
                    },
                };

            if (is_candidate) {
                selected.physicalDevice =
                    device;

                selected.physicalDeviceProperties =
                    properties;

                selected.queueFamilyIndices =
                    indices;

                selected.index =
                    i;

                break;
            }
        }

        if (selected.physicalDevice == .null_handle) {
            return error.NoSuitableGPU;
        }

        const graphics_family =
            selected.queueFamilyIndices.graphics_family;

        const present_family =
            selected.queueFamilyIndices.present_family;

        // --------------------------------------------------------
        // IMPORTANT:
        //
        // We have two WindowContexts running concurrently.
        //
        // Therefore we request TWO queues from every queue family
        // that we are going to use.
        // --------------------------------------------------------

        const queue_family_properties_count: u32 =
            blk: {
                var count: u32 = 0;

                self.instance.getPhysicalDeviceQueueFamilyProperties(
                    selected.physicalDevice,
                    &count,
                    null,
                );

                break :blk count;
            };

        const queue_families =
            try self.allocator.alloc(
                vulkan.QueueFamilyProperties,
                queue_family_properties_count,
            );

        defer self.allocator.free(queue_families);

        var count = queue_family_properties_count;

        self.instance.getPhysicalDeviceQueueFamilyProperties(
            selected.physicalDevice,
            &count,
            queue_families.ptr,
        );

        const graphics_queue_count =
            queue_families[graphics_family].queue_count;

        const present_queue_count =
            queue_families[present_family].queue_count;

        std.debug.print(
            "Graphics family: {}, queues: {}\n",
            .{
                graphics_family,
                graphics_queue_count,
            },
        );

        std.debug.print(
            "Present family: {}, queues: {}\n",
            .{
                present_family,
                present_queue_count,
            },
        );

        // We currently have two WindowContexts.
        if (graphics_queue_count < 2) {
            return error.NotEnoughGraphicsQueues;
        }

        if (present_family != graphics_family and
            present_queue_count < 2)
        {
            return error.NotEnoughPresentQueues;
        }

        // --------------------------------------------------------
        // Queue creation
        // --------------------------------------------------------

        const queue_priorities =
            [_]f32{
                1.0,
                1.0,
            };

        var queue_create_infos: [2]vulkan.DeviceQueueCreateInfo =
            undefined;

        var queue_create_info_count: u32 = 1;

        queue_create_infos[0] = .{
            .s_type = .device_queue_create_info,

            .queue_family_index = graphics_family,

            .queue_count = 2,

            .p_queue_priorities = &queue_priorities,
        };

        if (present_family != graphics_family) {
            queue_create_infos[1] = .{
                .s_type = .device_queue_create_info,

                .queue_family_index = present_family,

                .queue_count = 2,

                .p_queue_priorities = &queue_priorities,
            };

            queue_create_info_count = 2;
        }

        // --------------------------------------------------------
        // Device extensions
        // --------------------------------------------------------

        var extension_count: u32 = 0;

        _ = try self.instance
            .enumerateDeviceExtensionProperties(
            selected.physicalDevice,
            null,
            &extension_count,
            null,
        );

        const extensions =
            try self.allocator.alloc(
                vulkan.ExtensionProperties,
                extension_count,
            );

        defer self.allocator.free(extensions);

        _ = try self.instance
            .enumerateDeviceExtensionProperties(
            selected.physicalDevice,
            null,
            &extension_count,
            extensions.ptr,
        );

        const extensions_applied: [*]const [*:0]const u8 =
            &required_device_extensions;

        extension_count =
            required_device_extensions.len;

        const DeviceFeatures =
            vulkan.PhysicalDeviceFeatures{};

        const CreateInfo =
            vulkan.DeviceCreateInfo{
                .s_type = .device_create_info,

                .queue_create_info_count = queue_create_info_count,

                .p_queue_create_infos = &queue_create_infos,

                .p_enabled_features = &DeviceFeatures,

                .enabled_extension_count = extension_count,

                .pp_enabled_extension_names = extensions_applied,
            };

        // --------------------------------------------------------
        // Create logical device
        // --------------------------------------------------------

        const vkd =
            try self.allocator.create(
                DeviceWrapper,
            );

        errdefer self.allocator.destroy(vkd);

        const device =
            try self.instance.createDevice(
                selected.physicalDevice,
                &CreateInfo,
                null,
            );

        vkd.* =
            DeviceWrapper.load(
                device,
                self.instance
                    .wrapper
                    .dispatch
                    .vkGetDeviceProcAddr.?,
            );

        selected.device =
            vulkan.DeviceProxy.init(
                device,
                vkd,
            );

        // --------------------------------------------------------
        // IMPORTANT:
        //
        // Do NOT obtain queues here anymore.
        //
        // Each WindowContext obtains its own queue based on
        // its queue_index.
        // --------------------------------------------------------

        return selected;
    }

    inline fn isDeviceSuitable(
        self: *GraphicsContex,
        device: vulkan.PhysicalDevice,
        surface: ?vulkan.SurfaceKHR,
    ) !?QueueFamilyIndices {
        var family_count: u32 = 0;

        self.instance.getPhysicalDeviceQueueFamilyProperties(
            device,
            &family_count,
            null,
        );

        const families =
            try self.allocator.alloc(
                vulkan.QueueFamilyProperties,
                family_count,
            );

        defer self.allocator.free(families);

        self.instance.getPhysicalDeviceQueueFamilyProperties(
            device,
            &family_count,
            families.ptr,
        );

        var graphics_family: ?u32 = null;
        var present_family: ?u32 = null;

        for (families, 0..) |family, i| {
            const idx: u32 = @intCast(i);

            if (family.queue_flags.graphics_bit) {
                graphics_family = idx;
            }

            if (try glfw.getPhysicalDevicePresentationSupport(
                self.instance.handle,
                device,
                idx,
            ) == true) {
                if (surface) |s| {
                    const supported =
                        try self.instance
                            .getPhysicalDeviceSurfaceSupportKHR(
                            device,
                            idx,
                            s,
                        );

                    if (supported == .true) {
                        present_family = idx;
                    }
                } else {
                    present_family = idx;
                }
            }

            if (graphics_family != null and
                present_family != null)
            {
                return QueueFamilyIndices{
                    .graphics_family = graphics_family.?,

                    .present_family = present_family.?,
                };
            }
        }

        return null;
    }

    fn debugUtilsMessengerCallback(
        severity: vulkan.DebugUtilsMessageSeverityFlagsEXT,
        msg_type: vulkan.DebugUtilsMessageTypeFlagsEXT,
        callback_data: ?*const vulkan.DebugUtilsMessengerCallbackDataEXT,
        _: ?*anyopaque,
    ) callconv(.c) vulkan.Bool32 {
        const severity_str =
            if (severity.verbose_bit_ext)
                "verbose"
            else if (severity.info_bit_ext)
                "info"
            else if (severity.warning_bit_ext)
                "warning"
            else if (severity.error_bit_ext)
                "error"
            else
                "unknown";

        const type_str =
            if (msg_type.general_bit_ext)
                "general"
            else if (msg_type.validation_bit_ext)
                "validation"
            else if (msg_type.performance_bit_ext)
                "performance"
            else if (msg_type.device_address_binding_bit_ext)
                "device addr"
            else
                "unknown";

        const message: [*c]const u8 =
            if (callback_data) |cb_data|
                cb_data.p_message
            else
                "NO MESSAGE!";

        std.debug.print(
            "[{s}][{s}]. Message:\n  {s}\n",
            .{
                severity_str,
                type_str,
                message,
            },
        );

        return .false;
    }
};

// ================================================================
// Window Context
// ================================================================

const SwapchainSupportDetails = struct {
    capabilities: vulkan.SurfaceCapabilitiesKHR,

    formats: []vulkan.SurfaceFormatKHR,

    present_modes: []vulkan.PresentModeKHR,
};

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
        .float32 => .r32_sfloat,

        .float32x2 => .r32g32_sfloat,

        .float32x3 => .r32g32b32_sfloat,

        .float32x4 => .r32g32b32a32_sfloat,

        .uint32 => .r32_uint,

        .uint32x2 => .r32g32_uint,

        .uint32x3 => .r32g32b32_uint,

        .uint32x4 => .r32g32b32a32_uint,

        .sint32 => .r32_sint,

        .sint32x2 => .r32g32_sint,

        .sint32x3 => .r32g32b32_sint,

        .sint32x4 => .r32g32b32a32_sint,
    };
}

pub const WindowContext = struct {
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

    surface: vulkan.SurfaceKHR = .null_handle,

    device: *DeviceInfo,

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

    current_image: u32 = 0,

    frame_state: std.atomic.Value(Interface.Renderer.FrameState) = .init(.idle),

    const DeviceType = enum(u8) {
        global,
        local,
    };

    pub const ShaderResource = struct {
        handle: vulkan.ShaderModule =
            .null_handle,

        generation: u32 =
            1,
    };

    pub const GraphicsPipelineResource = struct {
        handle: vulkan.Pipeline =
            .null_handle,

        layout: vulkan.PipelineLayout =
            .null_handle,

        generation: u32 =
            1,
    };

    // ============================================================
    // Init
    // ============================================================

    pub fn init(
        allocator: std.mem.Allocator,
        global: *GraphicsContex,
        window: *Interface.Window,
        queue_index: u32,
    ) !*WindowContext {
        const self =
            try allocator.create(
                WindowContext,
            );

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

        errdefer self.deinit(global);

        try self.createSurface(global);

        try self.initDevice(
            null,
            global,
        );

        // --------------------------------------------------------
        // Get THIS WINDOW's queues.
        // --------------------------------------------------------

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

        std.debug.print(
            "Window queue index: {}\n",
            .{queue_index},
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

    // ============================================================
    // Deinit
    // ============================================================

    pub fn deinit(
        self: *WindowContext,
        global: *GraphicsContex,
    ) void {
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

        // Увесь GPU workload цього VkDevice має завершитися.
        self.device.device.deviceWaitIdle() catch |err| {
            std.debug.print(
                "deviceWaitIdle failed during WindowContext.deinit: {}\n",
                .{err},
            );
            return;
        };

        // Тепер Vulkan objects можна знищувати.

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

        self.graphics_pipelines.deinit(self.allocator);
        self.shader_modules.deinit(self.allocator);

        self.destroyFramebuffers();
        self.destroyRenderPass();
        self.destroyImageViews();
        self.destroySwapchain();
        self.destroySurface(global);

        self.destroyCommandPool();
        self.destroySyncObjects();

        self.allocator.destroy(self);
    }

    // ============================================================
    // Surface
    // ============================================================

    fn createSurface(
        self: *WindowContext,
        global: *GraphicsContex,
    ) !void {
        try glfw.createWindowSurface(
            global.instance.handle,

            @ptrCast(
                @alignCast(self.window),
            ),

            null,

            &self.surface,
        );
    }

    fn destroySurface(
        self: *WindowContext,
        global: *GraphicsContex,
    ) void {
        if (self.surface != .null_handle) {
            global.instance.destroySurfaceKHR(
                self.surface,
                null,
            );

            self.surface =
                .null_handle;
        }
    }

    // ============================================================
    // Device
    // ============================================================

    pub fn selectPhysicalDevice(
        self: *WindowContext,
        selection: ?Interface.DeviceSelection,
        global: *GraphicsContex,
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

            self.device =
                global.device;

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
        self: *WindowContext,
        selection: ?Interface.DeviceSelection,
        global: *GraphicsContex,
    ) !void {
        if (selection) |select| {
            const device =
                try global.pickPhysicalDevice(
                    select,
                    self.surface,
                );

            self.device =
                device;

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

        self.device =
            global.device;
    }

    fn deinitDevice(
        self: *WindowContext,
    ) void {
        if (self.device_type.load(.acquire) == .local) {
            if (self.device.device != .null_handle) {
                self.device.device.destroyDevice(null);

                self.device.device =
                    .null_handle;
            }
        }
    }

    // ============================================================
    // Swapchain
    // ============================================================

    fn createSwapchain(
        self: *WindowContext,
        global: *GraphicsContex,
    ) !void {
        const capabilities =
            try global.instance
                .getPhysicalDeviceSurfaceCapabilitiesKHR(
                self.device.physicalDevice,
                self.surface,
            );

        var image_count_create =
            capabilities.min_image_count + 1;

        if (capabilities.max_image_count != 0) {
            image_count_create =
                @min(
                    image_count_create,
                    capabilities.max_image_count,
                );
        }

        const queue_families =
            [_]u32{
                self.device
                    .queueFamilyIndices
                    .graphics_family,

                self.device
                    .queueFamilyIndices
                    .present_family,
            };

        const separate_families =
            self.device
                .queueFamilyIndices
                .graphics_family !=
            self.device
                .queueFamilyIndices
                .present_family;

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

                .image_sharing_mode = if (separate_families)
                    .concurrent
                else
                    .exclusive,

                .queue_family_index_count = if (separate_families)
                    2
                else
                    0,

                .p_queue_family_indices = if (separate_families)
                    &queue_families
                else
                    null,

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

        self.swapchain_extent =
            capabilities.current_extent;

        self.swapchain_format =
            CreateInfo.image_format;
    }

    fn destroySwapchain(
        self: *WindowContext,
    ) void {
        if (self.swapchain != .null_handle) {
            self.device.device.destroySwapchainKHR(
                self.swapchain,
                null,
            );

            self.swapchain =
                .null_handle;
        }

        if (self.swapchain_images.len != 0) {
            self.allocator.free(
                self.swapchain_images,
            );

            self.swapchain_images =
                &.{};
        }
    }

    fn recreateSwapChain(
        self: *WindowContext,
        global: *GraphicsContex,
    ) !void {
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

    fn createImageViews(
        self: *WindowContext,
    ) !void {
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
                        .aspect_mask = .{
                            .color_bit = true,
                        },

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

    fn destroyImageViews(
        self: *WindowContext,
    ) void {
        for (self.swapchain_image_views) |image_view| {
            if (image_view != .null_handle) {
                self.device.device.destroyImageView(
                    image_view,
                    null,
                );
            }
        }

        if (self.swapchain_image_views.len != 0) {
            self.allocator.free(
                self.swapchain_image_views,
            );

            self.swapchain_image_views =
                &.{};
        }
    }

    // ============================================================
    // Render pass
    // ============================================================

    fn createRenderPass(
        self: *WindowContext,
    ) !void {
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

    fn destroyRenderPass(
        self: *WindowContext,
    ) void {
        if (self.render_pass != .null_handle) {
            self.device.device.destroyRenderPass(
                self.render_pass,
                null,
            );

            self.render_pass =
                .null_handle;
        }
    }

    // ============================================================
    // Shaders
    // ============================================================

    pub fn createShaderModule(
        self: *WindowContext,
        spirv: []const u8,
    ) !Interface.Renderer.ShaderModule {
        if (spirv.len == 0) {
            return error.EmptyShader;
        }

        if (spirv.len % 4 != 0) {
            return error.WrongShaderAlignment;
        }

        const code =
            try self.allocator.alignedAlloc(
                u32,
                std.mem.Alignment.fromByteUnits(
                    @alignOf(u32),
                ),
                spirv.len / 4,
            );

        defer self.allocator.free(code);

        @memcpy(
            std.mem.sliceAsBytes(code),
            spirv,
        );

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

        const resource =
            ShaderResource{
                .handle = handle,

                .generation = 1,
            };

        const index: u32 =
            @intCast(
                self.shader_modules.items.len,
            );

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

    pub fn destroyShaderModule(
        self: *WindowContext,
        shader: Interface.Renderer.ShaderModule,
    ) void {
        if (shader.index >=
            self.shader_modules.items.len)
        {
            return;
        }

        const resource =
            &self.shader_modules.items[
                shader.index
            ];

        if (resource.generation !=
            shader.generation or
            resource.handle ==
                .null_handle)
        {
            return;
        }

        self.device.device.destroyShaderModule(
            resource.handle,
            null,
        );

        resource.handle =
            .null_handle;

        resource.generation +%= 1;
    }

    // ============================================================
    // Graphics pipeline
    // ============================================================

    pub fn createGraphicsPipeline(
        self: *WindowContext,
        info: Interface.Renderer.GraphicsPipelineCreateInfo,
    ) !Interface.Renderer.GraphicsPipeline {
        const vertex_module =
            try self.getShaderModule(info.vertex_shader);

        const fragment_module =
            try self.getShaderModule(info.fragment_shader);

        // ------------------------------------------------------------
        // Vertex input
        // ------------------------------------------------------------

        const bindings =
            try self.allocator.alloc(
                vulkan.VertexInputBindingDescription,
                info.vertex_input.bindings.len,
            );
        defer self.allocator.free(bindings);

        for (
            info.vertex_input.bindings,
            bindings,
        ) |source, *target| {
            target.* = .{
                .binding = source.binding,
                .stride = source.stride,
                .input_rate = switch (source.input_rate) {
                    .vertex => .vertex,
                    .instance => .instance,
                },
            };
        }

        const attributes =
            try self.allocator.alloc(
                vulkan.VertexInputAttributeDescription,
                info.vertex_input.attributes.len,
            );
        defer self.allocator.free(attributes);

        for (
            info.vertex_input.attributes,
            attributes,
        ) |source, *target| {
            target.* = .{
                .location = source.location,
                .binding = source.binding,
                .format = vertexFormat(source.format),
                .offset = source.offset,
            };
        }

        const vertex_input =
            vulkan.PipelineVertexInputStateCreateInfo{
                .s_type = .pipeline_vertex_input_state_create_info,

                .vertex_binding_description_count = @intCast(bindings.len),

                .p_vertex_binding_descriptions = if (bindings.len > 0)
                    bindings.ptr
                else
                    null,

                .vertex_attribute_description_count = @intCast(attributes.len),

                .p_vertex_attribute_descriptions = if (attributes.len > 0)
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

                    .module = vertex_module,
                    .p_name = "main",
                },

                .{
                    .s_type = .pipeline_shader_stage_create_info,

                    .stage = .{
                        .fragment_bit = true,
                    },

                    .module = fragment_module,
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

                // Для першого тесту повністю вимикаємо culling.
                .cull_mode = .{},
                .front_face = .counter_clockwise,

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

                .rasterization_samples = .{
                    .@"1_bit" = true,
                },

                .alpha_to_coverage_enable = .false,
                .alpha_to_one_enable = .false,
            };

        // ------------------------------------------------------------
        // Depth / stencil
        //
        // Для звичайного трикутника depth нам взагалі не потрібен.
        // ------------------------------------------------------------

        const depth_stencil =
            vulkan.PipelineDepthStencilStateCreateInfo{
                .s_type = .pipeline_depth_stencil_state_create_info,

                .depth_test_enable = .false,
                .depth_write_enable = .false,

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

        const blend_attachment =
            vulkan.PipelineColorBlendAttachmentState{
                // Для тестового трикутника blending вимикаємо.
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

        const dynamic_states =
            [_]vulkan.DynamicState{
                .viewport,
                .scissor,
            };

        const dynamic_state =
            vulkan.PipelineDynamicStateCreateInfo{
                .s_type = .pipeline_dynamic_state_create_info,

                .dynamic_state_count = dynamic_states.len,

                .p_dynamic_states = &dynamic_states,
            };

        // ------------------------------------------------------------
        // Pipeline layout
        //
        // Наші shaders поки не використовують descriptors,
        // push constants тощо.
        // ------------------------------------------------------------

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

        var native_pipelines =
            [_]vulkan.Pipeline{
                .null_handle,
            };

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

        const native_pipeline =
            native_pipelines[0];

        errdefer self.device.device.destroyPipeline(
            native_pipeline,
            null,
        );

        // ------------------------------------------------------------
        // Store pipeline
        // ------------------------------------------------------------

        const index: u32 =
            @intCast(self.graphics_pipelines.items.len);

        try self.graphics_pipelines.append(
            self.allocator,
            .{
                .handle = native_pipeline,
                .layout = layout,
            },
        );

        return .{
            .index = index,
            .generation = self.graphics_pipelines.items[index].generation,
        };
    }

    pub fn destroyGraphicsPipeline(
        self: *WindowContext,
        pipeline: Interface.Renderer.GraphicsPipeline,
    ) void {
        if (pipeline.index >=
            self.graphics_pipelines.items.len)
        {
            return;
        }

        const resource =
            &self.graphics_pipelines.items[
                pipeline.index
            ];

        if (resource.generation !=
            pipeline.generation or
            resource.handle ==
                .null_handle)
        {
            return;
        }

        self.device.device.destroyPipeline(
            resource.handle,
            null,
        );

        self.device.device.destroyPipelineLayout(
            resource.layout,
            null,
        );

        resource.handle =
            .null_handle;

        resource.layout =
            .null_handle;

        resource.generation +%= 1;
    }

    // ============================================================
    // Command pool
    // ============================================================

    fn createCommandPool(
        self: *WindowContext,
    ) !void {
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

    fn destroyCommandPool(
        self: *WindowContext,
    ) void {
        if (self.command_pool != .null_handle) {
            self.device.device.destroyCommandPool(
                self.command_pool,
                null,
            );

            self.command_pool =
                .null_handle;

            self.command_buffer =
                .null_handle;
        }
    }

    fn createCommandBuffer(
        self: *WindowContext,
    ) !void {
        const CommandBuffersInfo =
            vulkan.CommandBufferAllocateInfo{
                .s_type = .command_buffer_allocate_info,

                .command_buffer_count = 1,

                .command_pool = self.command_pool,

                .level = .primary,
            };

        var command_buffers =
            [_]vulkan.CommandBuffer{
                self.command_buffer,
            };

        try self.device.device
            .allocateCommandBuffers(
            &CommandBuffersInfo,
            &command_buffers,
        );

        self.command_buffer =
            command_buffers[0];
    }

    // ============================================================
    // Resource lookup
    // ============================================================

    fn getShaderModule(
        self: *const WindowContext,
        handle: Interface.Renderer.ShaderModule,
    ) !vulkan.ShaderModule {
        if (handle.index >=
            self.shader_modules.items.len)
        {
            return error.InvalidShaderModule;
        }

        const resource =
            self.shader_modules.items[
                handle.index
            ];

        if (resource.generation !=
            handle.generation or
            resource.handle ==
                .null_handle)
        {
            return error.InvalidShaderModule;
        }

        return resource.handle;
    }

    fn getGraphicsPipeline(
        self: *const WindowContext,
        handle: Interface.Renderer.GraphicsPipeline,
    ) !GraphicsPipelineResource {
        if (handle.index >=
            self.graphics_pipelines.items.len)
        {
            return error.InvalidGraphicsPipeline;
        }

        const resource =
            self.graphics_pipelines.items[
                handle.index
            ];

        if (resource.generation !=
            handle.generation or
            resource.handle ==
                .null_handle)
        {
            return error.InvalidGraphicsPipeline;
        }

        return resource;
    }

    // ============================================================
    // Framebuffers
    // ============================================================

    fn createFramebuffers(
        self: *WindowContext,
    ) !void {
        self.framebuffers =
            try self.allocator.alloc(
                vulkan.Framebuffer,
                self.swapchain_image_views.len,
            );

        for (
            self.swapchain_image_views,
            0..,
        ) |image_view, i| {
            const attachments =
                [_]vulkan.ImageView{
                    image_view,
                };

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

    fn destroyFramebuffers(
        self: *WindowContext,
    ) void {
        for (self.framebuffers) |framebuffer| {
            if (framebuffer != .null_handle) {
                self.device.device.destroyFramebuffer(
                    framebuffer,
                    null,
                );
            }
        }

        if (self.framebuffers.len != 0) {
            self.allocator.free(
                self.framebuffers,
            );

            self.framebuffers =
                &.{};
        }
    }

    // ============================================================
    // Frame
    // ============================================================

    pub fn beginFrame(
        self: *WindowContext,
    ) !void {
        if (self.frame_state.cmpxchgStrong(.idle, .recording, .acquire, .monotonic) != null) {
            return error.FrameIsNotIdle;
        }
        errdefer self.frame_state.store(.idle, .release);

        _ = try self.device.device.waitForFences(
            &.{self.in_flight_fence},
            .true,
            std.math.maxInt(u64),
        );

        const result =
            try self.device.device.acquireNextImageKHR(
                self.swapchain,
                std.math.maxInt(u64),
                self.image_available_semaphore,
                .null_handle,
            );

        self.current_image =
            result.image_index;

        try self.device.device.resetFences(
            &.{self.in_flight_fence},
        );

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

    pub fn bindPipeline(self: *WindowContext, pipeline: Interface.Renderer.GraphicsPipeline) !void {
        if (self.frame_state.load(.acquire) != .recording) return error.FrameIsNotReady;
        const resource =
            try self.getGraphicsPipeline(
                pipeline,
            );

        self.device.device.cmdBindPipeline(
            self.command_buffer,
            .graphics,
            resource.handle,
        );
    }

    pub fn draw(self: *WindowContext, vertex_count: u32, instance_count: u32) !void {
        if (self.frame_state.load(.acquire) != .recording) return error.FrameIsNotReady;
        self.device.device.cmdDraw(
            self.command_buffer,
            vertex_count,
            instance_count,
            0,
            0,
        );
    }

    pub fn endFrame(self: *WindowContext) !void {
        if (self.frame_state.cmpxchgStrong(.recording, .closing, .acquire, .monotonic) != null) {
            return error.InvalidFrameState;
        }
        errdefer self.frame_state.store(.recording, .release);
        self.device.device.cmdEndRenderPass(self.command_buffer);
        try self.device.device.endCommandBuffer(self.command_buffer);
    }

    // ============================================================
    // Present
    // ============================================================

    pub fn present(self: *WindowContext) !void {
        if (self.frame_state.load(.acquire) != .closing) return error.InvalidFrameState;
        defer self.frame_state.store(.idle, .release);
        errdefer self.frame_state.store(.idle, .release);
        const WaitStage =
            [_]vulkan.PipelineStageFlags{
                .{
                    .color_attachment_output_bit = true,
                },
            };
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

        // IMPORTANT:
        // Use this WindowContext's graphics queue.
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

        // IMPORTANT:
        // Use this WindowContext's present queue.
        _ = try self.device.device.queuePresentKHR(
            self.present_queue,
            &PresentInfo,
        );
    }

    // ============================================================
    // Synchronization
    // ============================================================

    fn createSyncObjects(self: *WindowContext) !void {
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
                &vulkan.SemaphoreCreateInfo{
                    .s_type = .semaphore_create_info,
                },
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

    fn destroySyncObjects(self: *WindowContext) void {
        if (self.in_flight_fence !=
            .null_handle)
        {
            self.device.device.destroyFence(
                self.in_flight_fence,
                null,
            );

            self.in_flight_fence =
                .null_handle;
        }

        for (self.render_finished_semaphores) |semaphore| {
            self.device.device.destroySemaphore(
                semaphore,
                null,
            );
        }

        self.allocator.free(self.render_finished_semaphores);

        if (self.image_available_semaphore !=
            .null_handle)
        {
            self.device.device.destroySemaphore(
                self.image_available_semaphore,
                null,
            );

            self.image_available_semaphore =
                .null_handle;
        }
    }

    // ============================================================
    // Physical device info
    // ============================================================

    pub inline fn getPhysicalDevice(self: *WindowContext) !Interface.DeviceInfo {
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
};
