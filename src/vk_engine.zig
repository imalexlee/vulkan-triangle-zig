const std = @import("std");
const c = @import("clibs.zig");
const errors = @import("errors.zig");
const vk_utils = @import("vk_utils.zig");
const models = @import("models.zig");

const Self = @This();
const VulkanErrors = errors.VulkanErrors;
const GlfwErrors = errors.GlfwErrors;

const WIDTH = 800;
const HEIGHT = 600;
const debug: bool = std.debug.runtime_safety;
const validation_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};
const device_extensions = [_][*:0]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    "VK_KHR_portability_subset",
};

allocator: std.mem.Allocator,
window: ?*c.GLFWwindow = null,

instance: c.VkInstance = null,
debug_messenger: c.VkDebugUtilsMessengerEXT = null,
physical_device: c.VkPhysicalDevice = null,
device: c.VkDevice = null,
graphics_queue: c.VkQueue = null,
present_queue: c.VkQueue = null,
surface: c.VkSurfaceKHR = null,
swap_chain: c.VkSwapchainKHR = null,
swap_chain_image: []c.VkImage = null,
required_extensions: [][*]const u8 = &.{},

fn debugCallback(
    severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    message_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: *c.VkDebugUtilsMessengerCallbackDataEXT,
    user_data: *void,
) callconv(.C) c.VkBool32 {
    _ = severity;
    _ = message_type;
    _ = user_data;

    std.debug.print("validation layer: {s}\n", .{callback_data.pMessage});
    return c.VK_FALSE;
}

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn run(self: *Self) !void {
    try initWindow(self);
    try initVulkan(self);
    mainLoop(self);
    cleanup(self);
}

fn initWindow(self: *Self) !void {
    const result = c.glfwInit();
    if (result != c.GL_TRUE) return GlfwErrors.WindowCreationError;
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    self.window = c.glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
}

fn initVulkan(self: *Self) !void {
    try createInstance(self);
    try setupDebugMessenger(self);
    try createSurface(self);
    try pickPhysicalDevice(self);
    try createLogicalDevice(self);
    try createSwapChain(self);
}

fn createSwapChain(self: *Self) !void {
    var swap_chain_support = try querySwapChainSupport(self, self.physical_device);
    const surface_format = chooseSwapSurfaceFormat(swap_chain_support.formats.?);
    const present_mode = chooseSwapPresentMode(swap_chain_support.present_modes.?);
    const extent = choseSwapExtent(self, &swap_chain_support.capabilities);
    var image_count = swap_chain_support.capabilities.minImageCount + 1;

    // 0 would indicate no limit to how many images
    if (swap_chain_support.capabilities.minImageCount > 0 and
        image_count > swap_chain_support.capabilities.maxImageCount)
    {
        image_count = swap_chain_support.capabilities.maxImageCount;
    }

    var swap_chain_create_info = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = self.surface,
        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    };

    const indices = try findQueueFamilies(self, self.physical_device);
    const queue_family_indices = [_]u32{
        indices.graphics_family.?,
        indices.present_family.?,
    };

    if (indices.graphics_family.? != indices.present_family.?) {
        swap_chain_create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        swap_chain_create_info.queueFamilyIndexCount = 2;
        swap_chain_create_info.pQueueFamilyIndices = @ptrCast(&queue_family_indices);
    } else {
        swap_chain_create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        swap_chain_create_info.queueFamilyIndexCount = 0;
        swap_chain_create_info.pQueueFamilyIndices = null;
    }

    swap_chain_create_info.preTransform = swap_chain_support.capabilities.currentTransform;
    swap_chain_create_info.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    swap_chain_create_info.presentMode = present_mode;
    swap_chain_create_info.clipped = c.VK_TRUE;
    swap_chain_create_info.oldSwapchain = null;

    const result = c.vkCreateSwapchainKHR(self.device, &swap_chain_create_info, null, &self.swap_chain);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateSwapChain;
}

