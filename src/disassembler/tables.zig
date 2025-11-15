const std = @import("std");
const formatters = @import("formatters.zig");
const decoder = @import("decoder.zig");

pub const Op = enum {
    mov,
    push,
    pop,
    xchg,
    in,
    out,
    xlat,
    lea,
    lds,
    les,
    lahf,
    sahf,
    pushf,
    popf,
    add,
    adc,
    inc,
    aaa,
    daa,
    sub,
    sbb,
    dec,
    neg,
    cmp,
    aas,
    das,
    mul,
    imul,
    aam,
    div,
    idiv,
    aad,
    cbw,
    cwd,
    not,
    shl,
    shr,
    sar,
    rol,
    ror,
    rcl,
    rcr,
    @"and",
    @"test",
    @"or",
    xor,
    rep,
    repne,
    movs,
    cmps,
    scas,
    lods,
    stos,
    call,
    jmp,
    ret,
    retf,
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
    int,
    int3,
    into,
    iret,
    clc,
    cmc,
    stc,
    cld,
    std,
    cli,
    sti,
    hlt,
    wait,
    esc,
    lock,
    segment,
};

pub const ComponentType = enum(usize) {
    bits,
    d,
    w,
    mod,
    reg,
    seg,
    rm,
    s,
    v,
    z,
    disp,
    disp_w,
    data,
    data_w,
    address,
    address_w,

    xxx, // 3-bit data chunks
    yyy, // 3-bit data chunks

    // Flags
    jump, // Flag the instruction as jump to be correctly formatted in nasm syntax
    disp_always, // Flag the instruction as always having displacement
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
    es,
    cs,
    ss,
    ds,
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
pub const ES: Register = .{ .name = "es", .type = .es, .width = 2, .offset = 0 };
pub const CS: Register = .{ .name = "cs", .type = .cs, .width = 2, .offset = 0 };
pub const SS: Register = .{ .name = "ss", .type = .ss, .width = 2, .offset = 0 };
pub const DS: Register = .{ .name = "ds", .type = .ds, .width = 2, .offset = 0 };

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

pub const segments: [4]Register = .{ ES, CS, SS, DS };

// TODO: Generate map at comptime which maps every combination to a layout based on this table
pub const encodings = [_]Encoding{
    e(.mov, "Register/memory to/from register", //
        .{ "100010", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.mov, "Immediate to register/memory", //
        .{ "1100011", .w, .mod, "000", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.mov, "Immediate to register", //
        .{ "1011", .w, .reg, .data, .data_w }, .{ .d = 1 }),
    e(.mov, "Memory to accumulator", //
        .{ "1010000", .w, .address, .address_w }, .{ .d = 1, .mod = 0, .reg = 0, .rm = 0b110 }),
    e(.mov, "Accumulator to memory", //
        .{ "1010001", .w, .address, .address_w }, .{ .mod = 0, .reg = 0, .rm = 0b110 }),
    e(.mov, "Register/memory to segment register", //
        .{ "10001110", .mod, "0", .seg, .rm, .disp, .disp_w }, .{ .w = 1 }),
    e(.mov, "Segment register to register/memory", //
        .{ "10001100", .mod, "0", .seg, .rm, .disp, .disp_w }, .{ .w = 1 }),

    e(.push, "Register/memory", //
        .{ "11111111", .mod, "110", .rm, .disp, .disp_w }, .{ .w = 1 }),
    e(.push, "Register", //
        .{ "01010", .reg }, .{ .d = 1, .w = 1 }),
    e(.push, "Segment register", //
        .{ "000", .seg, "110" }, .{ .d = 1, .w = 1 }),

    e(.pop, "Register/memory", //
        .{ "10001111", .mod, "000", .rm, .disp, .disp_w }, .{ .w = 1 }),
    e(.pop, "Register", //
        .{ "01011", .reg }, .{ .d = 1, .w = 1 }),
    e(.pop, "Segment register", //
        .{ "000", .seg, "111" }, .{ .d = 1, .w = 1 }),

    e(.xchg, "Register/memory with register", //
        .{ "1000011", .w, .mod, .reg, .rm, .disp, .disp_w }, .{ .d = 1 }),
    e(.xchg, "Register with accumulator", //
        .{ "10010", .reg }, .{ .mod = 0b11, .w = 1, .rm = 0 }),

    e(.in, "Fixed port", //
        .{ "1110010", .w, .data }, .{ .d = 1, .reg = 0 }),
    e(.in, "Variable port", //
        .{ "1110110", .w }, .{ .d = 1, .reg = 0, .mod = 0b11, .rm = 0b10 }),

    e(.out, "Fixed port", //
        .{ "1110011", .w, .data }, .{ .d = 1, .reg = 0 }),
    e(.out, "Variable port", //
        .{ "1110111", .w }, .{ .d = 1, .reg = 0, .mod = 0b11, .rm = 0b10 }),

    e(.xlat, "Translate byte to AL", .{"11010111"}, .{}),
    e(.lea, "Load EA to register", //
        .{ "10001101", .mod, .reg, .rm, .disp, .disp_w }, .{ .d = 1, .w = 1 }),
    e(.lds, "Load pointer to DS", //
        .{ "11000101", .mod, .reg, .rm, .disp, .disp_w }, .{ .d = 1, .w = 1 }),
    e(.les, "Load pointer to ES", //
        .{ "11000100", .mod, .reg, .rm, .disp, .disp_w }, .{ .d = 1, .w = 1 }),
    e(.lahf, "Load AH with flags", .{"10011111"}, .{}),
    e(.sahf, "Store AH with flags", .{"10011110"}, .{}),
    e(.pushf, "Push flags", .{"10011100"}, .{}),
    e(.popf, "Pop flags", .{"10011101"}, .{}),

    e(.add, "Reg/memory with register to either", //
        .{ "000000", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.add, "Immediate to register/memory", //
        .{ "100000", .s, .w, .mod, "000", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.add, "Immediate to accumulator", //
        .{ "0000010", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.adc, "Reg/memory with register to either", //
        .{ "000100", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.adc, "Immediate to register/memory", //
        .{ "100000", .s, .w, .mod, "010", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.adc, "Immediate to accumulator", //
        .{ "0001010", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.inc, "Register/memory", //
        .{ "1111111", .w, .mod, "000", .rm, .disp, .disp_w }, .{}),
    e(.inc, "Register", //
        .{ "01000", .reg }, .{ .d = 1, .w = 1 }),

    e(.aaa, "ASCII adjust for add", .{"00110111"}, .{}),
    e(.daa, "Decimal adjust for add", .{"00100111"}, .{}),

    e(.sub, "Reg/memory with register to either", //
        .{ "001010", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.sub, "Immediate to register/memory", //
        .{ "100000", .s, .w, .mod, "101", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.sub, "Immediate to accumulator", //
        .{ "0010110", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.sbb, "Reg/memory with register to either", //
        .{ "000110", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.sbb, "Immediate to register/memory", //
        .{ "100000", .s, .w, .mod, "011", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.sbb, "Immediate to accumulator", //
        .{ "0001110", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.dec, "Register/memory", //
        .{ "1111111", .w, .mod, "001", .rm, .disp, .disp_w }, .{}),
    e(.dec, "Register", //
        .{ "01001", .reg }, .{ .d = 1, .w = 1 }),

    e(.neg, "Change sign", //
        .{ "1111011", .w, .mod, "011", .rm, .disp, .disp_w }, .{}),

    e(.cmp, "Register/memory and register", //
        .{ "001110", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.cmp, "Immediate with register/memory", //
        .{ "100000", .s, .w, .mod, "111", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.cmp, "Immediate with accumulator", //
        .{ "0011110", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.aas, "ASCII adjust for substract", .{"00111111"}, .{}),
    e(.das, "Decimal adjust for substract", .{"00101111"}, .{}),

    e(.mul, "Multiply (unsigned)", //
        .{ "1111011", .w, .mod, "100", .rm, .disp, .disp_w }, .{ .s = 0 }),
    e(.imul, "Integer multiply (signed)", //
        .{ "1111011", .w, .mod, "101", .rm, .disp, .disp_w }, .{ .s = 1 }),
    e(.aam, "ASCII adjust for multiply", //
        .{ "11010100", "00001010" }, .{}),

    e(.div, "Divide (unsigned)", //
        .{ "1111011", .w, .mod, "110", .rm, .disp, .disp_w }, .{ .s = 0 }),
    e(.idiv, "Integer divide (signed)", //
        .{ "1111011", .w, .mod, "111", .rm, .disp, .disp_w }, .{ .s = 1 }),
    e(.aad, "ASCII adjust for divide", //
        .{ "11010101", "00001010" }, .{}),

    e(.cbw, "Convert byte to word", .{"10011000"}, .{}),
    e(.cwd, "Convert word to double word", .{"10011001"}, .{}),

    e(.not, "Invert", //
        .{ "1111011", .w, .mod, "010", .rm, .disp, .disp_w }, .{}),
    e(.shl, "Shift logical/arithmetic left (SAL)", //
        .{ "110100", .v, .w, .mod, "100", .rm, .disp, .disp_w }, .{}),
    e(.shr, "Shift logical right", //
        .{ "110100", .v, .w, .mod, "101", .rm, .disp, .disp_w }, .{}),
    e(.sar, "Shift arithmetic right", //
        .{ "110100", .v, .w, .mod, "111", .rm, .disp, .disp_w }, .{}),
    e(.rol, "Rotate left", //
        .{ "110100", .v, .w, .mod, "000", .rm, .disp, .disp_w }, .{}),
    e(.ror, "Rotate right", //
        .{ "110100", .v, .w, .mod, "001", .rm, .disp, .disp_w }, .{}),
    e(.rcl, "Rotete through carry flag left", //
        .{ "110100", .v, .w, .mod, "010", .rm, .disp, .disp_w }, .{}),
    e(.rcr, "Rotate through carry right", //
        .{ "110100", .v, .w, .mod, "011", .rm, .disp, .disp_w }, .{}),

    e(.@"and", "Reg/memory with register to either", //
        .{ "001000", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.@"and", "Immediate to register/memory", //
        .{ "1000000", .w, .mod, "100", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.@"and", "Immediate to accumulator", //
        .{ "0010010", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.@"test", "Reg/memory with register to either", //
        .{ "1000010", .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.@"test", "Immediate to register/memory", //
        .{ "1111011", .w, .mod, "000", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.@"test", "Immediate to accumulator", //
        .{ "1010100", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.@"or", "Reg/memory with register to either", //
        .{ "000010", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.@"or", "Immediate to register/memory", //
        .{ "1000000", .w, .mod, "001", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.@"or", "Immediate to accumulator", //
        .{ "0000110", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.xor, "Reg/memory with register to either", //
        .{ "001100", .d, .w, .mod, .reg, .rm, .disp, .disp_w }, .{}),
    e(.xor, "Immediate to register/memory", //
        .{ "1000000", .w, .mod, "110", .rm, .disp, .disp_w, .data, .data_w }, .{}),
    e(.xor, "Immediate to accumulator", //
        .{ "0011010", .w, .data, .data_w }, .{ .d = 1, .reg = 0 }),

    e(.rep, "Repeat while CX not zero", .{"11110011"}, .{}),
    e(.repne, "Repeat while CX is zero", .{"11110010"}, .{}),
    e(.movs, "Move byte/word", .{ "1010010", .w }, .{}),
    e(.cmps, "Compare byte/word", .{ "1010011", .w }, .{}),
    e(.scas, "Scan byte/word", .{ "1010111", .w }, .{}),
    e(.lods, "Load byte/word to AL/AX", .{ "1010110", .w }, .{}),
    e(.stos, "Store byte/word from AL/AX", .{ "1010101", .w }, .{}),

    e(.call, "Direct within segment", //
        .{ "11101000", .disp, .disp_w }, .{}),
    e(.call, "Indirect within segment", //
        .{ "11111111", .mod, "010", .rm, .disp, .disp_w }, .{ .w = 1 }),
    e(.call, "Direct intersegment", //
        .{ "10011010", .disp, .disp_w, .data, .data_w }, .{ .w = 1 }),
    e(.call, "Indirect intersegment", //
        .{ "11111111", .mod, "011", .rm, .disp, .disp_w }, .{ .w = 1 }),

    e(.jmp, "Direct within segment", //
        .{ "11101001", .disp, .disp_w }, .{}),
    e(.jmp, "Direct within segment-short", //
        .{ "11101011", .disp }, .{}),
    e(.jmp, "Indirect within segment", //
        .{ "11111111", .mod, "100", .rm, .disp, .disp_w }, .{ .w = 1 }),
    e(.jmp, "Direct intersegment", //
        .{ "11101010", .disp, .disp_w, .data, .data_w }, .{ .w = 1, .disp_always = 1 }),
    e(.jmp, "Indirect intersegment", //
        .{ "11111111", .mod, "101", .rm, .disp, .disp_w }, .{ .w = 1 }),

    e(.ret, "Within segment", .{"11000011"}, .{}),
    e(.ret, "Within segment adding immediate to SP", //
        .{ "11000010", .data, .data_w }, .{ .w = 1 }),
    e(.retf, "Intersegment (RET)", .{"11001011"}, .{}),
    e(.retf, "Intersegment adding immediate to SP (RET)", //
        .{ "11001010", .data, .data_w }, .{ .w = 1 }),

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

    e(.int, "Type specified", .{ "11001101", .data }, .{}),
    e(.int3, "Type 3", .{"11001100"}, .{}),

    e(.into, "Interrupt on overflow", .{"11001110"}, .{}),
    e(.iret, "Interrupt return", .{"11001111"}, .{}),

    e(.clc, "Clear carry", .{"11111000"}, .{}),
    e(.cmc, "Complement carry", .{"11110101"}, .{}),
    e(.stc, "Set carry", .{"11111001"}, .{}),
    e(.cld, "Clear direction", .{"11111100"}, .{}),
    e(.std, "Set direction", .{"11111101"}, .{}),
    e(.cli, "Clear interrupt", .{"11111010"}, .{}),
    e(.sti, "Set interrupt", .{"11111011"}, .{}),
    e(.hlt, "Halt", .{"11110100"}, .{}),
    e(.wait, "Wait", .{"10011011"}, .{}),
    e(.esc, "Escape (to external device)", //
        .{ "11011", .xxx, .mod, .yyy, .rm, .disp, .disp_w }, .{}),
    e(.lock, "Bus lock prefix", .{"11110000"}, .{}),
    e(.segment, "Override prefix", .{ "001", .seg, "110" }, .{ .d = 1 }),
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
    @setEvalBranchQuota(65000);
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
                    .d, .w, .s, .v, .z => 1,
                    .mod, .seg => 2,
                    .reg, .rm, .xxx, .yyy => 3,
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
