pub const VulkanErrors = error{
    InstanceCreationError,
    InstanceLayerPropertiesError,
    ValidationLayersNotAvailable,
    PhysicalDeviceEnumerationError,
    DeviceExtensionError,
    CannotGetSurfaceCapabilities,
    CannotQuerySwapChain,
    CannotCreateSwapChain,
    CannotCreateLogicalDevice,
    NoSuitablePhysicalDevice,
    DebugMessangerError,
};

pub const GlfwErrors = error{
    WindowCreationError,
    SurfaceCreationError,
};
