const std = @import("std");
const utils = @import("utils");
const decoder = @import("decoder.zig");
const t = @import("tables.zig");

// Results:
// [    10] without_map n=    10 mean=  801.37us max=   843.3us min=   786.7us
// [    10] with_map    n=    10 mean=   746.5us max=   775.1us min=   734.7us
//
// [   100] without_map n=   100 mean= 847.655us max=   1.286ms min=   781.3us
// [   100] with_map    n=   100 mean= 773.381us max=   1.042ms min=   729.3us
//
// [  1000] without_map n=  1000 mean=  830.48us max=   2.139ms min=   777.3us
// [  1000] with_map    n=  1000 mean= 776.185us max=   1.465ms min=   724.1us
//
// [ 10000] without_map n= 10000 mean= 846.274us max=   2.153ms min=   776.2us
// [ 10000] with_map    n= 10000 mean= 771.117us max=   1.916ms min=     723us
//
// [100000] without_map n=100000 mean= 826.436us max=   2.485ms min=     775us
// [100000] with_map    n=100000 mean= 772.995us max=   2.552ms min=   721.1us

test "without_map" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const reader = try utils.openFileReaderAlloc(allocator, "out");
    const buffer = try reader.interface.readAlloc(allocator, 893);

    var in: std.io.Reader = .fixed(buffer);

    for ([_]u32{ 10, 100, 1000, 10000, 100000 }) |iterations| {
        var n: usize = 0;
        var global_time: u64 = 0;
        var max: u64 = 0;
        var min: u64 = std.math.maxInt(u64);
        for (0..iterations) |_| {
            var timer = try std.time.Timer.start();
            const now = timer.read();
            while (true) {
                _ = decoder.decode(&in) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                };
            }
            const diff = timer.read() - now;
            if (diff > max) {
                max = diff;
            }
            if (diff < min) {
                min = diff;
            }
            global_time += diff;
            n += 1;
            in.seek = 0;
        }
        std.testing.log_level = .debug;
        std.debug.print("[{d:>5}] without_map n={d:>6} mean={D:>10} max={D:>10} min={D:>10}\n", .{ iterations, n, global_time / n, max, min });
        std.testing.log_level = .warn;
    }
}

test "with_map" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const reader = try utils.openFileReaderAlloc(allocator, "out");
    const buffer = try reader.interface.readAlloc(allocator, 893);

    var in: std.io.Reader = .fixed(buffer);

    const encoding1 = generateEncodings1(allocator);

    for ([_]u32{ 10, 100, 1000, 10000, 100000 }) |iterations| {
        var n: usize = 0;
        var global_time: u64 = 0;
        var max: u64 = 0;
        var min: u64 = std.math.maxInt(u64);
        for (0..iterations) |_| {
            var timer = try std.time.Timer.start();
            const now = timer.read();
            while (true) {
                _ = decoder.decode1(&in, encoding1) catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                };
            }
            const diff = timer.read() - now;
            if (diff > max) {
                max = diff;
            }
            if (diff < min) {
                min = diff;
            }
            global_time += diff;
            n += 1;
            in.seek = 0;
        }
        std.testing.log_level = .debug;
        std.debug.print("[{d:>5}] with_map    n={d:>6} mean={D:>10} max={D:>10} min={D:>10}\n", .{ iterations, n, global_time / n, max, min });
        std.testing.log_level = .warn;
    }
}

pub fn generateEncodings1(allocator: std.mem.Allocator) std.AutoHashMap(u8, t.Encoding) {
    var ambiguous = std.AutoArrayHashMap(u8, bool).init(allocator);
    var map = std.AutoHashMap(u8, t.Encoding).init(allocator);
    for (t.encodings) |encoding| {
        var valid = false;
        for (encoding.layout) |component| {
            if (component.type == .bits and component.size == 8) {
                valid = true;
            }
            if (component.type == .bits and component.size < 8) {
                valid = false;
            }

            if (valid) {
                const present = map.fetchPut(component.value, encoding) catch unreachable != null;
                if (present) {
                    ambiguous.put(component.value, true) catch unreachable;
                }
                break;
            }
        }
    }

    for (ambiguous.keys()) |key| {
        _ = map.remove(key);
    }

    return map;
}
