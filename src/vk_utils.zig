const std = @import("std");
const c = @import("clibs.zig");

pub fn CreateDebugUtilsMessengerEXT(
    instance: c.VkInstance,
    create_info: *c.VkDebugUtilsMessengerCreateInfoEXT,
    allocator: ?*c.VkAllocationCallbacks,
    debug_messenger: *c.VkDebugUtilsMessengerEXT,
) c.VkResult {
    var func: c.PFN_vkCreateDebugUtilsMessengerEXT = undefined;
    func = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT") orelse return c.VK_ERROR_EXTENSION_NOT_PRESENT);
    return func.?(instance, create_info, allocator, debug_messenger);
}

pub fn DestroyDebugUtilsMessengerEXT(
    instance: c.VkInstance,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
    allocator: ?*c.VkAllocationCallbacks,
) void {
    var func: c.PFN_vkDestroyDebugUtilsMessengerEXT = undefined;
    func = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (func != null) func.?(instance, debug_messenger, allocator);
}
