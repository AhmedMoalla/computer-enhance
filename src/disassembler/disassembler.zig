const std = @import("std");

const regs: [8][2][]const u8 = [_][2][]const u8{
    [_][]const u8{ "al", "ax" },
    [_][]const u8{ "cl", "cx" },
    [_][]const u8{ "dl", "dx" },
    [_][]const u8{ "bl", "bx" },
    [_][]const u8{ "ah", "sp" },
    [_][]const u8{ "ch", "bp" },
    [_][]const u8{ "dh", "si" },
    [_][]const u8{ "bh", "di" },
};

pub fn disassemble(in: *std.Io.Reader, out: *std.Io.Writer) !void {
    try out.print("bits 16\n", .{});
    while (true) {
        const byte = in.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        const opcode = byte >> 2;
        if (opcode == 0b100010) {
            const next_byte = try in.takeByte();

            const d = byte & 0b10;
            const w = byte & 0b1;
            const mod = next_byte >> 6;
            const reg = (next_byte >> 3) & 0b111;
            const rm = next_byte & 0b111;

            if (mod == 0b11) {
                const src = if (d == 0) regs[reg][w] else regs[rm][w];
                const dst = if (d == 0) regs[rm][w] else regs[reg][w];
                try out.print("mov {s}, {s}\n", .{ dst, src });
            }
        }
    }

    try out.flush();
}
