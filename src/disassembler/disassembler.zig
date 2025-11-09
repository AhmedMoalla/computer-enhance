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
    try print(out, "bits 16\n", .{});
    while (true) {
        const byte = in.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        // std.debug.print("{b:0>8} => ", .{byte});

        if ((byte >> 2) == 0b100010) { // Register/memory to/from register
            const next_byte = try in.takeByte();

            const d: u1 = @intCast((byte >> 1) & 0b1);
            const w: u1 = @intCast(byte & 0b1);
            const mod: u2 = @intCast(next_byte >> 6);
            const reg: u3 = @intCast((next_byte >> 3) & 0b111);
            const rm: u3 = @intCast(next_byte & 0b111);

            // std.debug.print("{b:0>8} => D={b} W={b} MOD={b:0>2} REG={b:0>3} R/M={b:0>3} ", .{ next_byte, d, w, mod, reg, rm });

            switch (mod) {
                0b00 => { // Memory mode, no displacement
                    if (rm == 0b110) { // Direct Address, 16-bit displacement
                        const address = std.mem.readInt(u16, try in.takeArray(2), .little);

                        if (d == 0) {
                            try print(out, "mov [{d}], {s}", .{ address, regs[reg][w] });
                        } else {
                            try print(out, "mov {s}, [{d}]", .{ regs[reg][w], address });
                        }
                        try print(out, "\n", .{});
                        continue;
                    }

                    const src = if (d == 0) regs[reg][w] else calcs[rm];
                    const dst = if (d == 0) calcs[rm] else regs[reg][w];

                    if (d == 0) {
                        try print(out, "mov [{s}], {s}", .{ dst, src });
                    } else {
                        try print(out, "mov {s}, [{s}]", .{ dst, src });
                    }
                },
                0b01 => { // Memory mode, 8-bit displacement
                    const src = if (d == 0) regs[reg][w] else calcs[rm];
                    const dst = if (d == 0) calcs[rm] else regs[reg][w];
                    const disp = try in.takeByteSigned();
                    const sign = if (disp > 0) "+" else "-";

                    if (d == 0) {
                        if (disp == 0) {
                            try print(out, "mov [{s}], {s}", .{ dst, src });
                        } else {
                            try print(out, "mov [{s} {s} {d}], {s}", .{ dst, sign, @abs(disp), src });
                        }
                    } else {
                        if (disp == 0) {
                            try print(out, "mov {s}, [{s}]", .{ dst, src });
                        } else {
                            try print(out, "mov {s}, [{s} {s} {d}]", .{ dst, src, sign, @abs(disp) });
                        }
                    }
                },
                0b10 => { // Memory mode, 16-bit displacement
                    const src = if (d == 0) regs[reg][w] else calcs[rm];
                    const dst = if (d == 0) calcs[rm] else regs[reg][w];
                    const disp = std.mem.readInt(i16, try in.takeArray(2), .little);
                    const sign = if (disp > 0) "+" else "-";

                    if (d == 0) {
                        if (disp == 0) {
                            try print(out, "mov [{s}], {s}", .{ dst, src });
                        } else {
                            try print(out, "mov [{s} {s} {d}], {s}", .{ dst, sign, @abs(disp), src });
                        }
                    } else {
                        if (disp == 0) {
                            try print(out, "mov {s}, [{s}]", .{ dst, src });
                        } else {
                            try print(out, "mov {s}, [{s} {s} {d}]", .{ dst, src, sign, @abs(disp) });
                        }
                    }
                },
                0b11 => { // Register mode
                    const src = if (d == 0) regs[reg][w] else regs[rm][w];
                    const dst = if (d == 0) regs[rm][w] else regs[reg][w];
                    try print(out, "mov {s}, {s}", .{ dst, src });
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
            try print(out, "mov {s}, {d}", .{ dst, imm });
        } else if ((byte >> 1) == 0b1100011) { // Immediate to register/memory
            const next_byte = try in.takeByte();

            const w: u1 = @intCast(byte & 0b1);
            const mod: u2 = @intCast(next_byte >> 6);
            const rm: u3 = @intCast(next_byte & 0b111);
            const disp = switch (mod) {
                0b01 => try in.takeByteSigned(), // Memory mode, 8-bit displacement
                0b10 => std.mem.readInt(i16, try in.takeArray(2), .little), // Memory mode, 16-bit displacement
                else => 0,
            };
            const sign = if (disp > 0) "+" else "-";

            const imm = switch (w) {
                0 => try in.takeByte(),
                1 => std.mem.readInt(u16, try in.takeArray(2), .little),
            };
            const imm_size = if (w == 1) "word" else "byte";

            // std.debug.print("{b:0>8} => W={b} MOD={b:0>2} R/M={b:0>3} ", .{ next_byte, w, mod, rm });
            if (mod == 0b11) {
                const dst = regs[rm][w];
                try print(out, "mov {s}, {s} {d}", .{ dst, imm_size, imm });
            } else {
                const dst = calcs[rm];
                if (disp == 0) {
                    try print(out, "mov [{s}], {s} {d}", .{ dst, imm_size, imm });
                } else {
                    try print(out, "mov [{s} {s} {d}], {s} {d}", .{ dst, sign, @abs(disp), imm_size, imm });
                }
            }
        } else if ((byte >> 2) == 0b101000) { // Memory to accumulator / Accumulator to memory
            const d: u1 = @intCast((byte >> 1) & 0b1);
            const w: u1 = @intCast(byte & 0b1);
            const acc = if (w == 0) "al" else "ax";
            const address = std.mem.readInt(u16, try in.takeArray(2), .little);

            if (d == 0) {
                try print(out, "mov {s}, [{d}]", .{ acc, address });
            } else {
                try print(out, "mov [{d}], {s}", .{ address, acc });
            }
        }

        try print(out, "\n", .{});
    }

    try out.flush();
}

fn print(out: *std.Io.Writer, comptime fmt: []const u8, args: anytype) !void {
    // std.debug.print(fmt, args);
    try out.print(fmt, args);
}