fn querySwapChainSupport(self: *Self, device: c.VkPhysicalDevice) !models.SwapChainSupportDetails {
    var result: c.VkResult = undefined;
    var details = models.SwapChainSupportDetails{
        .capabilities = undefined,
        .formats = null,
        .present_modes = null,
    };
    result = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, self.surface, &details.capabilities);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotQuerySwapChain;

    var format_count: u32 = 0;
    result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, @ptrCast(&format_count), null);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotQuerySwapChain;

    if (format_count > 0) {
        details.formats = try self.allocator.alloc(c.VkSurfaceFormatKHR, format_count);
        result = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, details.formats.?.ptr);
        if (result != c.VK_SUCCESS) return VulkanErrors.CannotQuerySwapChain;
    }

    var present_mode_count: u32 = 0;
    result = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, self.surface, @ptrCast(&present_mode_count), null);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotQuerySwapChain;
    if (present_mode_count > 0) {
        details.present_modes = try self.allocator.alloc(c.VkPresentModeKHR, present_mode_count);
        result = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, self.surface, &present_mode_count, details.present_modes.?.ptr);
        if (result != c.VK_SUCCESS) return VulkanErrors.CannotQuerySwapChain;
    }

    return details;
}

fn chooseSwapSurfaceFormat(avail_formats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    for (avail_formats) |avail_format| {
        if (avail_format.format == c.VK_FORMAT_B8G8R8A8_SRGB and avail_format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return avail_format;
        }
    }
    // just return the first surface if we couldn't find one with SRGB
    return avail_formats[0];
}

fn choseSwapExtent(self: *Self, capabilities: *c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
    if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
        return capabilities.currentExtent;
    } else {
        var width: c_int = 0;
        var height: c_int = 0;
        c.glfwGetFramebufferSize(self.window, &width, &height);
        var actual_extent = c.VkExtent2D{
            .height = @intCast(height),
            .width = @intCast(width),
        };

        actual_extent.width = std.math.clamp(
            @as(u32, @intCast(width)),
            capabilities.minImageExtent.width,
            capabilities.maxImageExtent.width,
        );

        actual_extent.height = std.math.clamp(
            @as(u32, @intCast(height)),
            capabilities.minImageExtent.height,
            capabilities.maxImageExtent.height,
        );

        return actual_extent;
    }
}

