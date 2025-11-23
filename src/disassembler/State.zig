const std = @import("std");
const utils = @import("utils");
const t = @import("tables.zig");
const Operand = @import("decoder.zig").Operand;

const State = @This();
const FlagsBitSet = std.StaticBitSet(Flag.count);

pub var print_instruction_pointer: bool = true;

ax: u16 = 0,
bx: u16 = 0,
cx: u16 = 0,
dx: u16 = 0,
sp: u16 = 0,
bp: u16 = 0,
si: u16 = 0,
di: u16 = 0,

es: u16 = 0,
cs: u16 = 0,
ss: u16 = 0,
ds: u16 = 0,

ip: u16 = 0,

flags: FlagsBitSet = FlagsBitSet.initEmpty(),

memory: [1024 * 1024]u8 = undefined,

pub const Flag = enum(u4) {
    C, // Carry
    P, // Parity
    A, // Auxiliary carry
    Z, // Zero
    S, // Sign
    T, // Trap
    I, // Interrupt
    D, // Direction
    O, // Overflow

    const count = @typeInfo(Flag).@"enum".fields.len;
};

pub fn write(self: *State, to: ?Operand, value: u16, wide: bool) void {
    sw: switch (to.?) {
        .register => |reg| self.writeReg(reg, value),
        .direct_address => |da| {
            if (wide) {
                self.memory[da] = @truncate(value >> 8);
                self.memory[da + 1] = @truncate(value & 0xFF);
            } else {
                self.memory[da] = @truncate(value & 0xFF);
            }
        },
        .effective_address_calculation => |eac| {
            var da = self.readReg(eac.reg1);
            if (eac.reg2) |reg2| {
                da += self.readReg(reg2);
            }
            if (eac.displacement >= 0) {
                da += @intCast(eac.displacement);
            } else {
                da -= @intCast(-eac.displacement);
            }
            continue :sw .{ .direct_address = da };
        },
        else => unreachable,
    }
}

pub fn read(self: State, from: ?Operand, wide: bool) struct { signed: i16, unsigned: u16 } {
    sw: switch (from.?) {
        .register => |reg| {
            const value = self.readReg(reg);
            return .{ .signed = @bitCast(value), .unsigned = value };
        },
        .immediate => |imm| {
            const imm_u32: u32 = @bitCast(imm.value);
            return .{ .signed = @truncate(imm.value), .unsigned = @truncate(imm_u32) };
        },
        .direct_address => |da| {
            if (wide) {
                const value = std.mem.readVarInt(u16, self.memory[da .. da + 2], .big);
                return .{ .signed = @bitCast(value), .unsigned = @intCast(value) };
            } else {
                return .{ .signed = self.memory[da], .unsigned = @intCast(self.memory[da]) };
            }
        },
        .effective_address_calculation => |eac| {
            var da = self.readReg(eac.reg1);
            if (eac.reg2) |reg2| {
                da += self.readReg(reg2);
            }
            if (eac.displacement >= 0) {
                da += @intCast(eac.displacement);
            } else {
                da -= @intCast(-eac.displacement);
            }
            continue :sw .{ .direct_address = da };
        },
    }
}

pub fn setFlag(self: *State, flag: Flag, value: bool) void {
    self.flags.setValue(@intFromEnum(flag), value);
}

pub fn isFlagSet(self: State, flag: Flag) bool {
    return self.flags.isSet(@intFromEnum(flag));
}

fn writeReg(self: *State, reg: t.Register, value: u16) void {
    switch (reg.type) {
        inline .a, .b, .c, .d => |reg_type| {
            const reg_name = @tagName(reg_type) ++ "x";
            if (reg.width == 1) {
                const shift: u4 = reg.offset * @as(u4, 8);
                const mask: u16 = @as(u16, 0xFF00) >> shift;
                @field(self, reg_name) = (@field(self, reg_name) & mask) | (value << shift);
            } else {
                @field(self, reg_name) = value;
            }
        },
        inline else => |reg_type| @field(self, @tagName(reg_type)) = value,
    }
}

fn readReg(self: State, reg: t.Register) u16 {
    return switch (reg.type) {
        inline .a, .b, .c, .d => |reg_type| {
            const reg_name = @tagName(reg_type) ++ "x";
            if (reg.width == 1) {
                const shift: u4 = reg.offset * @as(u4, 8);
                const mask: u16 = @as(u16, 0xFF) << shift;
                return (@field(self, reg_name) & mask) >> shift;
            } else {
                return @field(self, reg_name);
            }
        },
        inline else => |reg_type| @field(self, @tagName(reg_type)),
    };
}

pub fn format(self: State, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("\nFinal registers:\n", .{});
    inline for (@typeInfo(State).@"struct".fields) |field| {
        switch (@typeInfo(field.type)) {
            .int => {
                if (!std.mem.eql(u8, field.name, "ip") or print_instruction_pointer) {
                    const value = @field(self, field.name);
                    if (value > 0) {
                        try writer.print("      {s}: 0x{x:0>4} ({d})\n", .{ field.name, value, value });
                    }
                }
            },
            else => {},
        }
    }

    if (self.flags.mask != 0) {
        try writer.print("   flags: ", .{});
        try formatFlags(self, writer);
    }
}

fn formatFlags(state: State, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (state.flags.mask != 0) {
        inline for (@typeInfo(Flag).@"enum".fields) |field| {
            if (state.flags.isSet(field.value)) {
                try writer.print("{s}", .{field.name});
            }
        }
    }
}

pub const Diff = struct {
    previous: State,
    current: ?State = null,

    pub fn init(previous: State) Diff {
        return Diff{ .previous = previous };
    }

    pub fn compare(self: *Diff, current: State) void {
        self.current = current;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const previous = self.previous;
        if (self.current) |current| {
            inline for (@typeInfo(State).@"struct".fields) |field| {
                switch (@typeInfo(field.type)) {
                    .int => {
                        if (!std.mem.eql(u8, field.name, "ip") or print_instruction_pointer) {
                            const previous_value = @field(previous, field.name);
                            const current_value = @field(current, field.name);
                            if (previous_value != current_value) {
                                try writer.print("{s}:0x{x}->0x{x} ", .{ field.name, previous_value, current_value });
                            }
                        }
                    },
                    else => {},
                }
            }

            if (!previous.flags.eql(current.flags)) {
                try writer.print("flags:", .{});
                try formatFlags(previous, writer);
                try writer.print("->", .{});
                try formatFlags(current, writer);
                try writer.print(" ", .{});
            }
        } else {
            try writer.print("BAD DIFF", .{});
        }
    }
};
