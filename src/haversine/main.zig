const std = @import("std");
const utils = @import("utils");
const generator = @import("generator.zig");
const parser = @import("parser.zig");
const haversine = @import("haversine.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const args = try utils.readAllArgsAlloc(allocator);
    if (args.has("generator")) {
        try generator.run();
    }

    if (args.items.len < 2) {
        std.log.err("usage: {s} [haversine_input.json] [answers.f64]", .{args.program_name});
        std.process.exit(1);
    }

    const inputs_file = try utils.openFileReaderAlloc(allocator, args.pos(0).?);
    const inputs = try parser.parseHaversineInputs(allocator, inputs_file.interface, 10000);

    var sum: f64 = 0;
    const sum_coef = 1.0 / @as(f64, @floatFromInt(inputs.len));
    for (inputs) |input| {
        sum += sum_coef * haversine.reference(input.x0, input.y0, input.x1, input.y1);
    }

    const stats = try inputs_file.file.stat();
    std.log.info("Input size: {d}", .{stats.size});
    std.log.info("Pair count: {d}", .{inputs.len});
    std.log.info("Havesine sum: {d}", .{sum});

    std.log.info("\n", .{});
    const answers = try utils.openFileReaderAlloc(allocator, args.pos(1).?);
    std.log.info("Validation:", .{});

    const answers_stats = try answers.file.stat();
    const count: u64 = answers_stats.size / @sizeOf(f64) - 1;
    if (count != inputs.len) {
        std.log.err("expected {d} sums but found {d}", .{ inputs.len, count });
        std.process.exit(1);
    }

    var ref_sum: f64 = 0;
    while (true) {
        const int: u64 = answers.interface.takeInt(u64, .little) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        ref_sum = @bitCast(int);
    }
    std.log.info("Reference sum: {d}", .{ref_sum});
    std.log.info("Difference: {d}", .{@abs(ref_sum - sum)});
}

test {
    _ = parser;
}
