const std = @import("std");

// regs[R/M or REG][W]
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

// calcs[R/M]
const calcs: [8][]const u8 = [_][]const u8{
    "bx + si",
    "bx + di",
    "bp + si",
    "bp + di",
    "si",
    "di",
    "bp",
    "bx",
};

pub fn disassemble(in: *std.Io.Reader, out: *std.Io.Writer) !void {
    try out.print("bits 16\n", .{});
    while (true) {
        const byte = in.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        if ((byte >> 2) == 0b100010) { // Register/memory to/from register
            const next_byte = try in.takeByte();

            const d: u1 = @intCast((byte >> 1) & 0b1);
            const w: u1 = @intCast(byte & 0b1);
            const mod: u2 = @intCast(next_byte >> 6);
            const reg: u3 = @intCast((next_byte >> 3) & 0b111);
            const rm: u3 = @intCast(next_byte & 0b111);

            // std.debug.print("{b:0>8} {b:0>8} => D={b} W={b} MOD={b:0>2} REG={b:0>3} R/M={b:0>3} ", .{ byte, next_byte, d, w, mod, reg, rm });

            mod_sw: switch (mod) {
                0b00 => { // Memory mode, no displacement
                    if (rm == 0b110) continue :mod_sw 0b10;

                    const src = if (d == 0) regs[reg][w] else calcs[rm];
                    const dst = if (d == 0) calcs[rm] else regs[reg][w];

                    if (d == 0) {
                        try out.print("mov [{s}], {s}\n", .{ dst, src });
                    } else {
                        try out.print("mov {s}, [{s}]\n", .{ dst, src });
                    }
                },
                0b01 => { // Memory mode, 8-bit displacement
                    const src = if (d == 0) regs[reg][w] else calcs[rm];
                    const dst = if (d == 0) calcs[rm] else regs[reg][w];
                    const disp = try in.takeByte();

                    if (d == 0) {
                        if (disp == 0) {
                            try out.print("mov [{s}], {s}\n", .{ dst, src });
                        } else {
                            try out.print("mov [{s} + {d}], {s}\n", .{ dst, disp, src });
                        }
                    } else {
                        if (disp == 0) {
                            try out.print("mov {s}, [{s}]\n", .{ dst, src });
                        } else {
                            try out.print("mov {s}, [{s} + {d}]\n", .{ dst, src, disp });
                        }
                    }
                },
                0b10 => { // Memory mode, 16-bit displacement
                    const src = if (d == 0) regs[reg][w] else calcs[rm];
                    const dst = if (d == 0) calcs[rm] else regs[reg][w];
                    const disp = std.mem.readInt(u16, try in.takeArray(2), .little);

                    if (d == 0) {
                        if (disp == 0) {
                            try out.print("mov [{s}], {s}\n", .{ dst, src });
                        } else {
                            try out.print("mov [{s} + {d}], {s}\n", .{ dst, disp, src });
                        }
                    } else {
                        if (disp == 0) {
                            try out.print("mov {s}, [{s}]\n", .{ dst, src });
                        } else {
                            try out.print("mov {s}, [{s} + {d}]\n", .{ dst, src, disp });
                        }
                    }
                },
                0b11 => { // Register mode
                    const src = if (d == 0) regs[reg][w] else regs[rm][w];
                    const dst = if (d == 0) regs[rm][w] else regs[reg][w];
                    try out.print("mov {s}, {s}\n", .{ dst, src });
                },
            }
        } else if ((byte >> 4) == 0b1011) { // Immediate to register
            const w: u1 = @intCast((byte >> 3) & 0b1);
            const reg: u3 = @intCast(byte & 0b111);

            const imm: u16 = blk: {
                if (w == 0) {
                    break :blk try in.takeByte();
                }

                break :blk std.mem.readInt(u16, try in.takeArray(2), .little);
            };

            const dst = regs[reg][w];
            try out.print("mov {s}, {d}\n", .{ dst, imm });
        }
    }

    try out.flush();
}
