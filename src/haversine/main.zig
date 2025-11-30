const std = @import("std");
const utils = @import("utils");
const generator = @import("generator.zig");
const parser = @import("parser.zig");
const haversine = @import("haversine.zig");
const timer = @import("timer.zig");

var prof_begin: u64 = 0;
var prof_parse: u64 = 0;
var prof_sum: u64 = 0;
var prof_validation: u64 = 0;
var prof_output: u64 = 0;
var prof_end: u64 = 0;

pub fn main() !void {
    prof_begin = timer.readCPUtimer();

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

    prof_parse = timer.readCPUtimer();
    const inputs = try parser.parseHaversineInputs(allocator, inputs_file.interface, 10000);

    prof_sum = timer.readCPUtimer();
    var sum: f64 = 0;
    const sum_coef = 1.0 / @as(f64, @floatFromInt(inputs.len));
    for (inputs) |input| {
        sum += sum_coef * haversine.reference(input.x0, input.y0, input.x1, input.y1);
    }

    prof_validation = timer.readCPUtimer();
    const answers = try utils.openFileReaderAlloc(allocator, args.pos(1).?);

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

    prof_output = timer.readCPUtimer();
    const stats = try inputs_file.file.stat();
    std.log.info("Input size: {d}", .{stats.size});
    std.log.info("Pair count: {d}", .{inputs.len});
    std.log.info("Havesine sum: {d}\n", .{sum});
    std.log.info("Validation:", .{});
    std.log.info("Reference sum: {d}", .{ref_sum});
    std.log.info("Difference: {d}\n", .{@abs(ref_sum - sum)});

    prof_end = timer.readCPUtimer();

    const total_cpu_elapsed = prof_end - prof_begin;
    const cpu_freq = timer.estimateCPUtimerFreq();
    std.log.info("Total time: {d}ms (CPU freq {d})", .{ 1000 * total_cpu_elapsed / cpu_freq, cpu_freq });

    printTimeElapsed("Startup", total_cpu_elapsed, prof_begin, prof_parse);
    printTimeElapsed("Parse", total_cpu_elapsed, prof_parse, prof_sum);
    printTimeElapsed("Sum", total_cpu_elapsed, prof_sum, prof_validation);
    printTimeElapsed("Validation", total_cpu_elapsed, prof_validation, prof_output);
    printTimeElapsed("Output", total_cpu_elapsed, prof_output, prof_end);
}

fn printTimeElapsed(label: []const u8, total_elapsed: u64, begin: u64, end: u64) void {
    const elapsed: f64 = @floatFromInt(end - begin);
    const ftotal_elapsed: f64 = @floatFromInt(total_elapsed);
    const percent: f64 = @as(f64, 100.0) * (elapsed / ftotal_elapsed);
    std.log.info("  {s}: {d} ({d:.2}%)", .{ label, elapsed, percent });
}

test {
    _ = parser;
}
