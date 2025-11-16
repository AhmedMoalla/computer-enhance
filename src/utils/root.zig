const std = @import("std");

pub const Args = struct {
    items: [][]const u8,
    positional: [][]const u8,
    named: std.StringHashMap(?[]const u8),

    pub fn pos(self: Args, index: usize) ?[]const u8 {
        if (index >= self.positional.len) {
            return null;
        }
        return self.positional[index];
    }

    pub fn get(self: Args, name: []const u8) ?[]const u8 {
        return self.named.get(name);
    }

    pub fn has(self: Args, name: []const u8) bool {
        return self.named.contains(name);
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.items.len == 0) {
            try writer.print("Args: none", .{});
            return;
        }

        try writer.print("Args:\n", .{});
        for (self.items, 0..) |item, i| {
            try writer.print("  [{d}] {s}\n", .{ i, item });
        }
        try writer.print("Positional:\n", .{});
        for (self.positional, 0..) |item, i| {
            try writer.print("  [{d}] {s}\n", .{ i, item });
        }

        if (self.named.count() > 0) {
            try writer.print("Named:\n", .{});
            var it = self.named.keyIterator();
            while (it.next()) |key| {
                try writer.print("  [{s}] {s}", .{ key.*, self.named.get(key.*).? orelse "true" });
            }
        }
    }
};

pub fn readAllArgsAlloc(allocator: std.mem.Allocator) !Args {
    var args_it = try std.process.argsWithAllocator(allocator);
    _ = args_it.skip(); // program name

    var args = try std.ArrayList([]const u8).initCapacity(allocator, 5);
    var positional = try std.ArrayList([]const u8).initCapacity(allocator, 5);
    var named = std.StringHashMap(?[]const u8).init(allocator);
    while (args_it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.indexOf(u8, arg, "=")) |equal_index| {
                const value = arg[equal_index + 1 ..];
                try named.put(arg[1..equal_index], if (value.len == 0) null else value);
            } else {
                try named.put(arg[1..], null);
            }
        } else {
            try positional.append(allocator, arg);
        }
        try args.append(allocator, arg);
    }

    return Args{
        .items = try args.toOwnedSlice(allocator),
        .positional = try positional.toOwnedSlice(allocator),
        .named = named,
    };
}

pub const FileReader = struct {
    file: std.fs.File,
    file_path: []const u8,
    file_name: []const u8,
    interface: *std.Io.Reader,

    buffer: []u8,
    file_reader: *std.fs.File.Reader,

    pub fn deinit(self: FileReader, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
        allocator.destroy(self.file_reader);
        allocator.free(self.file_path);
        self.file.close();
    }
};

pub fn openFileReaderAlloc(allocator: std.mem.Allocator, path: []const u8) !FileReader {
    const file = try std.fs.cwd().openFile(path, .{});
    const file_path = try std.fs.cwd().realpathAlloc(allocator, path);

    const buffer = try allocator.alloc(u8, 1024);
    var file_reader = try allocator.create(std.fs.File.Reader);
    file_reader.* = file.reader(buffer);
    return FileReader{
        .file = file,
        .file_path = file_path,
        .file_name = std.fs.path.basename(file_path),
        .interface = &file_reader.interface,
        .buffer = buffer,
        .file_reader = file_reader,
    };
}

pub const FileWriter = struct {
    file: std.fs.File,
    file_path: []const u8,
    file_name: []const u8,
    interface: *std.Io.Writer,

    buffer: []u8,
    file_writer: *std.fs.File.Writer,

    pub fn deinit(self: FileReader, allocator: std.mem.Allocator) void {
        allocator.free(self.buffer);
        allocator.destroy(self.file_reader);
        allocator.free(self.file_path);
        self.file.close();
    }
};

pub fn createFileWriterInDirAlloc(allocator: std.mem.Allocator, dir: std.fs.Dir, comptime path_fmt: []const u8, args: anytype) !FileWriter {
    const path = try std.fmt.allocPrint(allocator, path_fmt, args);
    defer allocator.free(path);
    const file = try dir.createFile(path, .{ .read = true });
    const file_path = try dir.realpathAlloc(allocator, path);

    const buffer = try allocator.alloc(u8, 1024);
    var file_writer = try allocator.create(std.fs.File.Writer);
    file_writer.* = file.writer(buffer);
    return FileWriter{
        .file = file,
        .file_path = file_path,
        .file_name = std.fs.path.basename(file_path),
        .interface = &file_writer.interface,
        .buffer = buffer,
        .file_writer = file_writer,
    };
}

pub fn createFileWriterAlloc(allocator: std.mem.Allocator, comptime path_fmt: []const u8, args: anytype) !FileWriter {
    return createFileWriterInDirAlloc(allocator, std.fs.cwd(), path_fmt, args);
}

pub fn toUpperAlloc(allocator: std.mem.Allocator, ascii_string: []const u8) []u8 {
    const output = allocator.alloc(u8, ascii_string.len) catch unreachable;
    for (ascii_string, 0..) |c, i| {
        output[i] = std.ascii.toUpper(c);
    }
    return output[0..ascii_string.len];
}

pub fn repeatCharAlloc(allocator: std.mem.Allocator, char: []const u8, n: usize) []u8 {
    const output = allocator.alloc(u8, char.len * n) catch unreachable;
    for (0..n) |i| {
        const start = i * char.len;
        @memcpy(output[start .. start + char.len], char);
    }
    return output;
}
