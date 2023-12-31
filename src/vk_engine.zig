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
const MAX_FRAMES_IN_FLIGHT = 2;
const DEBUG: bool = std.debug.runtime_safety;
const validation_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};
const device_extensions = [_][*:0]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    "VK_KHR_portability_subset",
};

required_extensions: [][*]const u8 = &.{},

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
swap_chain_images: []c.VkImage = &.{},
swap_chain_extent: c.VkExtent2D = undefined,
swap_chain_image_format: c.VkFormat = undefined,
swap_chain_image_views: []c.VkImageView = &.{},
swap_chain_frame_buffers: []c.VkFramebuffer = &.{},

render_pass: c.VkRenderPass = null,
pipeline_layout: c.VkPipelineLayout = null,
graphics_pipeline: c.VkPipeline = null,

command_pool: c.VkCommandPool = null,
command_buffers: []c.VkCommandBuffer = &.{},

//syncing stuff
image_available_semaphores: []c.VkSemaphore = &.{},
render_finished_semaphores: []c.VkSemaphore = &.{},
in_flight_fences: []c.VkFence = &.{},
current_frame: u1 = 0,

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
    try mainLoop(self);
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
    try createImageViews(self);
    try createRenderPass(self);
    try createGraphicsPipeline(self);
    try createFrameBuffers(self);
    try createCommandPool(self);
    try createCommandBuffers(self);
    try createSyncObjects(self);
}

fn recreateSwapchain(self: *Self) !void {
    _ = c.vkDeviceWaitIdle(self.device);
    try cleanupSwapchain(self);
    try createSwapChain(self);
    try createImageViews(self);
    try createFrameBuffers(self);
}

fn createSyncObjects(self: *Self) !void {
    var result: c.VkResult = undefined;

    self.image_available_semaphores = try self.allocator.alloc(c.VkSemaphore, MAX_FRAMES_IN_FLIGHT);
    self.render_finished_semaphores = try self.allocator.alloc(c.VkSemaphore, MAX_FRAMES_IN_FLIGHT);
    self.in_flight_fences = try self.allocator.alloc(c.VkFence, MAX_FRAMES_IN_FLIGHT);

    const semaphore_create_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    const fence_create_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        result = c.vkCreateSemaphore(self.device, &semaphore_create_info, null, &self.image_available_semaphores[i]);
        if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateSyncObjects;

        result = c.vkCreateSemaphore(self.device, &semaphore_create_info, null, &self.render_finished_semaphores[i]);
        if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateSyncObjects;

        result = c.vkCreateFence(self.device, &fence_create_info, null, &self.in_flight_fences[i]);
        if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateSyncObjects;
    }
}

fn createCommandBuffers(self: *Self) !void {
    self.command_buffers = try self.allocator.alloc(c.VkCommandBuffer, MAX_FRAMES_IN_FLIGHT);
    const command_buffer_allocate_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(self.command_buffers.len),
    };

    const result = c.vkAllocateCommandBuffers(self.device, &command_buffer_allocate_info, self.command_buffers.ptr);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateCommandBuffer;
}

fn recordCommandBuffer(self: *Self, command_buffer: c.VkCommandBuffer, image_index: u32) !void {
    var result: c.VkResult = undefined;
    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        //.flags = c.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT,
    };

    result = c.vkBeginCommandBuffer(command_buffer, &begin_info);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotRecordCommandBuffer;

    const clear_values = [_]c.VkClearColorValue{
        c.VkClearColorValue{ .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 } },
    };
    const render_pass_begin_info = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = self.render_pass,
        .framebuffer = self.swap_chain_frame_buffers[image_index],
        .renderArea = .{
            .offset = .{
                .x = 0,
                .y = 0,
            },
            .extent = self.swap_chain_extent,
        },
        .clearValueCount = 1,
        .pClearValues = @ptrCast(&clear_values),
    };

    c.vkCmdBeginRenderPass(command_buffer, &render_pass_begin_info, c.VK_SUBPASS_CONTENTS_INLINE);

    c.vkCmdBindPipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphics_pipeline);

    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(self.swap_chain_extent.width),
        .height = @floatFromInt(self.swap_chain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

    const scissor = c.VkRect2D{
        .extent = self.swap_chain_extent,
        .offset = .{
            .x = 0,
            .y = 0,
        },
    };

    c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

    c.vkCmdDraw(command_buffer, 3, 1, 0, 0);

    c.vkCmdEndRenderPass(command_buffer);

    result = c.vkEndCommandBuffer(command_buffer);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotRecordCommandBuffer;
}

