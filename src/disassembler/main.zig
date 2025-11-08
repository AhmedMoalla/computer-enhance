const std = @import("std");

const regs: [8][2][]const u8 = [_][2][]const u8{
    [_][]const u8{ "al", "ax" },
    [_][]const u8{ "cl", "cx" },
    [_][]const u8{ "dl", "dx" },
    [_][]const u8{ "bl", "bx" },
    [_][]const u8{ "ah", "sp" },
    [_][]const u8{ "ch", "bp" },
    [_][]const u8{ "dh", "si" },
    [_][]const u8{ "bh", "di" },
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var args_it = try std.process.argsWithAllocator(allocator);
    _ = args_it.skip(); // program name
    const bin_file_path = args_it.next() orelse return error.FileNotFound;

    const bin_file = try std.fs.cwd().openFile(bin_file_path, .{});
    var reader_buffer: [1024]u8 = undefined;
    var file_reader = bin_file.reader(&reader_buffer);
    const reader = &file_reader.interface;

    const asm_file = try std.fs.cwd().createFile(
        try std.fmt.allocPrint(allocator, "{s}.asm", .{std.fs.path.basename(bin_file_path)}),
        .{ .read = true },
    );
    var writer_buffer: [1024]u8 = undefined;
    var file_writer = asm_file.writer(&writer_buffer);
    const writer = &file_writer.interface;

    try writer.print("; {s} disassembly:\n", .{std.fs.path.basename(bin_file_path)});
    try disassemble(reader, writer);

    try writer.flush();
}

fn disassemble(reader: *std.Io.Reader, writer: *std.Io.Writer) !void {
    try writer.print("bits 16\n", .{});
    while (true) {
        const byte = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        const opcode = byte >> 2;
        if (opcode == 0b100010) {
            const next_byte = try reader.takeByte();

            const d = byte & 0b10;
            const w = byte & 0b1;
            const mod = next_byte >> 6;
            const reg = (next_byte >> 3) & 0b111;
            const rm = next_byte & 0b111;

            if (mod == 0b11) {
                const src = if (d == 0) regs[reg][w] else regs[rm][w];
                const dst = if (d == 0) regs[rm][w] else regs[reg][w];
                try writer.print("mov {s}, {s}\n", .{ dst, src });
            }
        }
    }
}

test "disassemble input | nasm | compare nasm_out input" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input_dir = "computer_enhance/perfaware/part1/";
    const inputs = [_][]const u8{
        input_dir ++ "listing_0037_single_register_mov",
        input_dir ++ "listing_0038_many_register_mov",
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    for (inputs) |bin_file_path| {
        errdefer {
            std.testing.log_level = .debug;
            std.debug.print("comparison failed for file: {s}\n", .{bin_file_path});
            std.testing.log_level = .warn;
        }

        const bin_file = try std.fs.cwd().openFile(bin_file_path, .{});
        var reader_buffer: [1024]u8 = undefined;
        var file_reader = bin_file.reader(&reader_buffer);
        const reader = &file_reader.interface;

        const asm_file_name = try std.fmt.allocPrint(allocator, "{s}.asm", .{std.fs.path.basename(bin_file_path)});
        const asm_file = try tmp.dir.createFile(
            asm_file_name,
            .{ .read = true },
        );
        const asm_file_path = try tmp.dir.realpathAlloc(allocator, asm_file_name);

        var writer_buffer: [1024]u8 = undefined;
        var file_writer = asm_file.writer(&writer_buffer);
        const writer = &file_writer.interface;

        // Disassemble provided binary file
        try disassemble(reader, writer);
        try writer.flush();

        // Assemble result with nasm
        const nasm_out_file = try tmp.dir.createFile(
            std.fs.path.basename(bin_file_path),
            .{ .read = true },
        );
        const nasm_out_file_path = try tmp.dir.realpathAlloc(allocator, std.fs.path.basename(bin_file_path));
        var process = std.process.Child.init(&[_][]const u8{
            "nasm",
            "-o",
            nasm_out_file_path,
            asm_file_path,
        }, allocator);

        const term = try process.spawnAndWait();
        try std.testing.expectEqual(term.Exited, 0);

        // Compare input with result
        var nasm_reader_buffer: [1024]u8 = undefined;
        const out_reader = nasm_out_file.reader(&nasm_reader_buffer);
        const nasm_out_stat = try nasm_out_file.stat();
        const out_reader_iface = @constCast(&out_reader.interface);
        const nasm_out_content = try out_reader_iface.readAlloc(allocator, nasm_out_stat.size);

        const expected_reader = bin_file.reader(&.{});
        const expected_stat = try bin_file.stat();
        const expected_reader_iface = @constCast(&expected_reader.interface);
        const expected_content = try expected_reader_iface.readAlloc(allocator, expected_stat.size);

        try std.testing.expectEqual(expected_stat.size, nasm_out_stat.size);
        try std.testing.expectEqualSlices(u8, expected_content, nasm_out_content);
    }
}
