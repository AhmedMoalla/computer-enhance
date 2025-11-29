const std = @import("std");
const decoder = @import("decoder.zig");
const t = @import("tables.zig");

pub const ClockEstimate = struct {
    clocks: u32,
    formula: ?ClockEstimateFormula = null,

    pub fn base(b: u32) ClockEstimate {
        return .{ .clocks = b };
    }

    pub fn baset(b: u32, memory_operand: decoder.Operand, transfers: u32) ClockEstimate {
        var result = ClockEstimate{ .clocks = b };
        if (addressIsOdd(memory_operand)) {
            const total_transfers = transfers * 4;
            result.clocks += total_transfers;
            result.formula = .{ .base = b, .transfers = total_transfers };
        }
        return result;
    }

    pub fn ea(b: u32, memory_operand: decoder.Operand, transfers: u32) ClockEstimate {
        const ea_clocks = eaClocks(memory_operand);
        var result = ClockEstimate{
            .clocks = b + ea_clocks,
            .formula = .{ .base = b, .ea = ea_clocks },
        };
        if (addressIsOdd(memory_operand)) {
            const total_transfers = transfers * 4;
            result.clocks += total_transfers;
            result.formula.?.transfers = total_transfers;
        }
        return result;
    }
};

pub const ClockEstimateFormula = struct {
    base: u32,
    ea: u32 = 0,
    transfers: u32 = 0,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("({d}", .{self.base});

        if (self.ea != 0) {
            try writer.print(" + {d}ea", .{self.ea});
        }
        if (self.transfers != 0) {
            try writer.print(" + {d}p", .{self.transfers});
        }
        try writer.print(")", .{});
    }
};

pub fn estimate(instr: decoder.Instruction, jumped: bool) ClockEstimate {
    return switch (instr.op) {
        .mov => {
            const lhs = instr.lhs.?;
            const rhs = instr.rhs.?;

            return switch (lhs) {
                .register => switch (rhs) {
                    .register => .base(2),
                    .immediate => .base(4),
                    .direct_address, .effective_address_calculation => .ea(8, rhs, 1),
                },
                .direct_address, .effective_address_calculation => switch (rhs) {
                    .register => |reg| if (reg.type == .a) .baset(10, lhs, 1) else .ea(9, lhs, 1),
                    .immediate => .ea(10, lhs, 1),
                    else => unreachable,
                },
                else => unreachable,
            };
        },
        .add => {
            const lhs = instr.lhs.?;
            const rhs = instr.rhs.?;

            return switch (lhs) {
                .register => switch (rhs) {
                    .register => .base(3),
                    .direct_address, .effective_address_calculation => .ea(9, rhs, 1),
                    .immediate => .base(4),
                },
                .direct_address, .effective_address_calculation => switch (rhs) {
                    .register => .ea(16, lhs, 2),
                    .immediate => .ea(17, lhs, 2),
                    else => unreachable,
                },
                else => unreachable,
            };
        },
        .inc => {
            const lhs = instr.lhs.?;

            return switch (lhs) {
                .register => |reg| .base(if (reg.width == 1) 3 else 2),
                .direct_address, .effective_address_calculation => .ea(15, lhs, 2),
                else => unreachable,
            };
        },
        .cmp => {
            const lhs = instr.lhs.?;
            const rhs = instr.rhs.?;

            return switch (lhs) {
                .register => switch (rhs) {
                    .register => .base(3),
                    .direct_address, .effective_address_calculation => .ea(9, rhs, 1),
                    .immediate => .base(4),
                },
                .direct_address, .effective_address_calculation => switch (rhs) {
                    .register => .ea(9, lhs, 1),
                    .immediate => .ea(10, lhs, 1),
                    else => unreachable,
                },
                else => unreachable,
            };
        },
        .@"test" => {
            const lhs = instr.lhs.?;
            const rhs = instr.rhs.?;

            return switch (lhs) {
                .register => |lreg| switch (rhs) {
                    .register => .base(3),
                    .direct_address, .effective_address_calculation => .ea(9, rhs, 1),
                    .immediate => .base(if (lreg.type == .a) 4 else 5),
                },
                .direct_address, .effective_address_calculation => switch (rhs) {
                    .immediate => .ea(11, lhs, 0),
                    else => unreachable,
                },
                else => unreachable,
            };
        },
        .xor => {
            const lhs = instr.lhs.?;
            const rhs = instr.rhs.?;

            return switch (lhs) {
                .register => switch (rhs) {
                    .register => .base(3),
                    .direct_address, .effective_address_calculation => .ea(9, rhs, 1),
                    .immediate => .base(4),
                },
                .direct_address, .effective_address_calculation => switch (rhs) {
                    .register => .ea(16, rhs, 2),
                    .immediate => .ea(17, lhs, 2),
                    else => unreachable,
                },
                else => unreachable,
            };
        },
        .je,
        .jl,
        .jle,
        .jb,
        .jbe,
        .jp,
        .jo,
        .js,
        .jne,
        .jnl,
        .jg,
        .jnb,
        .ja,
        .jnp,
        .jno,
        .jns,
        => .base(if (jumped) 16 else 4),
        else => unreachable,
    };
}

fn eaClocks(operand: decoder.Operand) u32 {
    return switch (operand) {
        .effective_address_calculation => |eac| {
            const reg1 = eac.reg1;
            if (eac.reg2) |reg2| {
                if ((reg1.type == .bp and reg2.type == .di) or (reg1.type == .b and reg2.type == .si)) {
                    if (eac.displacement != 0) return 11;
                    return 7;
                }
                if ((reg1.type == .bp and reg2.type == .si) or (reg1.type == .b and reg2.type == .di)) {
                    if (eac.displacement != 0) return 12;

                    return 8;
                }
            }

            if (eac.displacement != 0) return 9;
            return 5;
        },
        .direct_address => 6,
        else => unreachable,
    };
}

fn addressIsOdd(operand: decoder.Operand) bool {
    return switch (operand) {
        .effective_address_calculation => |eac| @mod(eac.displacement, 2) == 1,
        .direct_address => |da| @mod(da, 2) == 1,
        else => unreachable,
    };
}
