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
        input_dir ++ "listing_0053_add_loop_challenge",
        input_dir ++ "listing_0054_draw_rectangle",
        input_dir ++ "listing_0055_challenge_rectangle",
        input_dir ++ "listing_0056_estimating_cycles",
            // input_dir ++ "listing_0057_challenge_cycles",
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var show_clocks: bool = false;
    for (inputs, 0..) |in_file_path, i| {
        errdefer {
            std.testing.log_level = .debug;
            std.debug.print("comparison failed for file: {s}\n", .{in_file_path});
            std.testing.log_level = .warn;
        }

        // listings 48 and upwards print ip but the ones before do not
        State.print_instruction_pointer = i >= 5;

        // listings 56 and upwards show clocks but the ones before do not
        show_clocks = i >= 13;

        const in = try utils.openFileReaderAlloc(allocator, in_file_path);
        var allocating = try std.Io.Writer.Allocating.initCapacity(allocator, 1024 * 1024 * 5);
        defer allocating.deinit();

        var out = &allocating.writer;
        try out.print("--- test\\{s} execution ---\n", .{in.file_name});
        try emulator.execute(allocator, in.interface, out, .{ .show_clocks = show_clocks });
        try out.flush();
        const result_trimmed = std.mem.trimEnd(u8, out.buffered(), "\n");

        const expected_file_path = try std.fmt.allocPrint(allocator, "{s}.txt", .{in_file_path});
        const expected_in = try utils.openFileReaderAlloc(allocator, expected_file_path);
        const stat = try expected_in.file.stat();

        const expected = try expected_in.interface.readAlloc(allocator, stat.size);
        const expected_sanitized = try sanitizeExpected(allocator, expected, show_clocks);

        try std.testing.expectEqualSlices(u8, expected_sanitized, result_trimmed);
    }
}

fn sanitizeExpected(allocator: std.mem.Allocator, expected: []const u8, multiple_results: bool) ![]const u8 {
    var sanitized: []const u8 = try std.mem.replaceOwned(u8, allocator, expected, "\r", "");

    if (multiple_results) {
        sanitized = sanitized[header.len + 1 ..];
        var final_registers_reached = false;
        var it = std.mem.splitScalar(u8, sanitized, '\n');
        var char_count: usize = 0;
        while (it.next()) |line| {
            if (std.mem.containsAtLeast(u8, line, 1, "Final registers")) {
                final_registers_reached = true;
            }
            if (final_registers_reached and std.mem.eql(u8, "", line)) {
                break;
            }
            char_count += line.len + 1; // +1 for \n for every line
        }
        sanitized = sanitized[0..char_count];
    }

    return std.mem.trimEnd(u8, sanitized, "\n");
}

const header =
    \\**************
    \\**** 8086 ****
    \\**************
    \\
    \\WARNING: Clocks reported by this utility are strictly from the 8086 manual.
    \\They will be inaccurate, both because the manual clocks are estimates, and because
    \\some of the entries in the manual look highly suspicious and are probably typos.
    \\
;
