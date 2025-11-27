const std = @import("std");
const decoder = @import("decoder.zig");
const t = @import("tables.zig");

pub const ClockEstimate = struct {
    clocks: u32,
    formula: ?ClockEstimateFormula = null,

    pub fn base(b: u32) ClockEstimate {
        return .{ .clocks = b };
    }

    pub fn ea(b: u32, memory_operand: decoder.Operand) ClockEstimate {
        const ea_clocks = eaClocks(memory_operand);
        return .{ .clocks = b + ea_clocks, .formula = .{ .base = b, .ea = ea_clocks } };
    }
};

pub const ClockEstimateFormula = struct {
    base: u32,
    ea: u32,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("({d} + {d}ea)", .{ self.base, self.ea });
    }
};

pub fn estimate(instr: decoder.Instruction) ClockEstimate {
    return switch (instr.op) {
        .mov => {
            const lhs = instr.lhs.?;
            const rhs = instr.rhs.?;

            return switch (lhs) {
                .register => switch (rhs) {
                    .register => .base(2),
                    .immediate => .base(4),
                    .direct_address, .effective_address_calculation => .ea(8, rhs),
                },
                .direct_address, .effective_address_calculation => switch (rhs) {
                    .register => |reg| if (reg.type == .a) .base(10) else .ea(9, lhs),
                    .immediate => .ea(10, lhs),
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
                    .direct_address, .effective_address_calculation => .ea(9, rhs),
                    .immediate => .base(4),
                },
                .direct_address, .effective_address_calculation => switch (rhs) {
                    .register => .ea(16, lhs),
                    .immediate => .ea(17, lhs),
                    else => unreachable,
                },
                else => unreachable,
            };
        },
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
