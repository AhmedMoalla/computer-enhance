const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const timer = @import("timer.zig");

const log = std.log.scoped(.profiler);

const Profiler = @This();

const ProfilerZone = struct {
    label: []const u8,
    duration: u64 = 0,
    hit_count: u64 = 0,
    parent: ?*ProfilerZone = null,

    children: std.ArrayList([]const u8),

    pub fn id(self: ProfilerZone) []const u8 {
        const parent_label = if (self.parent) |parent| parent.label else null;
        return zoneId(parent_label, self.label);
    }

    pub fn childId(self: ProfilerZone, child_label: []const u8) []const u8 {
        return zoneId(self.label, child_label);
    }
};

const ProfilerBlock = struct {
    label: []const u8,
    start_tsc: u64,
};

var global = Profiler{};

initialized: bool = false,
allocator: std.mem.Allocator = undefined,

start_tsc: u64 = undefined,
end_tsc: u64 = undefined,
zones: std.StringArrayHashMap(ProfilerZone) = undefined,
blocks: std.StringArrayHashMap(ProfilerBlock) = undefined,
stack: std.ArrayList([]const u8) = undefined,

pub fn begin(allocator: std.mem.Allocator) void {
    if (!config.enable_profiling) {
        global.initialized = true;
        global.start_tsc = timer.readCPUtimer();
        return;
    }

    global.initialized = true;
    global.allocator = allocator;
    global.zones = std.StringArrayHashMap(ProfilerZone).init(allocator);
    global.blocks = std.StringArrayHashMap(ProfilerBlock).init(allocator);
    global.stack = std.ArrayList([]const u8).initCapacity(allocator, 20) catch unreachable;

    global.start_tsc = timer.readCPUtimer();
}

pub fn endAndPrint() void {
    const end = timer.readCPUtimer();
    checkInitialized();
    global.end_tsc = end;

    const total_cpu_elapsed: u64 = global.end_tsc - global.start_tsc;
    const ftotal_cpu_elapsed: f64 = @floatFromInt(total_cpu_elapsed);
    const cpu_freq = timer.estimateCPUtimerFreq();
    const fcpu_freq: f64 = @floatFromInt(cpu_freq.freq);
    const fns_per_s: f64 = @floatFromInt(std.time.ns_per_s);
    const total_time: u64 = @intFromFloat(ftotal_cpu_elapsed / (fcpu_freq / fns_per_s));

    log.info("Total time: {D} ({d} cycles @ {f})", .{
        total_time,
        total_cpu_elapsed,
        cpu_freq,
    });

    if (config.enable_profiling) {
        var it = global.zones.iterator();
        while (it.next()) |zone| {
            printZone(zone.value_ptr.*, total_cpu_elapsed);
        }
    }
}

pub fn timeBlock(label: []const u8) void {
    if (!config.enable_profiling) return;

    const start = timer.readCPUtimer();
    checkInitialized();

    var zone_id = label;
    if (global.stack.items.len > 0) {
        const parent_id = global.stack.items[global.stack.items.len - 1];
        const parent_zone = global.zones.getPtr(parent_id).?;
        zone_id = parent_zone.childId(label);
    }

    const result = global.zones.getOrPut(zone_id) catch unreachable;
    if (!result.found_existing) {
        result.value_ptr.* = .{
            .label = label,
            .children = std.ArrayList([]const u8).initCapacity(global.allocator, 20) catch unreachable,
        };
    }

    global.blocks.put(zone_id, .{
        .label = label,
        .start_tsc = start,
    }) catch unreachable;

    if (global.stack.items.len > 0 and !result.found_existing) {
        const parent_id = global.stack.items[global.stack.items.len - 1];
        const parent = global.zones.getPtr(parent_id).?;
        parent.children.append(global.allocator, zone_id) catch unreachable;
        const child_zone = result.value_ptr;
        child_zone.parent = parent;
    }

    global.stack.append(global.allocator, zone_id) catch unreachable;
}

pub fn endTimeBlock(label: []const u8) void {
    if (!config.enable_profiling) return;

    const end = timer.readCPUtimer();
    checkInitialized();

    var zone_id = label;
    if (global.stack.items.len > 1) {
        const parent_id = global.stack.items[global.stack.items.len - 2];
        const parent_zone = global.zones.getPtr(parent_id).?;
        zone_id = parent_zone.childId(label);
    }

    const block = global.blocks.get(zone_id) orelse {
        std.log.err("endTimeBlock(\"{s}\") called without a matching timeBlock(\"{s}\")", .{ label, label });
        std.process.exit(1);
    };

    const zone = global.zones.getPtr(zone_id) orelse {
        std.log.err("endTimeBlock(\"{s}\") called without a matching timeBlock(\"{s}\")", .{ label, label });
        std.process.exit(1);
    };

    zone.duration += end - block.start_tsc;
    zone.hit_count += 1;

    _ = global.stack.pop();
}

fn checkInitialized() void {
    if (!global.initialized) {
        std.log.err("begin() should be called before any function", .{});
        std.process.exit(1);
    }
}

fn printZone(zone: ProfilerZone, total_cpu_elapsed: u64) void {
    if (zone.parent != null) return;
    _ = printZoneRec(zone, total_cpu_elapsed, 0);
}

fn printZoneRec(z: ProfilerZone, total_cpu_elapsed: u64, depth_counter: u64) u64 {
    var zone = z;
    const padding = utils.repeatCharAlloc(global.allocator, "    ", depth_counter);

    const fcpu_elapsed: f64 = @floatFromInt(zone.duration);
    const fcpu_freq: f64 = @floatFromInt(timer.estimateCPUtimerFreq().freq);
    const fns_per_s: f64 = @floatFromInt(std.time.ns_per_s);
    const zone_time: u64 = @intFromFloat(fcpu_elapsed / (fcpu_freq / fns_per_s));

    for (zone.children.items) |child_label| {
        const child = global.zones.get(child_label).?;
        if (std.mem.eql(u8, zone.label, child.label)) {
            zone.hit_count += child.hit_count;
        }
    }

    const percent: f64 = @as(f64, 100.0) * fcpu_elapsed / @as(f64, @floatFromInt(total_cpu_elapsed));
    log.info("  {s}[{d:>6.2}%] {s:<15}[{d}] {D:>9.3} ({d} cycles)", .{
        padding,
        percent,
        zone.label,
        zone.hit_count,
        zone_time,
        zone.duration,
    });

    var children_cpu: u64 = 0;
    for (zone.children.items) |child_label| {
        var child = global.zones.get(child_label).?;
        if (std.mem.eql(u8, zone.label, child.label)) continue;
        child.parent = @constCast(&zone);
        children_cpu += printZoneRec(child, total_cpu_elapsed, depth_counter + 1);
    }

    if (children_cpu > 0) {
        _ = printZoneRec(ProfilerZone{
            .label = "Remaining",
            .hit_count = 1,
            .duration = zone.duration - children_cpu,
            .children = std.ArrayList([]const u8).empty,
        }, total_cpu_elapsed, depth_counter + 1);
    }

    return zone.duration;
}

inline fn zoneId(parent_label: ?[]const u8, label: []const u8) []const u8 {
    if (parent_label) |parent| {
        return std.mem.concat(global.allocator, u8, &[_][]const u8{ parent, ".", label }) catch unreachable;
    } else {
        return std.mem.concat(global.allocator, u8, &[_][]const u8{label}) catch unreachable;
    }
}
