const std = @import("std");
const formatters = @import("formatters.zig");
const decoder = @import("decoder.zig");

pub const Op = enum {
    mov,
    add,
    sub,
    cmp,
    jnz,
    je,
    jl,
    jle,
    jb,
    jbe,
    jp,
    jo,
    js,
    jne,
    jnl,
    jg,
    jnb,
    ja,
    jnp,
    jno,
    jns,
    loop,
    loopz,
    loopnz,
    jcxz,
};

pub const ComponentType = enum(usize) {
    bits,
    d,
    w,
    mod,
    reg,
    rm,
    s,
    disp,
    disp_w,
    data,
    data_w,
    address,
    address_w,

    // Flags
    jump,
};

pub const EncodingComponent = struct {
    type: ComponentType,
    size: u8,
    value: u8 = 0,
};

pub const Encoding = struct {
    op: Op,
    name: []const u8,
    layout: []const EncodingComponent,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try formatters.encoding(self, writer);
    }
};

pub const RegisterType = enum {
    a,
    b,
    c,
    d,
    sp,
    bp,
    si,
    di,
};

pub const Register = struct {
    name: []const u8,
    type: RegisterType,
    width: u8, // 1 or 2
    offset: u8, // 1 or 2
};

pub const effective_address_calculations: [8]decoder.Operand = .{
    .{ .effective_address_calculation = .{ .reg1 = BX, .reg2 = SI } },
    .{ .effective_address_calculation = .{ .reg1 = BX, .reg2 = DI } },
    .{ .effective_address_calculation = .{ .reg1 = BP, .reg2 = SI } },
    .{ .effective_address_calculation = .{ .reg1 = BP, .reg2 = DI } },
    .{ .effective_address_calculation = .{ .reg1 = SI } },
    .{ .effective_address_calculation = .{ .reg1 = DI } },
    .{ .effective_address_calculation = .{ .reg1 = BP } },
    .{ .effective_address_calculation = .{ .reg1 = BX } },
};

pub const AL: Register = .{ .name = "al", .type = .a, .width = 1, .offset = 0 };
pub const AH: Register = .{ .name = "ah", .type = .a, .width = 1, .offset = 1 };
pub const AX: Register = .{ .name = "ax", .type = .a, .width = 2, .offset = 0 };
pub const BL: Register = .{ .name = "bl", .type = .b, .width = 1, .offset = 0 };
pub const BH: Register = .{ .name = "bh", .type = .b, .width = 1, .offset = 1 };
pub const BX: Register = .{ .name = "bx", .type = .b, .width = 2, .offset = 0 };
pub const CL: Register = .{ .name = "cl", .type = .c, .width = 1, .offset = 0 };
pub const CH: Register = .{ .name = "ch", .type = .c, .width = 1, .offset = 1 };
pub const CX: Register = .{ .name = "cx", .type = .c, .width = 2, .offset = 0 };
pub const DL: Register = .{ .name = "dl", .type = .d, .width = 1, .offset = 0 };
pub const DH: Register = .{ .name = "dh", .type = .d, .width = 1, .offset = 1 };
pub const DX: Register = .{ .name = "dx", .type = .d, .width = 2, .offset = 0 };
pub const SP: Register = .{ .name = "sp", .type = .sp, .width = 2, .offset = 0 };
pub const BP: Register = .{ .name = "bp", .type = .bp, .width = 2, .offset = 0 };
pub const SI: Register = .{ .name = "si", .type = .si, .width = 2, .offset = 0 };
pub const DI: Register = .{ .name = "di", .type = .di, .width = 2, .offset = 0 };

pub const registers: [8][2]Register = .{
    .{ AL, AX },
    .{ CL, CX },
    .{ DL, DX },
    .{ BL, BX },
    .{ AH, SP },
    .{ CH, BP },
    .{ DH, SI },
    .{ BH, DI },
};