fn chooseSwapPresentMode(avail_present_modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
    // fifo mode is guarunteed to exist
    for (avail_present_modes) |avail_present_mode| {
        if (avail_present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) return avail_present_mode;
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn createSurface(self: *Self) !void {
    const result = c.glfwCreateWindowSurface(self.instance, self.window, null, &self.surface);
    if (result != c.VK_SUCCESS) return GlfwErrors.SurfaceCreationError;
}

fn createLogicalDevice(self: *Self) !void {
    const indices = try findQueueFamilies(self, self.physical_device);

    var queue_priority: f32 = 1.0;

    const unique_queue_families = [_]?u32{ indices.graphics_family, indices.present_family };
    var queues = try self.allocator.alloc(c.VkDeviceQueueCreateInfo, unique_queue_families.len);
    defer self.allocator.free(queues);
    for (unique_queue_families, 0..) |family, i| {
        const queue_create_info = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = family.?,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
        queues[i] = queue_create_info;
    }

    var device_features = c.VkPhysicalDeviceFeatures{};

    var device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = @ptrCast(queues.ptr),
        .queueCreateInfoCount = @intCast(queues.len),
        .pEnabledFeatures = &device_features,
    };
    device_create_info.enabledExtensionCount = @intCast(device_extensions.len);
    device_create_info.ppEnabledExtensionNames = @ptrCast(&device_extensions);
    if (debug) {
        device_create_info.enabledLayerCount = @intCast(validation_layers.len);
        device_create_info.ppEnabledLayerNames = @ptrCast(&validation_layers);
    } else {
        device_create_info.enabledLayerCount = 0;
    }

    const result = c.vkCreateDevice(self.physical_device, &device_create_info, null, &self.device);
    if (result != c.VK_SUCCESS) {
        return VulkanErrors.CannotCreateLogicalDevice;
    }
    c.vkGetDeviceQueue(self.device, indices.graphics_family.?, 0, &self.graphics_queue);
    c.vkGetDeviceQueue(self.device, indices.present_family.?, 0, &self.present_queue);
}

fn pickPhysicalDevice(self: *Self) !void {
    var device_count: u32 = 0;
    var result: c.VkResult = undefined;
    result = c.vkEnumeratePhysicalDevices(self.instance, &device_count, null);
    // if not successful or no gpu at all, still an error
    if (result != c.VK_SUCCESS or device_count == 0) return VulkanErrors.PhysicalDeviceEnumerationError;
    const devices = try self.allocator.alloc(c.VkPhysicalDevice, device_count);
    defer self.allocator.free(devices);
    result = c.vkEnumeratePhysicalDevices(self.instance, &device_count, @ptrCast(devices));

    if (result != c.VK_SUCCESS) return VulkanErrors.PhysicalDeviceEnumerationError;

    for (devices) |device| {
        if (try isDeviceSuitable(self, device)) {
            self.physical_device = device;
            break;
        }
    }

    if (self.physical_device == null) return VulkanErrors.NoSuitablePhysicalDevice;
}

fn isDeviceSuitable(self: *Self, device: c.VkPhysicalDevice) !bool {
    const indices = try findQueueFamilies(self, device);
    const extensions_supported = try checkDeviceExtensionSupport(self, device);
    var swap_chain_adequate: bool = false;
    if (extensions_supported) {
        const swap_chain_details = try querySwapChainSupport(self, device);
        if (swap_chain_details.present_modes != null and swap_chain_details.formats != null) {
            swap_chain_adequate = true;
        }
    }

    return (indices.isComplete() and extensions_supported and swap_chain_adequate);
}

fn checkDeviceExtensionSupport(self: *Self, device: c.VkPhysicalDevice) !bool {
    var result: c.VkResult = undefined;
    var ext_count: u32 = undefined;

    result = c.vkEnumerateDeviceExtensionProperties(device, null, &ext_count, null);
    if (result != c.VK_SUCCESS) return VulkanErrors.DeviceExtensionError;

    const avail_extensions = try self.allocator.alloc(c.VkExtensionProperties, ext_count);
    defer self.allocator.free(avail_extensions);
    result = c.vkEnumerateDeviceExtensionProperties(device, null, &ext_count, avail_extensions.ptr);
    if (result != c.VK_SUCCESS) return VulkanErrors.DeviceExtensionError;
    for (device_extensions) |req_ext| {
        var ext_exists: bool = false;
        for (avail_extensions) |avail_ext| {
            const req_ext_slice = std.mem.span(req_ext);
            if (std.mem.eql(u8, req_ext_slice, avail_ext.extensionName[0..req_ext_slice.len])) {
                ext_exists = true;
            }
        }
        if (!ext_exists) return false;
    }
    return true;
}

fn findQueueFamilies(self: *Self, device: c.VkPhysicalDevice) !models.QueueFamilyIndices {
    var indices: models.QueueFamilyIndices = undefined;
    var queue_family_count: u32 = 0;

    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
    const queue_familes = try self.allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
    defer self.allocator.free(queue_familes);
    c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_familes.ptr);

    var i: u32 = 0;
    for (queue_familes) |family| {
        if ((family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) == 1) {
            indices.graphics_family = i;
        }
        var present_support: c.VkBool32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, i, self.surface, &present_support);
        if (present_support == c.VK_TRUE) indices.present_family = i;

        if (indices.isComplete()) break;
        i += 1;
    }

    return indices;
}

fn populateDebugMessengerCreateInfo(create_info: *c.VkDebugUtilsMessengerCreateInfoEXT) void {
    create_info.sType =
        c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;

    create_info.messageSeverity =
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;

    create_info.messageType =
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;

    create_info.pNext = null;
    create_info.flags = 0;
    create_info.pfnUserCallback = @ptrCast(&debugCallback);
}

