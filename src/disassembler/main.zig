const std = @import("std");
const utils = @import("utils");
const disassembler = @import("disassembler.zig");

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
    if (args.len == 0) return error.FileNotFound;
    const bin_file_path = args[0];

    const in = try utils.openFileReaderAlloc(allocator, bin_file_path);
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
