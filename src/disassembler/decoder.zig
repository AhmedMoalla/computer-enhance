const std = @import("std");
const log = std.log.scoped(.decode);
const formatters = @import("formatters.zig");
const t = @import("tables.zig");

const ComponentMap = std.EnumMap(t.ComponentType, u16);

pub const Instruction = struct {
    op: t.Op,
    lhs: ?Operand = null,
    rhs: ?Operand = null,
    size: usize,
    prefix: ?t.Op = null,
    segment_override: ?t.Register = null,
    components: ComponentMap,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try formatters.instruction(self, writer);
    }
};

pub const Operand = union(enum) {
    direct_address: u16,
    effective_address_calculation: struct {
        reg1: t.Register,
        reg2: ?t.Register = null,
        displacement: i16 = 0,
    },
    register: t.Register,
    immediate: struct {
        value: i32,
        wide: ?bool = null,
        jump: bool = false, // Necessary to format for nasm as $+imm or $-imm
    },

    pub fn directAddress(addr: u16) Operand {
        return .{ .direct_address = addr };
    }

    pub fn eac(rm: u16, disp: i16) Operand {
        const effective_address_calculations: [8]Operand = .{
            .{ .effective_address_calculation = .{ .reg1 = t.BX, .reg2 = t.SI } },
            .{ .effective_address_calculation = .{ .reg1 = t.BX, .reg2 = t.DI } },
            .{ .effective_address_calculation = .{ .reg1 = t.BP, .reg2 = t.SI } },
            .{ .effective_address_calculation = .{ .reg1 = t.BP, .reg2 = t.DI } },
            .{ .effective_address_calculation = .{ .reg1 = t.SI } },
            .{ .effective_address_calculation = .{ .reg1 = t.DI } },
            .{ .effective_address_calculation = .{ .reg1 = t.BP } },
            .{ .effective_address_calculation = .{ .reg1 = t.BX } },
        };
        var result = effective_address_calculations[rm];
        result.effective_address_calculation.displacement = disp;
        return result;
    }

    pub fn reg(value: t.Register) Operand {
        return .{ .register = value };
    }

    pub fn imm(value: i32, wide: ?bool) Operand {
        return .{ .immediate = .{ .value = value, .wide = wide } };
    }

    pub fn jmp(value: i32) Operand {
        return .{ .immediate = .{ .value = value, .jump = true } };
    }
};

// Takes first two bytes and tries to find if they match an encoding.
// The matching encoding has its .bits layout component matching those in the the first two bytes.
pub fn findEncoding(bytes: []u8) !t.Encoding {
    std.debug.assert(bytes.len == 2);
    log.debug("bytes={b:0>8} {b:0>8} ({X:0>2} {X:0>2})", .{ bytes[0], bytes[1], bytes[0], bytes[1] });
    const word: u16 = (@as(u16, bytes[0]) << 8) | bytes[1];
    return layout_loop: for (t.encodings) |encoding| {
        var valid = true;
        var remaining_bit_size: u8 = @bitSizeOf(u16);
        var remaining_bits = word;

        for (encoding.layout) |component| {
            if (component.size == 0) continue;

            var shift: u4 = @intCast(remaining_bit_size - component.size);
            const in_bits = remaining_bits >> shift;
            remaining_bit_size -= component.size;

            if (remaining_bit_size == 0) {
                break;
            }

            shift = @intCast(16 - remaining_bit_size);
            remaining_bits &= @as(u16, 0xFFFF) >> shift;

            if (component.type == .bits and in_bits != component.value) {
                valid = false;
                break;
            }
        }
        if (valid) {
            break :layout_loop encoding;
        }
    } else error.InvalidInstruction;
}

