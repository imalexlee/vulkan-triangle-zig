# vulkan-triangle-zig
zig implementation of an RGB triangle using the Vulkan graphics API. Uses glfw for windowing.
<img width="912" alt="Screenshot 2024-01-01 at 3 14 22 PM" src="https://github.com/imalexlee/vulkan-triangle-zig/assets/106715298/c054cf11-237d-4fd7-8c5e-0b509063dc47">

## Notes
- originally written to be compiled by zig-0.12.0-dev.1861+412999621 compiler
- must install Vulkan and glfw as a system library
- compiled on an M1 mac and therefore you need MoltenVK if you're doing the same. This will come with your Vulkan install.
- use `zig build run` to build an run
