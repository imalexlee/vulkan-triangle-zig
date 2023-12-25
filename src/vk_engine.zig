const std = @import("std");
const c = @import("clibs.zig");
const errors = @import("errors.zig");

const Self = @This();
const VulkanErrors = errors.VulkanErrors;

const WIDTH = 800;
const HEIGHT = 600;

window: ?*c.GLFWwindow = undefined,

instance: c.VkInstance = undefined,
debug_messenger: c.VkDebugUtilsMessengerEXT = undefined,
chosen_gpu: c.VkPhysicalDevice = undefined,
device: c.VkDevice = undefined,
surface: c.VkSurfaceKHR = undefined,

pub fn init() Self {
    return Self{};
}

pub fn run(self: *Self) !void {
    initWindow(self);
    try initVulkan(self);
    mainLoop(self);
    cleanup(self);
}

fn initWindow(self: *Self) void {
    _ = c.glfwInit();
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    self.window = c.glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
}

fn initVulkan(self: *Self) !void {
    try createInstance(self);
}

fn createInstance(self: *Self) !void {
    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "vulkan-tutorial-zig",
        .applicationVersion = c.VK_MAKE_API_VERSION(0, 1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_API_VERSION(0, 1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    var ext_count: u32 = 0;
    const glfw_extensions = c.glfwGetRequiredInstanceExtensions(&ext_count);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var ext_list = std.ArrayList([*:0]const u8).init(gpa.allocator());
    defer ext_list.deinit();

    // adding KHR_PORTABILITY_SUBSET is required for moltenVK
    for (0..ext_count) |i| {
        try ext_list.append(glfw_extensions[i]);
    }

    try ext_list.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);

    var create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = if (glfw_extensions != null) @intCast(ext_list.items.len) else 0,
        .ppEnabledExtensionNames = ext_list.items.ptr,
        .enabledLayerCount = 0,
    };
    create_info.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;

    const result = c.vkCreateInstance(&create_info, null, &self.instance);
    if (result != c.VK_SUCCESS) return VulkanErrors.InstanceCreationError;
}

fn mainLoop(self: *Self) void {
    while (c.glfwWindowShouldClose(self.window) == 0) {
        c.glfwPollEvents();
    }
}

fn cleanup(self: *Self) void {
    c.vkDestroyInstance(self.instance, null);
    c.glfwDestroyWindow(self.window);
    c.glfwTerminate();
}
