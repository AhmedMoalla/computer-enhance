const std = @import("std");
const config = @import("config");
const utils = @import("utils");
const timer = @import("timer.zig");

const log = std.log.scoped(.profiler);

const Profiler = @This();

const ProfilerZone = struct {
    label: []const u8,
    start_tsc: u64,
    end_tsc: u64 = undefined,
    duration: u64 = 0,
    children_time: u64 = 0,
    hit_count: u64 = 0,
    nbytes: u64 = 0,
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
    }

    pub fn addNBytes(self: ProfilerBlock, nbytes: u64) void {
        var zone = global.zones.getPtr(self.label).?;
        zone.nbytes += nbytes;
    }
};

pub var default_zone_count: usize = 64;

const global_parent_label = "Global";

var global = Profiler{};
var parent_label: []const u8 = global_parent_label;

start_tsc: u64 = undefined,
end_tsc: u64 = undefined,
zones: std.StringArrayHashMap(ProfilerZone) = undefined,

pub fn begin(allocator: std.mem.Allocator) void {
    global.zones = std.StringArrayHashMap(ProfilerZone).init(allocator);
    global.zones.ensureTotalCapacity(default_zone_count) catch unreachable;
    global.zones.put(global_parent_label, .{
        .label = global_parent_label,
        .start_tsc = 0,
    }) catch unreachable;
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
        var it = global.zones.iterator();
        while (it.next()) |zone| {
            if (std.mem.eql(u8, global_parent_label, zone.value_ptr.label)) continue;
            printZone(zone.value_ptr.*, total_cpu_elapsed);
        }
    }
}

pub fn timeBlock(label: []const u8) ProfilerBlock {
    return timeBlockBandwidth(label, 0);
}

pub fn timeBlockBandwidth(label: []const u8, nbytes: usize) ProfilerBlock {
    if (!config.enable_profiling) return .{ .label = label, .start_tsc = 0 };
    const start_tsc = timer.readCPUtimer();

    const result = global.zones.getOrPut(label) catch unreachable;
    if (!result.found_existing) {
        result.value_ptr.* = .{
            .label = label,
            .start_tsc = start_tsc,
        };
    }
    result.value_ptr.nbytes += nbytes;

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

    const has_children = zone.children_time > 0 and percent_inclusive != percent_exclusive;
    const percent = if (has_children) percent_exclusive else percent_inclusive;
    const time = if (has_children) time_exclusive else time_inclusive;
    const duration = if (has_children) duration_exclusive else duration_inclusive;

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    writer.print("  [{d:>5.2}%] {s:<15}[{d}] {D:>9.3} ({d} cycles)", .{
        percent,
        zone.label,
        zone.hit_count,
        time,
        duration,
    }) catch unreachable;

    if (has_children) {
        writer.print(" [{d:>5.2}% w/children]", .{percent_inclusive}) catch unreachable;
    }

    if (zone.nbytes > 0) {
        writer.print(" {B:.2} at {d:.2}GB/s", .{ zone.nbytes, @as(f64, @floatFromInt(zone.nbytes)) / @as(f64, @floatFromInt(time)) }) catch unreachable;
    }

    writer.flush() catch unreachable;
    log.info("{s}", .{writer.buffered()});
}

fn calcTimeAndPercent(duration: u64, total_cpu_elapsed: u64) struct { u64, f64 } {
    const fcpu_elapsed: f64 = @floatFromInt(duration);
    const fcpu_freq: f64 = @floatFromInt(timer.estimateCPUtimerFreq().freq);
    const fns_per_s: f64 = @floatFromInt(std.time.ns_per_s);
    const zone_time: u64 = @intFromFloat(fcpu_elapsed / (fcpu_freq / fns_per_s));
    const percent: f64 = @as(f64, 100.0) * fcpu_elapsed / @as(f64, @floatFromInt(total_cpu_elapsed));
    return .{ zone_time, percent };
}
