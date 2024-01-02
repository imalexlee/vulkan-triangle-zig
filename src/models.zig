const c = @import("clibs.zig");

pub const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,

    pub fn isComplete(self: @This()) bool {
        return (self.graphics_family != null and self.present_family != null);
    }
};

pub const SwapChainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: ?[]c.VkSurfaceFormatKHR,
    present_modes: ?[]c.VkPresentModeKHR,
};
