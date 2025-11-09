const std = @import("std");

pub fn readAllArgsAlloc(allocator: std.mem.Allocator) ![][]const u8 {
    var args_it = try std.process.argsWithAllocator(allocator);
    _ = args_it.skip(); // program name

    var args = try std.ArrayList([]const u8).initCapacity(allocator, 5);
    while (args_it.next()) |arg| {
        const next_arg = try args.addOne(allocator);
        next_arg.* = arg;
    }
    return args.toOwnedSlice(allocator);
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

    const buffer = try allocator.alloc(u8, 1024);
    var file_reader = try allocator.create(std.fs.File.Reader);
    file_reader.* = file.reader(buffer);
    return FileReader{
        .file = file,
        .file_path = path,
        .file_name = std.fs.path.basename(path),
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

pub fn createFileWriterAlloc(allocator: std.mem.Allocator, comptime path_fmt: []const u8, args: anytype) !FileWriter {
    const path = try std.fmt.allocPrint(allocator, path_fmt, args);
    const file = try std.fs.cwd().createFile(path, .{ .read = true });

    const buffer = try allocator.alloc(u8, 1024);
    var file_writer = try allocator.create(std.fs.File.Writer);
    file_writer.* = file.writer(buffer);
    return FileWriter{
        .file = file,
        .file_path = path,
        .file_name = std.fs.path.basename(path),
        .interface = &file_writer.interface,
        .buffer = buffer,
        .file_writer = file_writer,
    };
}
