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
    NoSuitablePhysicalDevice,
    DebugMessangerError,
};

pub const GlfwErrors = error{
    WindowCreationError,
    SurfaceCreationError,
};
