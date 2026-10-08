const std = @import("std");
const vulkan = @import("vulkan");
const glfw = @import("glfw");
const Interface = @import("Interface");
const Conf = @import("Conf");
const shared = @import("root.zig");
const Self = @This();

allocator: std.mem.Allocator,

vbw: shared.BaseWrapper,

instance: vulkan.InstanceProxy,
debug_messenger: vulkan.DebugUtilsMessengerEXT,

device: *shared.DeviceInfo,

pub fn init(allocator: std.mem.Allocator) !Self {
    var self: Self = undefined;

    self.allocator = allocator;

    self.vbw = shared.BaseWrapper.load(getGlfwInstanceProcAddr);

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

pub fn deinit(self: *Self) void {
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

fn checkLayerSupport(self: *Self) !bool {
    const available_layers =
        try self.vbw.enumerateInstanceLayerPropertiesAlloc(
            self.allocator,
        );

    defer self.allocator.free(available_layers);

    for (shared.required_layer_names) |required| {
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

inline fn createInstance(self: *Self) !void {
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

        .enabled_layer_count = shared.required_layer_names.len,

        .pp_enabled_layer_names = @ptrCast(&shared.required_layer_names),

        .flags = .{
            .enumerate_portability_bit_khr = true,
        },
    };

    const vki =
        try self.allocator.create(shared.InstanceWrapper);

    errdefer self.allocator.destroy(vki);

    const instance =
        try self.vbw.createInstance(
            &CreateInfo,
            null,
        );

    vki.* = shared.InstanceWrapper.load(
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

inline fn setupDebugMessenger(self: *Self) !void {
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
    self: *Self,
    selection: Interface.DeviceSelection,
) !void {
    self.deinitDevice();

    errdefer self.deinitDevice();

    try self.initDevice(selection);
}

inline fn initDevice(
    self: *Self,
    selection: Interface.DeviceSelection,
) !void {
    const device =
        try self.pickPhysicalDevice(
            selection,
            null,
        );

    self.device = device;
}

inline fn deinitDevice(self: *Self) void {
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
    self: *Self,
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
    self: *Self,
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
    self: *Self,
    selection: Interface.DeviceSelection,
    surface: ?vulkan.SurfaceKHR,
) !*shared.DeviceInfo {
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
        try self.allocator.create(shared.DeviceInfo);

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
        &shared.required_device_extensions;

    extension_count =
        shared.required_device_extensions.len;

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
            shared.DeviceWrapper,
        );

    errdefer self.allocator.destroy(vkd);

    const device =
        try self.instance.createDevice(
            selected.physicalDevice,
            &CreateInfo,
            null,
        );

    vkd.* =
        shared.DeviceWrapper.load(
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

    return selected;
}

inline fn isDeviceSuitable(
    self: *Self,
    device: vulkan.PhysicalDevice,
    surface: ?vulkan.SurfaceKHR,
) !?shared.QueueFamilyIndices {
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
            return shared.QueueFamilyIndices{
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
