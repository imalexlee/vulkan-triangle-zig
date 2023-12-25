const std = @import("std");
const vk = @import("vk.zig");
const vk_engine = @import("vk_engine.zig");

pub fn main() !void {
    var engine = vk_engine.init();

    try engine.run();
}
