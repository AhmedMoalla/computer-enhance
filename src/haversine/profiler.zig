const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const timer = @import("timer.zig");

const log = std.log.scoped(.profiler);
const StringSet = std.StringArrayHashMap(void);

const Profiler = @This();

const ProfilerZone = struct {
    label: []const u8,
    start_tsc: u64,
    end_tsc: u64 = undefined,
    duration: u64 = 0,
    children_time: u64 = 0,
    hit_count: u64 = 0,
};

pub const ProfilerBlock = struct {
    label: []const u8,
    start_tsc: u64,
    previous_parent: []const u8 = undefined,

    pub fn endTimeBlock(self: ProfilerBlock) void {
        if (!config.enable_profiling) return;
        const end_tsc = timer.readCPUtimer();
        var zone = global.zones.getPtr(self.label).?;
        const block_duration = end_tsc - self.start_tsc;
        zone.duration += block_duration;
        zone.hit_count += 1;
        zone.end_tsc = end_tsc;

        parent_label = self.previous_parent;
        var parent = global.zones.getPtr(parent_label).?;
        parent.children_time += block_duration;
        var children = global.tree.getPtr(parent_label).?;
        children.put(self.label, {}) catch unreachable;
    }
};

pub var default_zone_count: usize = 64;

const global_parent_label = "Global";

var global = Profiler{};
var parent_label: []const u8 = global_parent_label;

allocator: std.mem.Allocator = undefined,

start_tsc: u64 = undefined,
end_tsc: u64 = undefined,
zones: std.StringArrayHashMap(ProfilerZone) = undefined,
tree: std.StringArrayHashMap(StringSet) = undefined, // Used for final hierarchical display

pub fn begin(allocator: std.mem.Allocator) void {
    global.allocator = allocator;
    global.zones = std.StringArrayHashMap(ProfilerZone).init(allocator);
    global.zones.ensureTotalCapacity(default_zone_count) catch unreachable;
    global.zones.put(global_parent_label, .{
        .label = global_parent_label,
        .start_tsc = 0,
    }) catch unreachable;
    global.tree = std.StringArrayHashMap(StringSet).init(allocator);
    global.tree.ensureTotalCapacity(default_zone_count) catch unreachable;
    var children = StringSet.init(allocator);
    children.ensureTotalCapacity(default_zone_count / 2) catch unreachable;
    global.tree.put(global_parent_label, children) catch unreachable;
    global.start_tsc = timer.readCPUtimer();
}

pub fn endAndPrint() void {
    global.end_tsc = timer.readCPUtimer();

    const total_cpu_elapsed: u64 = global.end_tsc - global.start_tsc;
    const total_time, _ = calcTimeAndPercent(global.end_tsc - global.start_tsc, total_cpu_elapsed);

    log.info("Total time: {D} ({d} cycles @ {f})", .{
        total_time,
        total_cpu_elapsed,
        timer.estimateCPUtimerFreq(),
    });

    if (config.enable_profiling) {
        var it = global.tree.iterator();
        while (it.next()) |entry| {
            std.debug.print("{s} -> ", .{entry.key_ptr.*});
            var children_it = entry.value_ptr.*.iterator();
            while (children_it.next()) |child| {
                std.debug.print("{s}, ", .{child.key_ptr.*});
            }
            std.debug.print("\n", .{});
        }
        var it2 = global.zones.iterator();
        while (it2.next()) |zone| {
            if (std.mem.eql(u8, global_parent_label, zone.value_ptr.label)) continue;
            printZone(zone.value_ptr.*, total_cpu_elapsed);
        }
    }
}

pub fn timeBlock(label: []const u8) ProfilerBlock {
    if (!config.enable_profiling) return .{ .label = label, .start_tsc = 0 };
    const start_tsc = timer.readCPUtimer();

    const result = global.zones.getOrPut(label) catch unreachable;
    if (!result.found_existing) {
        result.value_ptr.* = .{
            .label = label,
            .start_tsc = start_tsc,
        };
    }

    var children = StringSet.init(global.allocator);
    children.ensureTotalCapacity(default_zone_count / 2) catch unreachable;
    global.tree.put(label, children) catch unreachable;

    defer parent_label = label;

    return .{
        .label = label,
        .start_tsc = start_tsc,
        .previous_parent = parent_label,
    };
}

fn printZone(zone: ProfilerZone, total_cpu_elapsed: u64) void {
    const duration_inclusive = zone.end_tsc - zone.start_tsc;
    const duration_exclusive = zone.duration - zone.children_time;
    const time_inclusive, const percent_inclusive = calcTimeAndPercent(duration_inclusive, total_cpu_elapsed);
    const time_exclusive, const percent_exclusive = calcTimeAndPercent(duration_exclusive, total_cpu_elapsed);

    if (zone.children_time > 0 and percent_inclusive != percent_exclusive) {
        log.info("  [{d:>5.2}%] {s:<15}[{d}] {D:>9.3} ({d} cycles) [{d:>5.2}% w/children]", .{
            percent_exclusive,
            zone.label,
            zone.hit_count,
            time_exclusive,
            zone.duration - zone.children_time,
            percent_inclusive,
        });
    } else {
        log.info("  [{d:>5.2}%] {s:<15}[{d}] {D:>9.3} ({d} cycles)", .{
            percent_inclusive,
            zone.label,
            zone.hit_count,
            time_inclusive,
            zone.end_tsc - zone.start_tsc,
        });
    }
}

fn calcTimeAndPercent(duration: u64, total_cpu_elapsed: u64) struct { u64, f64 } {
    const fcpu_elapsed: f64 = @floatFromInt(duration);
    const fcpu_freq: f64 = @floatFromInt(timer.estimateCPUtimerFreq().freq);
    const fns_per_s: f64 = @floatFromInt(std.time.ns_per_s);
    const zone_time: u64 = @intFromFloat(fcpu_elapsed / (fcpu_freq / fns_per_s));
    const percent: f64 = @as(f64, 100.0) * fcpu_elapsed / @as(f64, @floatFromInt(total_cpu_elapsed));
    return .{ zone_time, percent };
}
