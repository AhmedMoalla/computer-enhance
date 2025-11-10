const std = @import("std");
const log = std.log.scoped(.disasm);
const decoder = @import("decoder.zig");

pub fn disassemble(in: *std.Io.Reader, out: *std.Io.Writer) !void {
    try print(out, "bits 16\n", .{});
    while (true) {
        const instr = decoder.decode(in) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        try print(out, "{s} {f}, {f}\n", .{ @tagName(instr.op), instr.dst, instr.src });
    }
    try out.flush();
}

fn print(out: *std.Io.Writer, comptime fmt: []const u8, args: anytype) !void {
    log.debug(fmt, args);
    try out.print(fmt, args);
}
