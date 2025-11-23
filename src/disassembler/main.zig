const std = @import("std");
const utils = @import("utils");
const emulator = @import("emulator.zig");
const disassembler = @import("disassembler.zig");

const log = std.log;

pub const std_options: std.Options = .{
    .log_level = .info,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .disasm, .level = .info },
        .{ .scope = .decoder, .level = .info },
    },
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const args = try utils.readAllArgsAlloc(allocator);
    log.debug("{f}\n", .{args});
    const bin_file_path = args.pos(0) orelse return error.FileNotFound;

    const in = try utils.openFileReaderAlloc(allocator, bin_file_path);

    if (args.has("exec")) {
        var buffer: [1024]u8 = undefined;
        const stdout = std.fs.File.stdout();
        var writer = stdout.writer(&buffer);
        const out = &writer.interface;

        try emulator.execute(allocator, in.interface, out);
        return;
    }

    const out = try utils.createFileWriterAlloc(
        allocator,
        "{s}.asm",
        .{std.fs.path.basename(bin_file_path)},
    );

    try out.interface.print("; {s} disassembly:\n", .{std.fs.path.basename(bin_file_path)});
    try disassembler.disassemble(in.interface, out.interface);
}

test {
    _ = @import("test.zig");
}