fn setupDebugMessenger(self: *Self) !void {
    if (!debug) return;

    var debug_create_info: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;
    populateDebugMessengerCreateInfo(&debug_create_info);

    const result = vk_utils.CreateDebugUtilsMessengerEXT(self.instance, &debug_create_info, null, &self.debug_messenger);
    if (result != c.VK_SUCCESS) return VulkanErrors.DebugMessangerError;
}

fn checkValidationLayerSupport(self: *Self) !bool {
    var layer_count: u32 = 0;
    var result: c.VkResult = undefined;
    result = c.vkEnumerateInstanceLayerProperties(&layer_count, null);
    if (result != c.VK_SUCCESS) return VulkanErrors.InstanceLayerPropertiesError;

    const avail_layers = try self.allocator.alloc(c.VkLayerProperties, layer_count);
    defer self.allocator.free(avail_layers);

    result = c.vkEnumerateInstanceLayerProperties(&layer_count, @ptrCast(avail_layers));
    if (result != c.VK_SUCCESS) return VulkanErrors.InstanceLayerPropertiesError;

    for (validation_layers) |layer| {
        var layer_found: bool = false;
        for (avail_layers) |avail_layer| {
            const layer_slice = std.mem.span(layer);
            const equal = std.mem.eql(u8, layer_slice, avail_layer.layerName[0..layer_slice.len]);

            if (equal) {
                layer_found = true;
                break;
            }
        }
        if (!layer_found) return false;
    }
    return true;
}

fn getRequiredExtensions(self: *Self) ![][*]const u8 {
    var glfw_ext_count: u32 = 0;

    const glfw_extensions = c.glfwGetRequiredInstanceExtensions(&glfw_ext_count);

    var glfw_ext_list = std.ArrayList([*:0]const u8).init(self.allocator);
    //try glfw_ext_list.appendSlice(@ptrCast(glfw_extensions));
    for (0..glfw_ext_count) |i| {
        try glfw_ext_list.append(glfw_extensions[i]);
    }
    if (debug) try glfw_ext_list.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

    // adding KHR_PORTABILITY_SUBSET is required for moltenVK
    try glfw_ext_list.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);

    // add following extension to play well with M1 Mac
    try glfw_ext_list.append(c.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);

    glfw_ext_list.shrinkAndFree(glfw_ext_list.items.len);

    return glfw_ext_list.items;
}

fn createInstance(self: *Self) !void {
    if (debug) {
        const layers_supported = try checkValidationLayerSupport(self);
        if (!layers_supported) return VulkanErrors.ValidationLayersNotAvailable;
    }

    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "vulkan-tutorial-zig",
        .applicationVersion = c.VK_MAKE_API_VERSION(0, 1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_API_VERSION(0, 1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    self.required_extensions = try getRequiredExtensions(self);

    var debug_create_info: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;
    if (debug) populateDebugMessengerCreateInfo(&debug_create_info);

    var instance_create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(self.required_extensions.len),
        .ppEnabledExtensionNames = @ptrCast(self.required_extensions.ptr),
        .ppEnabledLayerNames = if (debug) @ptrCast(&validation_layers) else null,
        .enabledLayerCount = if (debug) validation_layers.len else 0,
        .pNext = if (debug) @as(*c.VkDebugUtilsMessengerCreateInfoEXT, @ptrCast(&debug_create_info)) else null,
    };

    instance_create_info.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;

    const result = c.vkCreateInstance(&instance_create_info, null, &self.instance);
    if (result != c.VK_SUCCESS) return VulkanErrors.InstanceCreationError;
}

fn mainLoop(self: *Self) void {
    while (c.glfwWindowShouldClose(self.window) == 0) {
        c.glfwPollEvents();
    }
}

fn cleanup(self: *Self) void {
    if (debug) vk_utils.DestroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
    c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
    c.vkDestroyDevice(self.device, null);
    c.vkDestroySurfaceKHR(self.instance, self.surface, null);
    c.vkDestroyInstance(self.instance, null);
    c.glfwDestroyWindow(self.window);
    c.glfwTerminate();
}
