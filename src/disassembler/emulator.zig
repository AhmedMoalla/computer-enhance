const std = @import("std");
const t = @import("tables.zig");
const decoder = @import("decoder.zig");
const disassembler = @import("disassembler.zig");
const State = @import("State.zig");

const log = std.log.scoped(.disasm);

pub fn execute(allocator: std.mem.Allocator, in: *std.Io.Reader, out: *std.Io.Writer) !void {
    var state = State{};

    var program = Program{ .ip = &state.ip, .instructions = try decoder.decodeAll(allocator, in) };
    while (true) {
        const instr = program.current();
        try out.print("{f} ; ", .{instr});

        var jumped = false;
        var diff = State.Diff.init(state);
        const wide = instr.components.get(.w) == 1;
        switch (instr.op) {
            .mov => state.write(instr.lhs, state.read(instr.rhs).unsigned),
            .add => state.write(instr.lhs, arithmeticOp(&state, instr, add, wide)),
            .sub => state.write(instr.lhs, arithmeticOp(&state, instr, sub, wide)),
            .cmp => _ = arithmeticOp(&state, instr, sub, wide),
            .jne => jumped = jump(&state, instr, !state.isFlagSet(.Z)),
            .je => jumped = jump(&state, instr, state.isFlagSet(.Z)),
            .jp => jumped = jump(&state, instr, state.isFlagSet(.P)),
            .jb => jumped = jump(&state, instr, state.isFlagSet(.C)),
            .loopnz => {
                state.cx -= 1;
                jumped = jump(&state, instr, state.cx != 0 and !state.isFlagSet(.Z));
            },
            else => std.debug.print("{t} not implemented yet\n", .{instr.op}),
        }
        program.advance(instr.size, jumped);
        diff.compare(state);
        try out.print("{f}\n", .{diff});
        if (program.done()) break;
    }

    try out.print("{f}", .{state});

    try out.flush();
}

fn jump(state: *State, instr: decoder.Instruction, condition: bool) bool {
    if (condition) {
        const value = instr.lhs.?.immediate.value;
        const offset: i32 = @as(i32, @intCast(instr.size)) + value;
        if (offset >= 0) {
            state.ip += @intCast(offset);
        } else {
            state.ip -= @intCast(-offset);
        }
        return true;
    }
    return false;
}

const Program = struct {
    ip: *u16,
    instructions: []decoder.Instruction,

    ip_index: usize = 0,

    pub fn current(self: Program) decoder.Instruction {
        return self.instructions[self.ip_index];
    }

    pub fn advance(self: *Program, instruction_size: usize, jumped: bool) void {
        if (jumped) {
            var ip: usize = 0;
            self.ip_index = 0;
            for (self.instructions) |instr| {
                self.ip_index += 1;
                ip += instr.size;
                if (ip == self.ip.*) {
                    break;
                }
            }
        } else {
            self.ip.* += @intCast(instruction_size);
            self.ip_index += 1;
        }
    }

    pub fn done(self: Program) bool {
        return self.ip_index == self.instructions.len;
    }
};

const ArithmeticOp = fn (state: State, lhs: ?decoder.Operand, rhs: ?decoder.Operand) ArithmeticOpResult;

const ArithmeticOpResult = struct {
    unsigned: u16,
    signed: i16,
    overflow: struct { unsigned: u1, signed: u1 },
    low_nibble_overflowed: bool,
};

fn add(state: State, lhs_op: ?decoder.Operand, rhs_op: ?decoder.Operand) ArithmeticOpResult {
    const lhs = state.read(lhs_op);
    const rhs = state.read(rhs_op);

    const signed_result = @addWithOverflow(lhs.signed, rhs.signed);
    const unsigned_result = @addWithOverflow(lhs.unsigned, rhs.unsigned);
    return ArithmeticOpResult{
        .unsigned = unsigned_result[0],
        .signed = signed_result[0],
        .overflow = .{ .unsigned = unsigned_result[1], .signed = signed_result[1] },
        .low_nibble_overflowed = ((lhs.unsigned & 0xf) +% (rhs.unsigned & 0xf)) & 0x10 > 0,
    };
}

fn sub(state: State, lhs_op: ?decoder.Operand, rhs_op: ?decoder.Operand) ArithmeticOpResult {
    const lhs = state.read(lhs_op);
    const rhs = state.read(rhs_op);

    const signed_result = @subWithOverflow(lhs.signed, rhs.signed);
    const unsigned_result = @subWithOverflow(lhs.unsigned, rhs.unsigned);
    return ArithmeticOpResult{
        .unsigned = unsigned_result[0],
        .signed = signed_result[0],
        .overflow = .{ .unsigned = unsigned_result[1], .signed = signed_result[1] },
        .low_nibble_overflowed = ((lhs.unsigned & 0xf) -% (rhs.unsigned & 0xf)) & 0x10 > 0,
    };
}

fn arithmeticOp(state: *State, instr: decoder.Instruction, op: ArithmeticOp, wide: bool) u16 {
    const result = op(state.*, instr.lhs, instr.rhs);
    const low_byte: u8 = @truncate(@as(u16, @bitCast(result.signed)) & 0xFF);
    const bit_count = @popCount(low_byte);
    state.setFlag(.P, (bit_count & 1) == 0);
    state.setFlag(.Z, result.signed == 0);
    if (wide) {
        state.setFlag(.S, result.signed < 0);
    } else {
        state.setFlag(.S, @as(i8, @truncate(result.signed)) < 0);
    }
    state.setFlag(.O, result.overflow.signed == 1);
    state.setFlag(.C, result.overflow.unsigned == 1);
    state.setFlag(.A, result.low_nibble_overflowed);
    return result.unsigned;
}
