const std = @import("std");
const log = std.log.scoped(.disasm);
const t = @import("tables.zig");
const decoder = @import("decoder.zig");
const disassembler = @import("disassembler.zig");

pub const State = struct {
    ax: u16 = 0,
    bx: u16 = 0,
    cx: u16 = 0,
    dx: u16 = 0,
    sp: u16 = 0,
    bp: u16 = 0,
    si: u16 = 0,
    di: u16 = 0,

    pub fn write(self: *State, reg: t.Register, value: u16) void {
        switch (reg.type) {
            .a => self.ax = value,
            .b => self.bx = value,
            .c => self.cx = value,
            .d => self.dx = value,
            .sp => self.sp = value,
            .bp => self.bp = value,
            .si => self.si = value,
            .di => self.di = value,
            else => unreachable,
        }
    }

    pub fn read(self: State, reg: t.Register) u16 {
        return switch (reg.type) {
            .a => return self.ax,
            .b => return self.bx,
            .c => return self.cx,
            .d => return self.dx,
            .sp => return self.sp,
            .bp => return self.bp,
            .si => return self.si,
            .di => return self.di,
            else => unreachable,
        };
    }
};

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
        switch (instr.op) {
            .mov => {
                var register: ?t.Register = null;
                switch (instr.lhs.?) {
                    .register => |reg| register = reg,
                    else => {},
                }

                switch (instr.rhs.?) {
                    .immediate => |imm| {
                        const imm_u32: u32 = @bitCast(imm.value);
                        const value: u16 = @truncate(imm_u32);

                        try out.print("{s}:0x{x}", .{ register.?.name, state.read(register.?) });
                        state.write(register.?, value);
                        try out.print("->0x{x}", .{state.read(register.?)});
                    },
                    .register => |reg| {
                        if (register) |lhs_reg| {
                            try out.print("{s}:0x{x}", .{ lhs_reg.name, state.read(lhs_reg) });
                            state.write(lhs_reg, state.read(reg));
                            try out.print("->0x{x}", .{state.read(lhs_reg)});
                        }
                    },
                    else => {},
                }
            },
            else => {
                std.debug.print("{t} not implemented yet\n", .{instr.op});
            },
        }
        try out.print(" \n", .{});
    }

    try out.print("\nFinal registers:\n", .{});
    try out.print("      ax: 0x{x:0>4} ({d})\n", .{ state.ax, state.ax });
    try out.print("      bx: 0x{x:0>4} ({d})\n", .{ state.bx, state.bx });
    try out.print("      cx: 0x{x:0>4} ({d})\n", .{ state.cx, state.cx });
    try out.print("      dx: 0x{x:0>4} ({d})\n", .{ state.dx, state.dx });
    try out.print("      sp: 0x{x:0>4} ({d})\n", .{ state.sp, state.sp });
    try out.print("      bp: 0x{x:0>4} ({d})\n", .{ state.bp, state.bp });
    try out.print("      si: 0x{x:0>4} ({d})\n", .{ state.si, state.si });
    try out.print("      di: 0x{x:0>4} ({d})\n", .{ state.di, state.di });
    try out.print("\n", .{});

    try out.flush();
}
