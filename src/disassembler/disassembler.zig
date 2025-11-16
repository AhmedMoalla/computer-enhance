const std = @import("std");
const log = std.log.scoped(.disasm);
const t = @import("tables.zig");
const decoder = @import("decoder.zig");

pub fn disassemble(in: *std.Io.Reader, out: *std.Io.Writer) !void {
    var buffer: [16384]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    try print(out, "bits 16\n", .{});

    const encodings1 = generateEncodings1(allocator);
    while (true) {
        const instr = decoder.decode(in, encodings1) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        try print(out, "{f}\n", .{instr});
    }
    try out.flush();
}

fn print(out: *std.Io.Writer, comptime fmt: []const u8, args: anytype) !void {
    log.debug(fmt, args);
    try out.print(fmt, args);
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