fn createCommandPool(self: *Self) !void {
    const queue_family_indices = try findQueueFamilies(self, self.physical_device);

    const command_pool_create_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_indices.graphics_family.?,
    };

    const result = c.vkCreateCommandPool(self.device, &command_pool_create_info, null, &self.command_pool);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateCommandPool;
}

fn createFrameBuffers(self: *Self) !void {
    self.swap_chain_frame_buffers = try self.allocator.alloc(c.VkFramebuffer, self.swap_chain_image_views.len);

    for (self.swap_chain_image_views, 0..) |image_view, i| {
        const frame_buffer_create_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = self.render_pass,
            .attachmentCount = 1,
            .pAttachments = &image_view,
            .width = self.swap_chain_extent.width,
            .height = self.swap_chain_extent.height,
            .layers = 1,
        };
        const result = c.vkCreateFramebuffer(self.device, &frame_buffer_create_info, null, &self.swap_chain_frame_buffers[i]);
        if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateFrameBuffers;
    }
}

fn createRenderPass(self: *Self) !void {
    const color_attachment_desc = c.VkAttachmentDescription{
        .format = self.swap_chain_image_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        // we don't care about initial layout since we set the loading
        // operation to clear the image anyway upon loading.
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const attachment_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass_desc = c.VkSubpassDescription{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &attachment_ref,
    };

    const dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    const render_pass_create_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment_desc,
        .subpassCount = 1,
        .pSubpasses = &subpass_desc,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };

    const result = c.vkCreateRenderPass(self.device, &render_pass_create_info, null, &self.render_pass);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateRenderPass;
}

fn createGraphicsPipeline(self: *Self) !void {
    const vert_shader_code align(4) = @embedFile("shaders/vert.spv").*;
    const frag_shader_code align(4) = @embedFile("shaders/frag.spv").*;

    const vert_shader_module = try vk_utils.createShaderModule(self.device, &vert_shader_code);
    const frag_shader_module = try vk_utils.createShaderModule(self.device, &frag_shader_code);

    var result: c.VkResult = undefined;

    const vert_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_shader_module,
        .pName = "main",
    };

    const frag_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_shader_module,
        .pName = "main",
    };

    const shader_stages = [_]c.VkPipelineShaderStageCreateInfo{ vert_shader_stage_info, frag_shader_stage_info };

    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    const dynamic_states = [_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };
    const dynamic_state_info = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .pDynamicStates = &dynamic_states,
        .dynamicStateCount = @intCast(dynamic_states.len),
    };

    const viewport_state_info = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .scissorCount = 1,
        .viewportCount = 1,
    };

    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        // play around with this. need to enable a gpu feature for this
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        // if you want thicker lines, must enable the wideLines gpu feature
        .lineWidth = 1.0,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };

    const multisampling_create_info = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = c.VK_FALSE,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    // here we've disable both blending and bitwise op color blending.
    // this means that colors are written to the framebuffer unmodified.
    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT |
            c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT |
            c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = c.VK_FALSE,
        // these get thrown out since blending is disabled
        // just here for reference
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };

    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };

    const layout_create_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };

    result = c.vkCreatePipelineLayout(self.device, &layout_create_info, null, &self.pipeline_layout);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreatePipelineLayout;

    const pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly,
        .pViewportState = &viewport_state_info,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling_create_info,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dynamic_state_info,
        .layout = self.pipeline_layout,
        .renderPass = self.render_pass,
        .subpass = 0,
    };

    result = c.vkCreateGraphicsPipelines(self.device, null, 1, &pipeline_create_info, null, &self.graphics_pipeline);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreatePipelineLayout;

    c.vkDestroyShaderModule(self.device, vert_shader_module, null);
    c.vkDestroyShaderModule(self.device, frag_shader_module, null);
}

