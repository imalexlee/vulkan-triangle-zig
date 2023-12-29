pub const VulkanErrors = error{
    InstanceCreationError,
    InstanceLayerPropertiesError,
    ValidationLayersNotAvailable,
    PhysicalDeviceEnumerationError,
    DeviceExtensionError,
    CannotGetSurfaceCapabilities,
    CannotQuerySwapChain,
    CannotCreateSwapChain,
    CannotCreateImageViews,
    CannotCreateLogicalDevice,
    CannotCreateShaderModule,
    CannotCreatePipelineLayout,
    CannotCreateRenderPass,
    CannotCreateFrameBuffers,
    CannotCreateCommandPool,
    CannotCreateCommandBuffer,
    CannotRecordCommandBuffer,
    CannotCreateSyncObjects,
    CannotDrawFrame,
    NoSuitablePhysicalDevice,
    DebugMessangerError,
};

pub const GlfwErrors = error{
    WindowCreationError,
    SurfaceCreationError,
};
