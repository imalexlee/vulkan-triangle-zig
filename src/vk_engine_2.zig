//const std = @import("std");
//const glfw = @import("mach-glfw");
//const vk = @import("vk.zig");
//const Self = @This();
//
//window: glfw.Window = undefined,
//is_initialized: bool = false,
//frame_num: u32 = 0,
//
//instance: vk.Instance = undefined,
//debug_messenger: vk.DebugUtilsMessengerEXT = undefined,
//chosen_gpu: vk.PhysicalDevice = undefined,
//device: vk.Device = undefined,
//surface: vk.SurfaceKHR = undefined,
//
///// Default GLFW error handling callback
//fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
//    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
//}
//
//pub fn init() Self {
//    glfw.setErrorCallback(errorCallback);
//    if (!glfw.init(.{})) {
//        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
//        std.process.exit(1);
//    }
//
//    const vec = glm.vec4;
//    _ = vec;
//    // Create our window
//    const window = glfw.Window.create(640, 480, "Vulkan Engine", null, null, .{}) orelse {
//        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
//        std.process.exit(1);
//    };
//
//    initVulkan();
//
//    return Self{
//        .window = window,
//        .is_initialized = true,
//    };
//}
//
//pub fn initVulkan() void {}
//
//pub fn run(self: *Self) void {
//
//    // Wait for the user to close the window.
//    while (!self.window.shouldClose()) {
//        self.window.swapBuffers();
//        glfw.pollEvents();
//        draw();
//    }
//}
//
//pub fn draw() void {}
//
//pub fn cleanup(self: *Self) void {
//    if (self.is_initialized) {
//        self.window.destroy();
//        glfw.terminate();
//    }
//}