fn createImageViews(self: *Self) !void {
    self.swap_chain_image_views = try self.allocator.alloc(c.VkImageView, self.swap_chain_images.len);
    for (self.swap_chain_images, 0..) |image, i| {
        const image_view_create_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = self.swap_chain_image_format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        const result = c.vkCreateImageView(self.device, &image_view_create_info, null, &self.swap_chain_image_views[i]);
        if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateImageViews;
    }
}

fn createSwapChain(self: *Self) !void {
    var swap_chain_support = try querySwapChainSupport(self, self.physical_device);
    const surface_format = chooseSwapSurfaceFormat(swap_chain_support.formats.?);
    const present_mode = chooseSwapPresentMode(swap_chain_support.present_modes.?);
    const extent = choseSwapExtent(self, &swap_chain_support.capabilities);
    var image_count = swap_chain_support.capabilities.minImageCount + 1;
    var result: c.VkResult = undefined;

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

    result = c.vkCreateSwapchainKHR(self.device, &swap_chain_create_info, null, &self.swap_chain);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateSwapChain;

    result = c.vkGetSwapchainImagesKHR(self.device, self.swap_chain, &image_count, null);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateSwapChain;

    self.swap_chain_images = try self.allocator.alloc(c.VkImage, image_count);
    result = c.vkGetSwapchainImagesKHR(self.device, self.swap_chain, &image_count, self.swap_chain_images.ptr);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotCreateSwapChain;

    self.swap_chain_image_format = surface_format.format;
    self.swap_chain_extent = extent;
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
        .pQueueCreateInfos = queues.ptr,
        .queueCreateInfoCount = @intCast(queues.len),
        .pEnabledFeatures = &device_features,
    };
    device_create_info.enabledExtensionCount = @intCast(device_extensions.len);
    device_create_info.ppEnabledExtensionNames = @ptrCast(&device_extensions);
    if (DEBUG) {
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

fn findQueueFamilies(self: *Self, physical_device: c.VkPhysicalDevice) !models.QueueFamilyIndices {
    var indices: models.QueueFamilyIndices = undefined;
    var queue_family_count: u32 = 0;

    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, null);
    const queue_familes = try self.allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
    defer self.allocator.free(queue_familes);
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, queue_familes.ptr);

    var i: u32 = 0;
    for (queue_familes) |family| {
        if ((family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) == 1) {
            indices.graphics_family = i;
        }
        var present_support: c.VkBool32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, i, self.surface, &present_support);
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
    if (!DEBUG) return;

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
    if (DEBUG) try glfw_ext_list.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

    // adding KHR_PORTABILITY_SUBSET is required for moltenVK
    try glfw_ext_list.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);

    // add following extension to play well with M1 Mac
    try glfw_ext_list.append(c.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);

    glfw_ext_list.shrinkAndFree(glfw_ext_list.items.len);

    return glfw_ext_list.items;
}

fn createInstance(self: *Self) !void {
    if (DEBUG) {
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
    if (DEBUG) populateDebugMessengerCreateInfo(&debug_create_info);

    var instance_create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(self.required_extensions.len),
        .ppEnabledExtensionNames = @ptrCast(self.required_extensions.ptr),
        .ppEnabledLayerNames = if (DEBUG) @ptrCast(&validation_layers) else null,
        .enabledLayerCount = if (DEBUG) validation_layers.len else 0,
        .pNext = if (DEBUG) @as(*c.VkDebugUtilsMessengerCreateInfoEXT, @ptrCast(&debug_create_info)) else null,
    };

    instance_create_info.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;

    const result = c.vkCreateInstance(&instance_create_info, null, &self.instance);
    if (result != c.VK_SUCCESS) return VulkanErrors.InstanceCreationError;
}

