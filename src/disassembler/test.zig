const std = @import("std");
const utils = @import("utils");
const disassembler = @import("disassembler.zig");

test "disassemble input | nasm | compare nasm_out input" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input_dir = "computer_enhance/perfaware/part1/";
    const inputs = [_][]const u8{
        input_dir ++ "listing_0037_single_register_mov",
        input_dir ++ "listing_0038_many_register_mov",
        input_dir ++ "listing_0039_more_movs",
        input_dir ++ "listing_0040_challenge_movs",
        input_dir ++ "listing_0041_add_sub_cmp_jnz",
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    for (inputs) |in_file_path| {
        errdefer {
            std.testing.log_level = .debug;
            std.debug.print("comparison failed for file: {s}\n", .{in_file_path});
            std.testing.log_level = .warn;
        }

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
        const nasm_out_content = try nasm(allocator, out.file_path, tmp.dir);

        // Compare input with result
        in = try utils.openFileReaderAlloc(allocator, in_file_path);
        const stat = try in.file.stat();
        const in_content = try in.interface.readAlloc(allocator, stat.size);

        try std.testing.expectEqual(stat.size, nasm_out_content.len);
        try std.testing.expectEqualSlices(u8, in_content, nasm_out_content);
    }
}

fn nasm(allocator: std.mem.Allocator, asm_file_path: []const u8, output_dir: std.fs.Dir) ![]const u8 {
    const asm_file_name = std.fs.path.basename(asm_file_path);
    const nasm_out_file_path = try std.fs.path.join(allocator, &[_][]const u8{
        try output_dir.realpathAlloc(allocator, "."),
        std.fs.path.stem(asm_file_name),
    });

    var process = std.process.Child.init(&[_][]const u8{
        "nasm",
        "-o",
        nasm_out_file_path,
        asm_file_path,
    }, allocator);

    const term = try process.spawnAndWait();
    try std.testing.expectEqual(term.Exited, 0);

    const file_reader = try utils.openFileReaderAlloc(allocator, nasm_out_file_path);
    const stat = try file_reader.file.stat();
    const reader = file_reader.interface;
    return reader.readAlloc(allocator, stat.size);
}
