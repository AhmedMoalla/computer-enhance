const std = @import("std");
const utils = @import("utils");
const timer = @import("timer.zig");

const log = std.log.scoped(.profiler);

const Profiler = @This();

const ProfilerBlock = struct {
    label: []const u8,
    start_tsc: u64,
    end_tsc: u64 = undefined,
    hit_count: u64 = 1,
    recursive_depth: u64 = 0,

    has_parent: bool = false,
    children: std.ArrayList([]const u8),
};

var global = Profiler{};

initialized: bool = false,
allocator: std.mem.Allocator = undefined,
cpu_freq: timer.CPUFreq = undefined,

start_tsc: u64 = undefined,
end_tsc: u64 = undefined,
blocks: std.StringArrayHashMap(ProfilerBlock) = undefined,
stack: std.ArrayList([]const u8) = undefined,

pub fn begin(allocator: std.mem.Allocator) void {
    global.initialized = true;
    global.allocator = allocator;
    global.cpu_freq = timer.estimateCPUtimerFreq();
    global.blocks = std.StringArrayHashMap(ProfilerBlock).init(allocator);
    global.stack = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;

    global.start_tsc = timer.readCPUtimer();
}

pub fn endAndPrint() void {
    const end = timer.readCPUtimer();
    checkInitialized();
    global.end_tsc = end;

    const total_cpu_elapsed: u64 = global.end_tsc - global.start_tsc;
    const total_time: u64 = (total_cpu_elapsed * std.time.ns_per_s) / global.cpu_freq.freq;

    log.info("Total time: {D} ({d} cycles @ {f})", .{
        total_time,
        total_cpu_elapsed,
        global.cpu_freq,
    });

    var it = global.blocks.iterator();
    while (it.next()) |block| {
        printBlock(block.value_ptr.*, total_cpu_elapsed);
    }
}

pub fn timeBlock(label: []const u8) void {
    const start = timer.readCPUtimer();
    checkInitialized();

    const result = global.blocks.getOrPut(label) catch unreachable;

    if (!result.found_existing) {
        result.value_ptr.* = ProfilerBlock{
            .label = label,
            .start_tsc = start,

            .children = std.ArrayList([]const u8).initCapacity(global.allocator, 10) catch unreachable,
        };

        const new_block = global.blocks.getPtr(label).?;
        if (global.stack.items.len > 0) {
            const parent_label = global.stack.items[global.stack.items.len - 1];
            const parent = global.blocks.getPtr(parent_label).?;
            parent.*.children.append(global.allocator, new_block.label) catch unreachable;
            new_block.has_parent = true;
        }
        global.stack.append(global.allocator, new_block.label) catch unreachable;
    } else {
        result.value_ptr.recursive_depth += 1;
        result.value_ptr.hit_count += 1;
    }
}

pub fn endTimeBlock(label: []const u8) void {
    const end = timer.readCPUtimer();
    checkInitialized();

    var block = global.blocks.getPtr(label) orelse {
        std.log.err("endTimeBlock(\"{s}\") called without a matching timeBlock(\"{s}\")", .{ label, label });
        std.process.exit(1);
    };

    block.end_tsc = end;
    if (block.recursive_depth == 0) {
        _ = global.stack.pop();
    } else {
        block.recursive_depth -= 1;
    }
}

fn checkInitialized() void {
    if (!global.initialized) {
        std.log.err("begin() should be called before any function", .{});
        std.process.exit(1);
    }
}

fn printBlock(block: ProfilerBlock, total_cpu_elapsed: u64) void {
    if (block.has_parent) return;
    _ = printBlockRec(block, total_cpu_elapsed, 0);
}

fn printBlockRec(block: ProfilerBlock, total_cpu_elapsed: u64, depth_counter: u64) u64 {
    const padding = utils.repeatCharAlloc(global.allocator, "    ", depth_counter);

    const cpu_elapsed: u64 = block.end_tsc - block.start_tsc;
    const block_time: u64 = (cpu_elapsed * std.time.ns_per_s) / global.cpu_freq.freq;

    const percent: f64 = @as(f64, 100.0) * @as(f64, @floatFromInt(cpu_elapsed)) / @as(f64, @floatFromInt(total_cpu_elapsed));
    log.info("  {s}[{d:>6.2}%] {s:<15}[{d}] {D:>9.3} ({d} cycles)", .{
        padding,
        percent,
        block.label,
        block.hit_count,
        block_time,
        cpu_elapsed,
    });

    var children_cpu: u64 = 0;
    for (block.children.items) |child_label| {
        var child = global.blocks.get(child_label).?;
        child.has_parent = false;
        children_cpu += printBlockRec(child, total_cpu_elapsed, depth_counter + 1);
    }

    if (children_cpu > 0) {
        _ = printBlockRec(ProfilerBlock{
            .label = "Remaining",
            .start_tsc = 0,
            .end_tsc = cpu_elapsed - children_cpu,
            .children = std.ArrayList([]const u8).empty,
        }, total_cpu_elapsed, depth_counter + 1);
    }

    return cpu_elapsed;
}
