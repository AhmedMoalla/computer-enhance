const std = @import("std");
const log = std.log.scoped(.disasm);
const t = @import("tables.zig");
const decoder = @import("decoder.zig");

pub fn disassemble(in: *std.Io.Reader, out: *std.Io.Writer) !void {
    var buffer: [16384]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    try print(out, "bits 16\n", .{});

    const encodings1 = decoder.generateEncodings1(allocator);
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
