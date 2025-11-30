const std = @import("std");
const timer = @import("timer.zig");

const Profiler = @This();

var global = Profiler{};

initialized: bool = false,
allocator: std.mem.Allocator = undefined,

start_ts: u64 = undefined,
blocks: std.StringArrayHashMap(ProfilerBlock) = undefined,

const ProfilerBlock = struct {
    start_ts: u64,
    duration: u64 = undefined,
    hits: u64 = 1,
};

pub fn begin(allocator: std.mem.Allocator) void {
    global.allocator = allocator;
    global.start_ts = timer.readCPUtimer();
    global.blocks = std.StringArrayHashMap(ProfilerBlock).init(allocator);
    global.initialized = true;
}

pub fn endAndPrint() void {
    checkInitialized();
    const end = timer.readCPUtimer() - global.start_ts;
    const cpu_freq = timer.estimateCPUtimerFreq();
    std.log.info("Total time: {d}ms (CPU freq {d})", .{ 1000 * end / cpu_freq, cpu_freq });

    var it = global.blocks.iterator();
    while (it.next()) |block| {
        printTimeElapsed(block.key_ptr.*, block.value_ptr.*, end);
    }

    global.blocks.deinit();
}

pub fn timeBlock(name: []const u8) void {
    checkInitialized();
    const result = global.blocks.getOrPut(name) catch {
        std.log.err("Out Of Memory", .{});
        std.process.exit(1);
    };

    if (result.found_existing) {
        result.value_ptr.hits += 1;
    } else {
        result.value_ptr.* = ProfilerBlock{
            .start_ts = timer.readCPUtimer(),
        };
    }
}

pub fn endTimeBlock(name: []const u8) void {
    checkInitialized();
    const block = global.blocks.getPtr(name) orelse {
        std.log.err("endTimeBlock(\"{s}\") called without a matching timeBlock(\"{s}\")", .{ name, name });
        std.process.exit(1);
    };

    block.*.duration = timer.readCPUtimer() - block.start_ts;
}

fn printTimeElapsed(label: []const u8, block: ProfilerBlock, total_elapsed: u64) void {
    const duration = block.duration;
    const elapsed: f64 = @floatFromInt(duration);
    const ftotal_elapsed: f64 = @floatFromInt(total_elapsed);
    const percent: f64 = @as(f64, 100.0) * (elapsed / ftotal_elapsed);
    std.log.info("  {s}[{d}]: {D} ({d:.2}%)", .{ label, block.hits, duration, percent });
}

fn checkInitialized() void {
    if (!global.initialized) {
        std.log.err("begin() should be called before any function", .{});
        std.process.exit(1);
    }
}
