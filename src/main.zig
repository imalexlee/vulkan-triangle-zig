const std = @import("std");
const vk = @import("vk.zig");
const vk_engine = @import("vk_engine.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    var engine = vk_engine.init(arena.allocator());

    try engine.run();
}