pub fn decode(in: *std.Io.Reader) !Instruction {
    var components: ComponentMap = .init(.{});

    const encoding: t.Encoding = try findEncoding(try in.peekArray(2));
    log.debug("encoding={f}", .{encoding});

    const all_components_bits = for (encoding.layout) |component| {
        if (component.type != .bits) break false;
    } else true;
    if (all_components_bits) {
        in.toss(encoding.layout.len);
        if (encoding.op == .rep or encoding.op == .repne or encoding.op == .lock) {
            const instr = try decode(in);
            return Instruction{
                .op = instr.op,
                .lhs = instr.lhs,
                .rhs = instr.rhs,
                .size = instr.size + encoding.layout.len,
                .prefix = encoding.op,
                .components = instr.components,
            };
        }
        return Instruction{
            .op = encoding.op,
            .size = encoding.layout.len,
            .components = components,
        };
    }

    var size: usize = 0;
    var bitCount: u8 = 0;
    var byte = try in.takeByte();
    for (encoding.layout) |layout| {
        if (layout.type == .bits) {
            const position = bitCount;
            const shift: u3 = @intCast(8 - position - layout.size);
            const mask: u16 = (@as(u16, 1) << @intCast(layout.size)) - 1;
            std.debug.assert(((byte >> shift) & mask) == layout.value);
            bitCount += layout.size;
            continue;
        }

        if (layout.size == 0) {
            components.put(layout.type, layout.value);
            log.debug("implicit {s} = {b}", .{ @tagName(layout.type), layout.value });
            continue;
        }

        const data_sign_extended = components.get(.s) == 1;
        const data_is_wide = components.get(.w) == 1 and !data_sign_extended;
        if (layout.type == .data_w and !data_is_wide) {
            log.debug("skipping data_w", .{});
            continue;
        }

        const is_jump = components.get(.jump) == 1;
        const mod = components.get(.mod);
        const direct_address: bool = mod == 0b00 and components.get(.rm) == 0b110;
        if (layout.type == .disp and mod != 0b01 and mod != 0b10 and !direct_address and !is_jump) {
            log.debug("skipping disp", .{});
            continue;
        }

        if (layout.type == .disp_w and mod != 0b10 and !direct_address) {
            log.debug("skipping disp_w", .{});
            continue;
        }

        if (bitCount >= 8) {
            byte = try in.takeByte();
            log.debug("byte={b:0>8}", .{byte});
            bitCount = 0;
            size += 1;
        }

        const position = bitCount;
        const shift: u3 = @intCast(8 - position - layout.size);
        const mask: u16 = (@as(u16, 1) << @intCast(layout.size)) - 1;
        components.put(layout.type, (byte >> shift) & mask);
        log.debug("pos={d} {s} = {b}", .{ position, @tagName(layout.type), components.get(layout.type).? });

        bitCount += layout.size;
    }
    size += 1; // last byte isn't counted in last loop

    const d = components.get(.d) orelse 0;
    const w = components.get(.w);

    var lhs: ?Operand = null;
    var rhs: ?Operand = null;

    const reg_operand = if (d == 0) &rhs else &lhs;
    const mod_operand = if (d == 0) &lhs else &rhs;

    if (components.get(.reg)) |reg| {
        reg_operand.* = .reg(t.registers[reg][w.?]);
    }

    if (components.get(.mod)) |mod| {
        const rm = components.get(.rm).?;
        if (mod == 0b11) { // Register Mode
            mod_operand.* = .reg(t.registers[rm][w.?]);
        } else {
            if (mod == 0b00 and rm == 0b110) { // Direct Address
                mod_operand.* = .directAddress(displacement(u16, components));
            } else {
                mod_operand.* = .eac(rm, displacement(i16, components));
                log.debug("disp={d}", .{mod_operand.*.?.effective_address_calculation.displacement});
            }
        }
    }

    if (components.get(.data)) |data| {
        var imm: i32 = @intCast(data);
        if (components.get(.data_w)) |data_w| {
            imm = (data_w << 8) | data;
        }
        if (components.get(.s) == 1) {
            const signed: i8 = @bitCast(@as(u8, @truncate(data)));
            imm = @intCast(signed);
        }
        if (mod_operand.* == null) {
            mod_operand.* = .imm(imm, null);
        } else {
            reg_operand.* = .imm(imm, w.? == 1);
        }
        log.debug("imm={d}", .{imm});
    }

    if (components.get(.address)) |address| {
        if (components.get(.address_w)) |address_w| {
            mod_operand.* = .directAddress(@bitCast((address_w << 8) | address));
        }
    }

    if (components.get(.seg)) |seg| {
        reg_operand.* = .reg(t.segments[seg]);
    }

    if (components.get(.jump) == 1) {
        lhs = .jmp(displacement(i16, components));
        rhs = null;
    }

    const v = components.get(.v);
    if (v == 0) {
        rhs = .imm(1, null);
    } else if (v == 1) {
        rhs = .reg(t.CL);
    }

    if (encoding.op == .segment) {
        const sreg = lhs.?;
        const instr = try decode(in);
        return Instruction{
            .op = instr.op,
            .lhs = instr.lhs,
            .rhs = instr.rhs,
            .size = instr.size + encoding.layout.len,
            .segment_override = sreg.register,
            .components = instr.components,
        };
    }

    log.debug("lhs={any} | rhs={any}", .{ lhs, rhs });

    return Instruction{
        .op = encoding.op,
        .lhs = lhs,
        .rhs = rhs,
        .size = size,
        .components = components,
    };
}

fn displacement(comptime T: type, components: std.EnumMap(t.ComponentType, u16)) T {
    if (components.get(.disp)) |disp| {
        if (components.get(.disp_w)) |disp_w| { // 16-bit displacement
            return @bitCast((disp_w << 8) | disp);
        }
        // 8-bit displacement
        const disp_u8: u8 = @intCast(disp);
        if (T == u16) {
            return disp_u8;
        } else {
            const disp_i8: i8 = @bitCast(disp_u8);
            return @as(T, disp_i8);
        }
    }
    return 0; // No displacement
}
