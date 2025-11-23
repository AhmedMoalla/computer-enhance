const std = @import("std");
const utils = @import("utils");
const emulator = @import("emulator.zig");
const disassembler = @import("disassembler.zig");
const State = @import("State.zig");

test "nasm input.asm | disassemble input | nasm | compare nasm_out input" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input_dir = "computer_enhance/perfaware/part1/";
    var asm_inputs = try std.ArrayList([]u8).initCapacity(allocator, 30);
    const idir = try std.fs.cwd().openDir(input_dir, .{ .iterate = true });
    var it = idir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        const extension = std.fs.path.extension(entry.name);
        if (std.mem.eql(u8, ".asm", extension)) {
            const file_path = try std.mem.concat(allocator, u8, &[_][]const u8{ input_dir, entry.name });
            try asm_inputs.append(allocator, file_path);
        }
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    for (asm_inputs.items) |asm_in_file_path| {
        errdefer {
            std.testing.log_level = .debug;
            std.debug.print("comparison failed for file: {s}\n", .{asm_in_file_path});
            std.testing.log_level = .warn;
        }

        // Assemble input .asm file with nasm
        const in_file = try nasm(allocator, asm_in_file_path, tmp.dir);
        const in_file_path = in_file.file_path;

        var in = try utils.openFileReaderAlloc(allocator, in_file_path);
        const out = try utils.createFileWriterInDirAlloc(
            allocator,
            tmp.dir,
            "{s}.asm",
            .{std.fs.path.basename(in_file_path)},
        );

        // Disassemble provided binary file
        try disassembler.disassemble(in.interface, out.interface);

        // Assemble result with nasm
        const nasm_out = try nasm(allocator, out.file_path, tmp.dir);

        // Compare input with result
        in = try utils.openFileReaderAlloc(allocator, in_file_path);
        const stat = try in.file.stat();
        const in_content = try in.interface.readAlloc(allocator, stat.size);

        try std.testing.expectEqual(nasm_out.file_content.len, stat.size);
        try std.testing.expectEqualSlices(u8, nasm_out.file_content, in_content);
    }
}

fn nasm(allocator: std.mem.Allocator, asm_file_path: []const u8, output_dir: std.fs.Dir) !NasmOutput {
    const asm_file_name = std.fs.path.basename(asm_file_path);
    const nasm_out_file_path = try std.fs.path.join(allocator, &[_][]const u8{
        try output_dir.realpathAlloc(allocator, "."),
        std.fs.path.stem(asm_file_name),
    });

    var process = std.process.Child.init(&[_][]const u8{
        "nasm",
        "-w-prefix-lock-xchg",
        "-o",
        nasm_out_file_path,
        asm_file_path,
    }, allocator);

    const term = try process.spawnAndWait();
    try std.testing.expectEqual(0, term.Exited);

    const file_reader = try utils.openFileReaderAlloc(allocator, nasm_out_file_path);
    const stat = try file_reader.file.stat();
    const reader = file_reader.interface;
    return NasmOutput{
        .file_path = nasm_out_file_path,
        .file_content = try reader.readAlloc(allocator, stat.size),
    };
}

const NasmOutput = struct {
    file_path: []const u8,
    file_content: []const u8,
};

test "exec | compare" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input_dir = "computer_enhance/perfaware/part1/";

    const inputs = [_][]const u8{
        input_dir ++ "listing_0043_immediate_movs",
        input_dir ++ "listing_0044_register_movs",
        input_dir ++ "listing_0045_challenge_register_movs",
        input_dir ++ "listing_0046_add_sub_cmp",
        input_dir ++ "listing_0047_challenge_flags",
        input_dir ++ "listing_0048_ip_register",
        input_dir ++ "listing_0049_conditional_jumps",
        input_dir ++ "listing_0050_challenge_jumps",
        input_dir ++ "listing_0051_memory_mov",
        input_dir ++ "listing_0052_memory_add_loop",
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    for (inputs, 0..) |in_file_path, i| {
        errdefer {
            std.testing.log_level = .debug;
            std.debug.print("comparison failed for file: {s}\n", .{in_file_path});
            std.testing.log_level = .warn;
        }

        // listings 48 and upwards prints ip but the ones before do not
        State.print_instruction_pointer = i >= 5;

        const in = try utils.openFileReaderAlloc(allocator, in_file_path);
        var buffer: [2048]u8 = undefined;
        var out = std.Io.Writer.fixed(&buffer);
        try out.print("--- test\\{s} execution ---\n", .{in.file_name});
        try emulator.execute(allocator, in.interface, &out);
        try out.flush();
        const result_trimmed = std.mem.trimEnd(u8, out.buffered(), "\n");

        const expected_file_path = try std.fmt.allocPrint(allocator, "{s}.txt", .{in_file_path});
        const expected_in = try utils.openFileReaderAlloc(allocator, expected_file_path);
        const stat = try expected_in.file.stat();

        const expected_crlf = try expected_in.interface.readAlloc(allocator, stat.size);
        const expected: []u8 = try std.mem.replaceOwned(u8, allocator, expected_crlf, "\r", "");
        const expected_trimmed = std.mem.trimEnd(u8, expected, "\n");

        try std.testing.expectEqualSlices(u8, expected_trimmed, result_trimmed);
    }
}
