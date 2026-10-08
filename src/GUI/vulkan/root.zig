const vulkan = @import("vulkan");
const builtin = @import("builtin");
const Conf = @import("Conf");

pub const enable_validation_layers = builtin.mode == .Debug or Conf.renderer_extensions;

pub const required_layer_names = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

pub const required_device_extensions = [_][*:0]const u8{
    vulkan.extensions.khr_swapchain.name,
};

pub const BaseWrapper = vulkan.BaseWrapper;
pub const InstanceWrapper = vulkan.InstanceWrapper;
pub const DeviceWrapper = vulkan.DeviceWrapper;

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
