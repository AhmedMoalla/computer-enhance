const std = @import("std");
const builtin = @import("builtin");

pub fn getOStimerFreq() u64 {
    return switch (builtin.os.tag) {
        .windows => std.os.windows.QueryPerformanceFrequency(),
        .linux, .macos => 1_000_000,
        inline else => {
            std.log.err("unsupported os: {t}", .{builtin.os.tag});
            std.process.exit(1);
        },
    };
}

pub fn readOStimer() u64 {
    return switch (builtin.os.tag) {
        .windows => std.os.windows.QueryPerformanceCounter(),
        .linux, .macos => {
            const value: std.posix.timeval = undefined;
            std.posix.gettimeofday(&value, null);
            return getOStimerFreq() * value.sec + value.usec;
        },
        inline else => {
            std.log.err("unsupported os: {t}", .{builtin.os.tag});
            std.process.exit(1);
        },
    };
}

pub fn readCPUtimer() u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;

    asm volatile ("rdtsc"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
    );

    return (@as(u64, high) << 32) | @as(u64, low);
}

pub fn estimateCPUtimerFreq() CPUFreq {
    const ms_to_wait: u64 = 100;
    const os_freq: u64 = getOStimerFreq();

    const cpu_start = readCPUtimer();
    const os_start = readOStimer();
    const os_wait_time: u64 = os_freq * ms_to_wait / 1000;
    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;

    while (os_elapsed < os_wait_time) {
        os_end = readOStimer();
        os_elapsed = os_end - os_start;
    }

    const cpu_end: u64 = readCPUtimer();
    const cpu_elapsed: u64 = cpu_end - cpu_start;

    var cpu_freq: u64 = 0;
    if (os_elapsed > 0) {
        cpu_freq = os_freq * cpu_elapsed / os_elapsed;
    }
    return .{ .freq = cpu_freq };
}

pub const CPUFreq = struct {
    freq: u64,

    // adapted from std.Io.Writer.printByteSize
    pub fn format(self: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        const value = self.freq;
        if (value == 0) return w.alignBufferOptions("0Hz", .{});
        // The worst case in terms of space needed is 32 bytes + 3 for the suffix.
        var buf: [std.fmt.float.min_buffer_size + 3]u8 = undefined;

        const mags_si = " kMGTPEZY";

        const log2 = std.math.log2(value);
        const magnitude = @min(log2 / comptime std.math.log2(1000), mags_si.len - 1);
        const new_value = std.math.lossyCast(f64, value) / std.math.pow(f64, std.math.lossyCast(f64, 1000), std.math.lossyCast(f64, magnitude));
        const suffix = mags_si[magnitude];

        const s = switch (magnitude) {
            0 => buf[0..std.fmt.printInt(&buf, value, 10, .lower, .{})],
            else => std.fmt.float.render(&buf, new_value, .{ .mode = .decimal, .precision = 2 }) catch |err| switch (err) {
                error.BufferTooSmall => unreachable,
            },
        };

        var i: usize = s.len;
        if (suffix == ' ') {
            buf[i] = 'H';
            buf[i + 1] = 'z';
            i += 2;
        } else {
            buf[i..][0..3].* = [_]u8{ suffix, 'H', 'z' };
            i += 3;
        }

        return w.alignBufferOptions(buf[0..i], .{});
    }
};

test "listing_0071_os_timer_main.cpp port" {
    std.testing.log_level = .debug;
    defer std.testing.log_level = .warn;

    const os_freq = getOStimerFreq();
    std.debug.print("    OS Freq: {d}\n", .{os_freq});

    const os_start = readOStimer();
    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;
    while (os_elapsed < os_freq) {
        os_end = readOStimer();
        os_elapsed = os_end - os_start;
    }

    const fos_elapsed: f64 = @floatFromInt(os_elapsed);
    const fos_freq: f64 = @floatFromInt(os_freq);
    std.debug.print("   OS Timer: {d} -> {d} = {d} elapsed\n", .{ os_start, os_end, os_elapsed });
    std.debug.print(" OS Seconds: {d}\n", .{fos_elapsed / fos_freq});
}

test "listing_0072_cpu_time_main.cpp port" {
    std.testing.log_level = .debug;
    defer std.testing.log_level = .warn;

    const os_freq = getOStimerFreq();
    std.debug.print("    OS Freq: {d}\n", .{os_freq});

    const cpu_start = readCPUtimer();
    const os_start = readOStimer();
    var os_end: u64 = 0;
    var os_elapsed: u64 = 0;
    while (os_elapsed < os_freq) {
        os_end = readOStimer();
        os_elapsed = os_end - os_start;
    }

    const cpu_end = readCPUtimer();
    const cpu_elapsed = cpu_end - cpu_start;

    const fos_elapsed: f64 = @floatFromInt(os_elapsed);
    const fos_freq: f64 = @floatFromInt(os_freq);
    std.debug.print("   OS Timer: {d} -> {d} = {d} elapsed\n", .{ os_start, os_end, os_elapsed });
    std.debug.print(" OS Seconds: {d}\n", .{fos_elapsed / fos_freq});

    std.debug.print("  CPU Timer: {d} -> {d} = {d} elapsed\n", .{ cpu_start, cpu_end, cpu_elapsed });
}
