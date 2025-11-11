const std = @import("std");
const utils = @import("utils");
const decoder = @import("decoder.zig");

pub const Op = enum {
    mov,
};

pub const ComponentType = enum(usize) {
    bits,
    d,
    w,
    mod,
    reg,
    rm,
    disp,
    disp_w,
    data,
    data_w,
    address,
    address_w,
};

pub const ComponentLayout = struct {
    type: ComponentType,
    size: u8,
    value: u8 = 0,
};

pub const TableEntry = struct {
    op: Op,
    name: []const u8 = "",
    layout: []const ComponentLayout,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var buffer: [1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const allocator = fba.allocator();

        try writer.print("\n", .{});

        const layout = self.layout;
        const width, const n_bytes, const n_implicit = blk: {
            var implicit_label_printed: bool = false;
            var n_implicit: usize = 0;
            var width_acc: usize = layout.len + 1; // separators
            var bit_size_acc: usize = 0;
            for (layout) |component| {
                if (component.size == 0) {
                    if (!implicit_label_printed) {
                        try writer.print("IMPLICIT: ", .{});
                        implicit_label_printed = true;
                    }
                    try writer.print("{s}={b} ", .{ @tagName(component.type), component.value });
                    n_implicit += 1;
                    continue;
                }
                width_acc += switch (component.type) { // text + spaces
                    .bits => (component.size * 2) + 1,
                    .d, .w => 3,
                    .mod => 5,
                    .reg, .rm => 7,
                    .disp, .disp_w, .data, .data_w, .address, .address_w => 17,
                };
                bit_size_acc += component.size;
            }

            // width_acc - n_implicit: Remove separator for implicit components
            break :blk .{ width_acc - n_implicit, bit_size_acc / 8, n_implicit };
        };

        if (n_implicit > 0) {
            try writer.print("\n", .{});
        }

        // Determine byte width
        var byte_widths: []usize = allocator.alloc(usize, n_bytes) catch unreachable;
        @memset(byte_widths, 0);
        {
            var component_index: usize = 0;
            for (0..n_bytes) |i| {
                var remaining: usize = 8;
                for (layout[component_index..]) |component| {
                    byte_widths[i] += switch (component.type) { // text + spaces
                        .bits => (component.size * 2) + 1,
                        .d, .w => 3,
                        .mod => 5,
                        .reg, .rm => 7,
                        .disp, .disp_w, .data, .data_w, .address, .address_w => 17,
                    };
                    byte_widths[i] += 1; // One separator per component
                    component_index += 1;
                    remaining -= component.size;
                    if (remaining == 0) break;
                }

                byte_widths[i] -= 1; // Last component has no separator due to byte boundary
            }
        }

        // =========== Top Border ===========
        {
            try writer.print("┏", .{});
            for (0..(width - 2)) |_| { // -2 is ┏ and ┓
                try writer.print("━", .{});
            }
            try writer.print("┓\n", .{});
        }

        // =========== First Section ===========
        {
            const op_name = utils.toUpperAlloc(allocator, @tagName(self.op));
            const name = self.name;
            // -2: is for starting ┃ and ending ┃ and -2: is for ": " between op_name and title
            const n_spaces: usize = width - op_name.len - name.len - 2 - 2;
            const half_n_spaces = n_spaces / 2;
            const left_spaces = utils.repeatCharAlloc(allocator, ' ', half_n_spaces + (n_spaces % 2));
            const right_spaces = utils.repeatCharAlloc(allocator, ' ', half_n_spaces);

            try writer.print("┃", .{});
            try writer.print("{s}{s}: {s}{s}", .{ left_spaces, op_name, name, right_spaces });
            try writer.print("┃\n", .{});
        }

        // =========== First-Second Separator ===========
        {
            try writer.print("┣", .{});
            for (byte_widths, 0..) |w, i| {
                for (0..w) |_| {
                    try writer.print("━", .{});
                }
                if (i < byte_widths.len - 1) {
                    try writer.print("┳", .{});
                }
            }
            try writer.print("┫\n", .{});
        }

        // =========== Second Section Header ===========
        {
            try writer.print("┃", .{});
            for (byte_widths, 0..) |w, i| {
                // -6: is for 'BYTE n' and -2: is for < and >
                const n_dashes: usize = w - 6 - 2;
                const half_n_dashes = n_dashes / 2;
                const left_dashes = utils.repeatCharAlloc(allocator, '-', half_n_dashes + (n_dashes % 2));
                const right_dashes = utils.repeatCharAlloc(allocator, '-', half_n_dashes);
                try writer.print("<{s}BYTE {d}{s}>", .{ left_dashes, i + 1, right_dashes });
                if (i < byte_widths.len - 1) {
                    try writer.print("┃", .{});
                }
            }
            try writer.print("┃\n", .{});
        }

        // =========== Second Section Indices ===========
        {
            var remaining: usize = 8;
            try writer.print("┃", .{});
            for (layout) |component| {
                if (component.size == 0) continue;
                for (0..component.size) |_| {
                    remaining -= 1;
                    try writer.print(" {d}", .{remaining});
                }
                try writer.print(" ", .{});

                if (remaining == 0) {
                    remaining = 8;
                    try writer.print("┃", .{});
                } else {
                    try writer.print(" ", .{});
                }
            }
            try writer.print("\n", .{});
        }

        // =========== Second-Third Separator ===========
        {
            var remaining: usize = 8;
            try writer.print("┣", .{});
            for (layout, 0..) |component, i| {
                if (component.size == 0) continue;
                remaining -= component.size;
                const n_dashes = switch (component.type) { // text + spaces
                    .bits => (component.size * 2) + 1,
                    .d, .w => 3,
                    .mod => 5,
                    .reg, .rm => 7,
                    .disp, .disp_w, .data, .data_w, .address, .address_w => 17,
                };
                for (0..n_dashes) |_| {
                    try writer.print("━", .{});
                }

                if (remaining == 0) {
                    remaining = 8;
                    if (i < layout.len - n_implicit - 1) {
                        try writer.print("╋", .{});
                    } else {
                        try writer.print("┫", .{});
                    }
                } else {
                    try writer.print("┯", .{});
                }
            }
            try writer.print("\n", .{});
        }

        // =========== Third Section ===========
        {
            var remaining: usize = 8;
            try writer.print("┃", .{});
            for (layout) |component| {
                if (component.size == 0) continue;
                remaining -= component.size;
                switch (component.type) {
                    .bits => {
                        for (0..component.size) |i| {
                            const shift: u3 = @intCast(i);
                            try writer.print(" {d}", .{(component.value >> shift) & 0b1});
                        }
                    },
                    .d, .w, .mod => try writer.print(" {s}", .{@tagName(component.type)}),
                    .reg => try writer.print("  {s} ", .{@tagName(component.type)}),
                    .rm => try writer.print("  r/m ", .{}),
                    .disp => try writer.print("     disp-lo    ", .{}),
                    .disp_w => try writer.print("     disp-hi    ", .{}),
                    .data => try writer.print("       data     ", .{}),
                    .data_w => try writer.print("   data if w=1  ", .{}),
                    .address => try writer.print("     addr-lo    ", .{}),
                    .address_w => try writer.print("     addr-hi    ", .{}),
                }

                if (remaining == 0) {
                    remaining = 8;
                    try writer.print(" ┃", .{});
                } else {
                    try writer.print(" ┊", .{});
                }
            }
            try writer.print("\n", .{});
        }

        // =========== Bottom Border ===========
        {
            var remaining: usize = 8;
            try writer.print("┗", .{});
            for (layout, 0..) |component, i| {
                if (component.size == 0) continue;
                remaining -= component.size;
                const n_dashes = switch (component.type) { // text + spaces
                    .bits => (component.size * 2) + 1,
                    .d, .w => 3,
                    .mod => 5,
                    .reg, .rm => 7,
                    .disp, .disp_w, .data, .data_w, .address, .address_w => 17,
                };
                for (0..n_dashes) |_| {
                    try writer.print("━", .{});
                }

                if (remaining == 0) {
                    remaining = 8;
                    if (i < layout.len - n_implicit - 1) {
                        try writer.print("┻", .{});
                    } else {
                        try writer.print("┛", .{});
                    }
                } else {
                    try writer.print("┷", .{});
                }
            }
        }
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
pub const encodings = [_]TableEntry{
    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃                     MOV: Register/memory to/from register                     ┃
    // ┣━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━┫
    // ┃<-------BYTE 1------>┃<-------BYTE 2------>┃<-----BYTE 3---->┃<-----BYTE 4---->┃
    // ┃ 7 6 5 4 3 2   1   0 ┃ 7 6   5 4 3   2 1 0 ┃ 7 6 5 4 3 2 1 0 ┃ 7 6 5 4 3 2 1 0 ┃
    // ┣━━━━━━━━━━━━━┯━━━┯━━━╋━━━━━┯━━━━━━━┯━━━━━━━╋━━━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━┫
    // ┃ 1 0 0 0 1 0 ┊ d ┊ w ┃ mod ┊  reg  ┊  r/m  ┃     disp-lo     ┃     disp-hi     ┃
    // ┗━━━━━━━━━━━━━┷━━━┷━━━┻━━━━━┷━━━━━━━┷━━━━━━━┻━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━┛
    .{
        .op = .mov,
        .name = "Register/memory to/from register",
        .layout = &.{
            .{ .type = .bits, .size = 6, .value = 0b100010 },
            .{ .type = .d, .size = 1 },
            .{ .type = .w, .size = 1 },
            .{ .type = .mod, .size = 2 },
            .{ .type = .reg, .size = 3 },
            .{ .type = .rm, .size = 3 },
            .{ .type = .disp, .size = 8 },
            .{ .type = .disp_w, .size = 8 },
        },
    },
    .{
        .op = .mov,
        .name = "Immediate to register/memory",
        .layout = &.{
            .{ .type = .bits, .size = 7, .value = 0b1100011 },
            .{ .type = .w, .size = 1 },
            .{ .type = .mod, .size = 2 },
            .{ .type = .bits, .size = 3, .value = 0b000 },
            .{ .type = .rm, .size = 3 },
            .{ .type = .disp, .size = 8 },
            .{ .type = .disp_w, .size = 8 },
            .{ .type = .data, .size = 8 },
            .{ .type = .data_w, .size = 8 },
            .{ .type = .d, .size = 0, .value = 0 },
        },
    },
    .{
        .op = .mov,
        .name = "Immediate to register",
        .layout = &.{
            .{ .type = .bits, .size = 4, .value = 0b1011 },
            .{ .type = .w, .size = 1 },
            .{ .type = .reg, .size = 3 },
            .{ .type = .data, .size = 8 },
            .{ .type = .data_w, .size = 8 },
            .{ .type = .d, .size = 0, .value = 1 },
        },
    },
    .{
        .op = .mov,
        .name = "Memory to accumulator",
        .layout = &.{
            .{ .type = .bits, .size = 7, .value = 0b1010000 },
            .{ .type = .w, .size = 1 },
            .{ .type = .address, .size = 8 },
            .{ .type = .address_w, .size = 8 },
            .{ .type = .d, .size = 0, .value = 1 },
            .{ .type = .mod, .size = 0, .value = 0 },
            .{ .type = .reg, .size = 0, .value = 0 },
            .{ .type = .rm, .size = 0, .value = 0b110 },
        },
    },
    .{
        .op = .mov,
        .name = "Accumulator to memory",
        .layout = &.{
            .{ .type = .bits, .size = 7, .value = 0b1010001 },
            .{ .type = .w, .size = 1 },
            .{ .type = .address, .size = 8 },
            .{ .type = .address_w, .size = 8 },
            .{ .type = .d, .size = 0, .value = 0 },
            .{ .type = .mod, .size = 0, .value = 0 },
            .{ .type = .reg, .size = 0, .value = 0 },
            .{ .type = .rm, .size = 0, .value = 0b110 },
        },
    },
};
