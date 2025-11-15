const std = @import("std");
const utils = @import("utils");
const tables = @import("tables.zig");
const decoder = @import("decoder.zig");

pub fn instruction(self: decoder.Instruction, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    if (self.prefix) |prefix| {
        try writer.print("{t} ", .{prefix});
    }
    try writer.print("{t}", .{self.op});
    if (self.prefix == .rep or self.prefix == .repne) {
        const w = self.components.get(.w) == 1;
        try writer.print("{s}", .{if (w) "w" else "b"});
    }
    if (self.lhs) |lhs| {
        try writer.print(" ", .{});
        try formatOperand(self, lhs, writer);
    }
    if (self.rhs) |rhs| {
        try writer.print(", ", .{});
        try formatOperand(self, rhs, writer);
    }
}

fn formatOperand(instr: decoder.Instruction, operand: decoder.Operand, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (operand) {
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
            if (imm.jump) {
                const sign = if (imm.value >= 0) "+" else "-";
                const size_i32: i32 = @intCast(instr.size);
                try writer.print("${s}{d}", .{ sign, @abs(imm.value + size_i32) });
            } else {
                try writer.print("{d}", .{imm.value});
            }
        },
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
            width_acc += componentWidth(component);
            bit_size_acc += component.size;
        }

        // width_acc - n_implicit: Remove separator for implicit components
        break :blk .{ width_acc - n_implicit, bit_size_acc / 8, n_implicit };
    };

    if (n_implicit > 0) {
        try writer.print("\n", .{});
    }

    const op_name = utils.toUpperAlloc(allocator, @tagName(self.op));
    const name = self.name;
    const title_width = op_name.len + name.len + 2; // +2: is for ": " between op_name and title
    const title_padded_width = title_width + 2; // +2: is for padding (1 space before and after title)
    const title_too_big = title_padded_width > width - 2; // -2: is for starting ┃ and ending ┃
    var title_padding: usize = 0;
    if (title_too_big) {
        if (title_padded_width < width) {
            title_padding = width - title_padded_width;
        } else {
            title_padding = (title_padded_width - width) + 2; // +2: is for starting ┃ and ending ┃
        }
    }

    // =========== Top Border ===========
    {
        try writer.print("┏", .{});
        for (0..(width - 2)) |_| { // -2 is ┏ and ┓
            try writer.print("━", .{});
        }
        if (title_too_big) {
            for (0..title_padding) |_| {
                try writer.print("━", .{});
            }
        }
        try writer.print("┓\n", .{});
    }

    // =========== First Section ===========
    {
        var left_spaces: []const u8 = " ";
        var right_spaces: []const u8 = " ";
        if (!title_too_big) {
            // -2: is for starting ┃ and ending ┃ and -2: is for ": " between op_name and title
            const n_spaces: usize = width - op_name.len - name.len - 2 - 2;
            const half_n_spaces = n_spaces / 2;
            left_spaces = utils.repeatCharAlloc(allocator, " ", half_n_spaces + (n_spaces % 2));
            right_spaces = utils.repeatCharAlloc(allocator, " ", half_n_spaces);
        }

        try writer.print("┃", .{});
        try writer.print("{s}{s}: {s}{s}", .{ left_spaces, op_name, name, right_spaces });
        try writer.print("┃\n", .{});
    }

    // =========== First-Second Separator ===========
    {
        try writer.print("┣", .{});
        var remaining: usize = 8;
        for (layout, 0..) |component, i| {
            if (component.size == 0) continue;
            remaining -= component.size;
            for (0..componentWidth(component)) |_| {
                try writer.print("━", .{});
            }
            if (remaining == 0) {
                remaining = 8;
                if (i < layout.len - 1) {
                    try writer.print("┳", .{});
                }
            } else {
                try writer.print("━", .{});
            }
        }
        if (title_too_big) {
            try writer.print("┳", .{});
            for (0..title_padding - 1) |_| {
                try writer.print("┳", .{});
            }
            try writer.print("┫\n", .{});
        } else {
            try writer.print("┫\n", .{});
        }
    }

    // =========== Second Section Header ===========
    {
        var byte_widths: []usize = allocator.alloc(usize, n_bytes) catch unreachable;
        @memset(byte_widths, 0);
        {
            var component_index: usize = 0;
            for (0..n_bytes) |i| {
                var remaining: usize = 8;
                for (layout[component_index..]) |component| {
                    byte_widths[i] += componentWidth(component);
                    if (component.size > 0) {
                        byte_widths[i] += 1; // One separator per component
                    }
                    component_index += 1;
                    remaining -= component.size;
                    if (remaining == 0) break;
                }

                byte_widths[i] -= 1; // Last component has no separator due to byte boundary
            }
        }

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

        if (title_too_big) {
            try writer.print("┣", .{});
            for (0..title_padding - 1) |_| {
                try writer.print("╋", .{});
            }
            try writer.print("┫\n", .{});
        } else {
            try writer.print("┃\n", .{});
        }
    }

    // =========== Second Section Indices ===========
    {
        var remaining: usize = 8;
        try writer.print("┃", .{});
        for (layout, 0..) |component, i| {
            if (component.size == 0) continue;
            for (0..component.size) |_| {
                remaining -= 1;
                try writer.print(" {d}", .{remaining});
            }
            try writer.print(" ", .{});

            if (remaining == 0) {
                remaining = 8;
                if (i < layout.len - 1) {
                    try writer.print("┃", .{});
                }
            } else {
                try writer.print(" ", .{});
            }
        }

        if (title_too_big) {
            try writer.print("┣", .{});
            for (0..title_padding - 1) |_| {
                try writer.print("╋", .{});
            }
            try writer.print("┫\n", .{});
        } else {
            try writer.print("┃\n", .{});
        }
    }

    // =========== Second-Third Separator ===========
    {
        var remaining: usize = 8;
        try writer.print("┣", .{});
        for (layout, 0..) |component, i| {
            if (component.size == 0) continue;
            remaining -= component.size;
            const n_dashes = componentWidth(component);
            for (0..n_dashes) |_| {
                try writer.print("━", .{});
            }
            if (remaining == 0) {
                remaining = 8;
                if (i < layout.len - 1) {
                    try writer.print("╋", .{});
                }
            } else {
                try writer.print("┯", .{});
            }
        }

        if (title_too_big) {
            try writer.print("╋", .{});
            for (0..title_padding - 1) |_| {
                try writer.print("╋", .{});
            }
            try writer.print("┫\n", .{});
        } else {
            try writer.print("┫\n", .{});
        }
    }

    // =========== Third Section ===========
    {
        var remaining: usize = 8;
        try writer.print("┃", .{});
        for (layout, 0..) |component, i| {
            if (component.size == 0) continue;
            remaining -= component.size;
            switch (component.type) {
                .bits => {
                    var j: u32 = component.size - 1;
                    while (j < component.size) : (j -%= 1) {
                        const shift: u3 = @intCast(j);
                        try writer.print(" {d}", .{(component.value >> shift) & 0b1});
                    }
                },
                .d, .w, .s, .v, .z, .mod, .seg => try writer.print(" {s}", .{@tagName(component.type)}),
                .reg => try writer.print("  {s} ", .{@tagName(component.type)}),
                .rm => try writer.print("  r/m ", .{}),
                .disp => try writer.print("     disp-lo    ", .{}),
                .disp_w => try writer.print("     disp-hi    ", .{}),
                .data => try writer.print("       data     ", .{}),
                .data_w => try writer.print("   data if w=1  ", .{}),
                .address => try writer.print("     addr-lo    ", .{}),
                .address_w => try writer.print("     addr-hi    ", .{}),
                .jump => {},
            }

            if (remaining == 0) {
                remaining = 8;
                if (i < layout.len - 1) {
                    try writer.print(" ┃", .{});
                }
            } else {
                try writer.print(" ┊", .{});
            }
        }

        if (title_too_big) {
            try writer.print(" ┣", .{});
            for (0..title_padding - 1) |_| {
                try writer.print("╋", .{});
            }
            try writer.print("┫\n", .{});
        } else {
            try writer.print(" ┃\n", .{});
        }
    }

    // =========== Bottom Border ===========
    {
        var remaining: usize = 8;
        try writer.print("┗", .{});
        for (layout, 0..) |component, i| {
            if (component.size == 0) continue;
            remaining -= component.size;
            const n_dashes = componentWidth(component);
            for (0..n_dashes) |_| {
                try writer.print("━", .{});
            }

            if (remaining == 0) {
                remaining = 8;
                if (i < layout.len - 1) {
                    try writer.print("┻", .{});
                }
            } else {
                try writer.print("┷", .{});
            }
        }

        if (title_too_big) {
            try writer.print("┻", .{});
            for (0..title_padding - 1) |_| {
                try writer.print("┻", .{});
            }
            try writer.print("┛", .{});
        } else {
            try writer.print("┛", .{});
        }
    }
}

fn componentWidth(component: tables.EncodingComponent) usize {
    if (component.size == 0) return 0;
    return switch (component.type) { // text + spaces
        .bits => (component.size * 2) + 1,
        .d, .w, .s, .v, .z => 3,
        .mod, .seg => 5,
        .reg, .rm => 7,
        .disp, .disp_w, .data, .data_w, .address, .address_w => 17,
        .jump => 0,
    };
}
