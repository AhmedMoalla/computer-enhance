const std = @import("std");
const utils = @import("utils");
const disassembler = @import("disassembler.zig");

test "nasm input.asm | disassemble input | nasm | compare nasm_out input" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input_dir = "computer_enhance/perfaware/part1/";
    const asm_inputs = [_][]const u8{
        input_dir ++ "listing_0037_single_register_mov.asm",
        input_dir ++ "listing_0038_many_register_mov.asm",
        input_dir ++ "listing_0039_more_movs.asm",
        input_dir ++ "listing_0040_challenge_movs.asm",
        input_dir ++ "listing_0041_add_sub_cmp_jnz.asm",
        input_dir ++ "listing_0042_completionist_decode.asm",
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    for (asm_inputs) |asm_in_file_path| {
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
