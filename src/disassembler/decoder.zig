const std = @import("std");
const log = std.log.scoped(.decode);
const formatters = @import("formatters.zig");
const t = @import("tables.zig");

pub const Instruction = struct {
    op: t.Op,
    dst: Operand,
    src: Operand,

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
        value: u16,
        wide: ?bool = null,
    },
    invalid: void,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try formatters.operand(self, writer);
    }
};

pub fn decode(in: *std.Io.Reader) !Instruction {
    var components: std.EnumMap(t.ComponentType, u16) = .init(.{});

    var byte = try in.takeByte();
    log.debug("byte={b:0>8}", .{byte});

    const encoding: t.Encoding = layout_loop: for (t.encodings) |encoding| {
        for (encoding.layout) |layout| {
            if (layout.type == .bits) {
                // If bits are same then we found the layout
                const shift: u3 = @intCast(8 - layout.size);
                const in_bits = byte >> shift;
                if (in_bits == layout.value) break :layout_loop encoding;
            }
        }
    } else return error.InvalidInstruction;

    log.debug("layout={f}", .{encoding});
    log.debug("op={s}", .{@tagName(encoding.op)});

    var bitCount: u8 = 0;
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

        if (layout.type == .data_w and components.get(.w) != 1) {
            log.debug("skipping data_w", .{});
            continue;
        }

        const mod = components.get(.mod);
        const direct_address: bool = mod == 0b00 and components.get(.rm) == 0b110;
        if (layout.type == .disp and mod != 0b01 and mod != 0b10 and !direct_address) {
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
        }

        const position = bitCount;
        const shift: u3 = @intCast(8 - position - layout.size);
        const mask: u16 = (@as(u16, 1) << @intCast(layout.size)) - 1;
        components.put(layout.type, (byte >> shift) & mask);
        log.debug("pos={d} {s} = {b}", .{ position, @tagName(layout.type), components.get(layout.type).? });

        bitCount += layout.size;
    }

    const d = components.get(.d).?;
    const w = components.get(.w);

    var dst: Operand = .invalid;
    var src: Operand = .invalid;

    const reg_operand = if (d == 0) &src else &dst;
    const mod_operand = if (d == 0) &dst else &src;

    if (components.get(.reg)) |reg| {
        reg_operand.* = .{ .register = t.registers[reg][w.?] };
    }

    if (components.get(.mod)) |mod| {
        const rm = components.get(.rm).?;
        if (mod == 0b11) { // Register Mode
            mod_operand.* = .{ .register = t.registers[rm][w.?] };
        } else {
            if (mod == 0b00 and rm == 0b110) { // Direct Address
                mod_operand.* = .{
                    .direct_address = displacement(u16, components),
                };
            } else {
                mod_operand.* = t.effective_address_calculations[rm];
                mod_operand.*.effective_address_calculation.displacement = displacement(i16, components);
                log.debug("disp={d}", .{mod_operand.*.effective_address_calculation.displacement});
            }
        }
    }

    if (components.get(.data)) |data| {
        var imm = data;
        if (components.get(.data_w)) |data_w| {
            imm = (data_w << 8) | data;
        }
        if (mod_operand.* == .invalid) {
            mod_operand.* = .{ .immediate = .{ .value = imm } };
        } else {
            reg_operand.* = .{ .immediate = .{ .value = imm, .wide = w.? == 1 } };
        }
        log.debug("imm={d}", .{imm});
    }

    if (components.get(.address)) |address| {
        if (components.get(.address_w)) |address_w| {
            mod_operand.* = .{ .direct_address = @bitCast((address_w << 8) | address) };
        }
    }

    if (dst == .invalid or src == .invalid) {
        log.debug("ERROR: dst = {f} | src = {f}", .{ dst, src });
        return error.InvalidInstruction;
    }

    return Instruction{ .op = encoding.op, .dst = dst, .src = src };
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
