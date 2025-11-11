const std = @import("std");
const utils = @import("utils");
const tables = @import("tables.zig");
const decoder = @import("decoder.zig");

pub fn instruction(self: decoder.Instruction, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{s} {f}, {f}", .{ @tagName(self.op), self.dst, self.src });
}

pub fn operand(self: decoder.Operand, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (self) {
        .direct_address => |da| try writer.print("[{d}]", .{da}),
        .effective_address_calculation => |eac| {
            try writer.print("[{s}", .{eac.reg1.name});
            if (eac.reg2) |reg2| {
                try writer.print(" + {s}", .{reg2.name});
            }
            if (eac.displacement > 0) {
                try writer.print(" + {}", .{@abs(eac.displacement)});
            } else if (eac.displacement < 0) {
                try writer.print(" - {}", .{@abs(eac.displacement)});
            }
            try writer.print("]", .{});
        },
        .register => |reg| try writer.print("{s}", .{reg.name}),
        .immediate => |imm| {
            if (imm.wide) |wide| {
                try writer.print("{s} ", .{if (wide) "word" else "byte"});
            }
            try writer.print("{d}", .{imm.value});
        },
        .invalid => try writer.print("INVALID", .{}),
    }
}

pub fn encoding(self: tables.Encoding, writer: *std.Io.Writer) std.Io.Writer.Error!void {
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
        const left_spaces = utils.repeatCharAlloc(allocator, " ", half_n_spaces + (n_spaces % 2));
        const right_spaces = utils.repeatCharAlloc(allocator, " ", half_n_spaces);

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
            const left_dashes = utils.repeatCharAlloc(allocator, "─", half_n_dashes + (n_dashes % 2));
            const right_dashes = utils.repeatCharAlloc(allocator, "─", half_n_dashes);
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
