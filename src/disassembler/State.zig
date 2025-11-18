const std = @import("std");
const t = @import("tables.zig");
const Operand = @import("decoder.zig").Operand;

const State = @This();

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

memory: [1024 * 1024]u8 = undefined,

pub fn write(self: *State, to: ?Operand, value: u16) void {
    switch (to.?) {
        .register => |reg| self.writeReg(reg, value),
        else => unreachable,
    }
}

pub fn read(self: State, from: ?Operand) u16 {
    return switch (from.?) {
        .register => |reg| self.readReg(reg),
        .immediate => |imm| {
            const imm_u32: u32 = @bitCast(imm.value);
            return @truncate(imm_u32);
        },
        else => unreachable,
    };
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
                        const previous_value = @field(previous, field.name);
                        const current_value = @field(current, field.name);
                        if (previous_value != current_value) {
                            try writer.print("{s}:0x{x}->0x{x} ", .{ field.name, previous_value, current_value });
                        }
                    },
                    else => {},
                }
            }
        } else {
            try writer.print("BAD DIFF", .{});
        }
    }
};
