const std = @import("std");
const c = @import("clibs.zig");
const errors = @import("errors.zig");
const VulkanErrors = errors.VulkanErrors;

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

pub fn createShaderModule(device: c.VkDevice, shader_buffer: []align(@alignOf(u32)) const u8) !c.VkShaderModule {
    var shader_module_create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = shader_buffer.len,
        .pCode = std.mem.bytesAsSlice(u32, shader_buffer).ptr,
    };
    var shader_module: c.VkShaderModule = null;
    const result = c.vkCreateShaderModule(device, &shader_module_create_info, null, &shader_module);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateShaderModule;

    return shader_module;
}

// pub fn readShaderFile(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
//    const file = try std.fs.cwd().openFile(file_path, .{});
//    defer file.close();
//    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
// }
