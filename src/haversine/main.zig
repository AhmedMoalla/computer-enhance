const std = @import("std");
const utils = @import("utils");
const generator = @import("generator.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const args = try utils.readAllArgsAlloc(allocator);
    if (args.has("generator")) {
        try generator.run();
    }
}