fn mainLoop(self: *Self) !void {
    while (c.glfwWindowShouldClose(self.window) == 0) {
        c.glfwPollEvents();
        try drawFrame(self);
    }

    _ = c.vkDeviceWaitIdle(self.device);
}

fn drawFrame(self: *Self) !void {
    var result: c.VkResult = undefined;

    result = c.vkWaitForFences(self.device, 1, &self.in_flight_fences[self.current_frame], c.VK_TRUE, std.math.maxInt(u64));
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotDrawFrame;

    var image_index: u32 = undefined;
    result = c.vkAcquireNextImageKHR(self.device, self.swap_chain, std.math.maxInt(u64), self.image_available_semaphores[self.current_frame], null, &image_index);

    switch (result) {
        c.VK_ERROR_OUT_OF_DATE_KHR => {
            try recreateSwapchain(self);
            return;
        },
        c.VK_SUBOPTIMAL_KHR => {},
        c.VK_SUCCESS => {},
        else => return VulkanErrors.CannotDrawFrame,
    }

    result = c.vkResetFences(self.device, 1, &self.in_flight_fences[self.current_frame]);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotDrawFrame;

    _ = c.vkResetCommandBuffer(self.command_buffers[self.current_frame], 0);

    try recordCommandBuffer(self, self.command_buffers[self.current_frame], image_index);

    const wait_semaphores = [_]c.VkSemaphore{self.image_available_semaphores[self.current_frame]};
    const signal_semaphores = [_]c.VkSemaphore{self.render_finished_semaphores[self.current_frame]};
    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &wait_semaphores,
        .pWaitDstStageMask = &wait_stages,
        .commandBufferCount = 1,
        .pCommandBuffers = &self.command_buffers[self.current_frame],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &signal_semaphores,
    };

    result = c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.in_flight_fences[self.current_frame]);
    if (result != c.VK_SUCCESS) return VulkanErrors.CannotDrawFrame;

    const swap_chains = [_]c.VkSwapchainKHR{self.swap_chain};
    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &signal_semaphores,
        .swapchainCount = 1,
        .pSwapchains = &swap_chains,
        .pImageIndices = &image_index,
        .pResults = null,
    };

    result = c.vkQueuePresentKHR(self.present_queue, &present_info);

    switch (result) {
        c.VK_ERROR_OUT_OF_DATE_KHR, c.VK_SUBOPTIMAL_KHR => {
            try recreateSwapchain(self);
        },
        c.VK_SUCCESS => {},
        else => return VulkanErrors.CannotDrawFrame,
    }

    // flip current frame between 1 and 0.
    // only works if MAX_FRAMES_IN_FLIGHT == 2 but this is a hot function
    // so might as well.
    self.current_frame ^= 1;
}

fn cleanupSwapchain(self: *Self) !void {
    for (self.swap_chain_frame_buffers) |frame_buffer| {
        c.vkDestroyFramebuffer(self.device, frame_buffer, null);
    }

    for (self.swap_chain_image_views) |image_view| {
        c.vkDestroyImageView(self.device, image_view, null);
    }

    c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
}

fn cleanup(self: *Self) void {
    try cleanupSwapchain(self);
    if (DEBUG) vk_utils.DestroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);

    for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        c.vkDestroySemaphore(self.device, self.image_available_semaphores[i], null);
        c.vkDestroySemaphore(self.device, self.render_finished_semaphores[i], null);
        c.vkDestroyFence(self.device, self.in_flight_fences[i], null);
    }

    c.vkDestroyCommandPool(self.device, self.command_pool, null);
    c.vkDestroyPipeline(self.device, self.graphics_pipeline, null);
    c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
    c.vkDestroyRenderPass(self.device, self.render_pass, null);

    c.vkDestroyDevice(self.device, null);
    c.vkDestroySurfaceKHR(self.instance, self.surface, null);
    c.vkDestroyInstance(self.instance, null);
    c.glfwDestroyWindow(self.window);
    c.glfwTerminate();
}