// TODO: Generate map at comptime which maps every combination to a layout based on this table
pub const encodings = [_]Encoding{
    e(.mov, "Register/memory to/from register", //
        .{ "100010", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.mov, "Immediate to register/memory", //
        .{ "1100011", .w, .mod, "000", .rm, .disp, .disp_w, .data, .data_w }, .{ .d = 0 }),
    e(.mov, "Immediate to register", //
        .{ "1011", .w, .reg, .data, .data_w }, .{ .d = 1 }),
    e(.mov, "Memory to accumulator", //
        .{ "1010000", .w, .address, .address_w }, .{ .d = 1, .mod = 0, .reg = 0, .rm = 0b110 }),
    e(.mov, "Accumulator to memory", //
        .{ "1010001", .w, .address, .address_w }, .{ .d = 0, .mod = 0, .reg = 0, .rm = 0b110 }),

    e(.add, "Reg/memory with register to either", //
        .{ "000000", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.add, "Immediate to register/memory", //
        .{ "100000", .s, .w, .mod, "000", .rm, .disp, .disp_w, .data, .data_w }, .{ .d = 0 }),
    e(.add, "Immediate to accumulator", //
        .{ "0000010", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.sub, "Reg/memory with register to either", //
        .{ "001010", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.sub, "Immediate to register/memory", //
        .{ "100000", .s, .w, .mod, "101", .rm, .disp, .disp_w, .data, .data_w }, .{ .d = 0 }),
    e(.sub, "Immediate to accumulator", //
        .{ "0010110", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.cmp, "Register/memory and register", //
        .{ "001110", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.cmp, "Immediate with register/memory", //
        .{ "100000", .s, .w, .mod, "111", .rm, .disp, .disp_w, .data, .data_w }, .{ .d = 0 }),
    e(.cmp, "Immediate with accumulator", //
        .{ "0011110", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    j(.je, "Jump on equal/zero (JZ)", "01110100"),
    j(.jl, "Jump on less/not greater or equal (JNGE)", "01111100"),
    j(.jle, "Jump on less or equal/not greater (JNG)", "01111110"),
    j(.jb, "Jump on below/not above or equal (JNAE)", "01110010"),
    j(.jbe, "Jump on below or equal/not above (JNA)", "01110110"),
    j(.jp, "Jump on parity/parity even (JPE)", "01111010"),
    j(.jo, "Jump on overflow", "01110000"),
    j(.js, "Jump on sign", "01111000"),
    j(.jne, "Jump on not equal/not zero (JNZ)", "01110101"),
    j(.jnl, "Jump on not less/greater or equal (JGE)", "01111101"),
    j(.jg, "Jump on not less or equal/greater (JNLE)", "01111111"),
    j(.jnb, "Jump on not below/above or equal (JAE)", "01110011"),
    j(.ja, "Jump on not below or equal/above (JNBE)", "01110111"),
    j(.jnp, "Jump on not par/par odd (JPO)", "01111011"),
    j(.jno, "Jump on not overflow", "01110001"),
    j(.jns, "Jump on not sign", "01111001"),
    j(.loop, "Loop CX times", "11100010"),
    j(.loopz, "Loop while zero/equal (LOOPE)", "11100001"),
    j(.loopnz, "Loop while not zero/equal (LOOPNE)", "11100000"),
    j(.jcxz, "Jump on CX zero", "11100011"),
};

fn j(op: Op, comptime name: []const u8, comptime bits: []const u8) Encoding {
    return e(op, name, .{ bits, .disp }, .{ .jump = 1 });
}

fn e(op: Op, comptime name: []const u8, layout: anytype, implicits: anytype) Encoding {
    return switch (@typeInfo(@TypeOf(layout))) {
        .@"struct" => Encoding{ .op = op, .name = name, .layout = &(parseImplicits(implicits) ++ parseComponents(layout)) },
        else => @compileError("expected 'layout' to be a tuple."),
    };
}

fn parseComponents(layout: anytype) [layout.len]EncodingComponent {
    @setEvalBranchQuota(50000);
    var components: [layout.len]EncodingComponent = undefined;
    inline for (layout, 0..) |component, i| {
        components[i] = switch (@typeInfo(@TypeOf(component))) {
            .pointer => EncodingComponent{
                .type = .bits,
                .size = component.len,
                .value = std.fmt.parseInt(u8, component, 2) catch @compileError("could not parse bits: " ++ component),
            },
            .enum_literal => EncodingComponent{
                .type = component,
                .size = switch (component) {
                    .d, .w, .s => 1,
                    .mod => 2,
                    .reg, .rm => 3,
                    .disp, .disp_w, .data, .data_w, .address, .address_w => 8,
                    else => @compileError("unexpected component: " ++ component),
                },
            },
            else => |t| @compileError("expected 'layout' component to either comptime_int or Op" ++ t),
        };
    }
    return components;
}

fn parseImplicits(implicits: anytype) [structLen(implicits)]EncodingComponent {
    switch (@typeInfo(@TypeOf(implicits))) {
        .@"struct" => |s| {
            var components: [structLen(implicits)]EncodingComponent = undefined;
            inline for (s.fields, 0..) |field, i| {
                components[i] = EncodingComponent{
                    .type = std.meta.stringToEnum(ComponentType, field.name) orelse @compileError("could not parse component: " ++ field.name),
                    .size = 0,
                    .value = @field(implicits, field.name),
                };
            }
            return components;
        },
        else => @compileError("expected 'implicits' to be a struct literal"),
    }
}

fn structLen(@"struct": anytype) usize {
    return @typeInfo(@TypeOf(@"struct")).@"struct".fields.len;
}
