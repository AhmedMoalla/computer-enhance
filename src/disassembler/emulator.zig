const std = @import("std");
const log = std.log.scoped(.disasm);
const t = @import("tables.zig");
const decoder = @import("decoder.zig");
const disassembler = @import("disassembler.zig");
const State = @import("State.zig");

pub fn execute(in: *std.Io.Reader, out: *std.Io.Writer) !void {
    var state = State{};
    var buffer: [16384]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const encodings1 = disassembler.generateEncodings1(allocator);
    while (true) {
        const instr = decoder.decode(in, encodings1) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        try out.print("{f} ; ", .{instr});

        var diff = State.Diff.init(state);
        switch (instr.op) {
            .mov => state.write(instr.lhs, state.read(instr.rhs)),
            else => std.debug.print("{t} not implemented yet\n", .{instr.op}),
        }
        diff.compare(state);
        try out.print("{f}\n", .{diff});
    }

    try out.print("{f}", .{state});

    try out.flush();
}
