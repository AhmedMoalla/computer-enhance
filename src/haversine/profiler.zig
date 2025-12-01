const std = @import("std");
const timer = @import("timer.zig");

const Profiler = @This();

var global = Profiler{};

initialized: bool = false,
allocator: std.mem.Allocator = undefined,

start_ts: u64 = undefined,
blocks: std.StringArrayHashMap(ProfilerBlock) = undefined,
current_block_label: []const u8 = global_block_label,

const global_block_label = "Global";

const ProfilerBlock = struct {
    label: []const u8,
    start_ts: u64,
    duration: u64 = undefined,
    children_time: u64 = 0,
    parent_label: []const u8 = undefined,
    hits: u64 = 1,
};

pub fn begin(allocator: std.mem.Allocator) void {
    global.allocator = allocator;
    global.start_ts = timer.readCPUtimer();
    global.blocks = std.StringArrayHashMap(ProfilerBlock).init(allocator);
    global.blocks.put(global_block_label, ProfilerBlock{ .start_ts = 0, .label = global_block_label }) catch unreachable;
    global.initialized = true;
}

pub fn endAndPrint() void {
    checkInitialized();

    std.debug.assert(global.blocks.orderedRemove(global_block_label));

    const end = timer.readCPUtimer() - global.start_ts;
    const cpu_freq = timer.estimateCPUtimerFreq();
    std.log.info("Total time: {d}ms (CPU freq {d})", .{ 1000 * end / cpu_freq, cpu_freq });

    var it = global.blocks.iterator();
    while (it.next()) |block| {
        printTimeElapsed(block.key_ptr.*, block.value_ptr.*, end);
    }

    global.blocks.deinit();
}

pub fn timeBlock(label: []const u8) void {
    checkInitialized();
    const result = global.blocks.getOrPut(label) catch unreachable;

    if (result.found_existing) {
        result.value_ptr.hits += 1;
    } else {
        result.value_ptr.* = ProfilerBlock{
            .label = label,
            .start_ts = timer.readCPUtimer(),
        };
    }

    result.value_ptr.parent_label = global.current_block_label;
    global.current_block_label = result.value_ptr.label;
}

pub fn endTimeBlock(label: []const u8) void {
    checkInitialized();
    const block = global.blocks.getPtr(label) orelse {
        std.log.err("endTimeBlock(\"{s}\") called without a matching timeBlock(\"{s}\")", .{ label, label });
        std.process.exit(1);
    };

    block.*.duration = timer.readCPUtimer() - block.start_ts;

    const parent = global.blocks.getPtr(block.parent_label) orelse unreachable;
    parent.children_time += block.duration;
    global.current_block_label = block.parent_label;
}

fn printTimeElapsed(label: []const u8, block: ProfilerBlock, total_elapsed: u64) void {
    const duration = block.duration;
    const elapsed: f64 = @floatFromInt(duration);
    const ftotal_elapsed: f64 = @floatFromInt(total_elapsed);
    const percent: f64 = @as(f64, 100.0) * (elapsed / ftotal_elapsed);

    const indent = if (std.mem.eql(u8, global_block_label, block.parent_label)) "  " else "    ";

    if (block.children_time > 0) {
        const duration_without_children: f64 = @floatFromInt(duration - block.children_time);
        const percent_without_children: f64 = @as(f64, 100.0) * (duration_without_children / ftotal_elapsed);
        std.log.info("{s}{s}[{d}]: {D} ({d:.2}%, {d:.2}% w/children)", .{ indent, label, block.hits, duration, percent_without_children, percent });
    } else {
        std.log.info("{s}{s}[{d}]: {D} ({d:.2}%)", .{ indent, label, block.hits, duration, percent });
    }
}

fn checkInitialized() void {
    if (!global.initialized) {
        std.log.err("begin() should be called before any function", .{});
        std.process.exit(1);
    }
}
