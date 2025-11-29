const std = @import("std");

const utils = @import("utils");
const haversine = @import("haversine.zig");

const maxX: f64 = 180;
const minX: f64 = -maxX;
const maxY: f64 = 90;
const minY: f64 = -maxY;

pub fn run() !noreturn {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const args = try utils.readAllArgsAlloc(allocator);
    if (args.items.len < 2) {
        std.log.err("usage: {s} [random seed] [number of coordinate pairs to generate]", .{args.program_name});
        std.process.exit(1);
    }

    const prng, const seed = blk: {
        const arg0 = args.pos(0).?;
        const seed = std.fmt.parseUnsigned(u64, arg0, 10) catch {
            std.log.err("invalid seed: {s}", .{arg0});
            std.process.exit(1);
        };
        var prng = std.Random.DefaultPrng.init(seed);
        break :blk .{ prng.random(), seed };
    };
    const arg1 = args.pos(1).?;
    const npairs = std.fmt.parseUnsigned(u64, arg1, 10) catch {
        std.log.err("invalid npairs: {s}", .{arg1});
        std.process.exit(1);
    };

    const answers_file = try utils.createFileWriterAlloc(allocator, "answers_{d}.f64", .{npairs});
    var out_answers = &answers_file.file_writer.interface;

    const data_file = try utils.createFileWriterAlloc(allocator, "data_{d}.json", .{npairs});
    var out = &data_file.file_writer.interface;
    var json = std.json.Stringify{ .writer = out };

    var x_center: f64 = 0;
    var y_center: f64 = 0;
    var x_radius: f64 = maxX;
    var y_radius: f64 = maxY;

    var cluster_count_left: u64 = 0;
    const cluster_count_max: u64 = 1 + (npairs / 64);

    var sum: f64 = 0;
    const sum_coef = 1.0 / @as(f64, @floatFromInt(npairs));

    try json.beginObject();
    try json.objectField("pairs");
    try json.beginArray();
    for (0..npairs) |_| {
        if (cluster_count_left == 0) {
            cluster_count_left = cluster_count_max;
            x_center = randomBetween(prng, minX, maxX);
            y_center = randomBetween(prng, minY, maxY);
            x_radius = randomBetween(prng, 0, maxX);
            y_radius = randomBetween(prng, 0, maxY);
        }
        cluster_count_left -= 1;

        const x0: f64 = randomDegree(prng, x_center, x_radius, minX, maxX);
        const y0: f64 = randomDegree(prng, y_center, y_radius, minY, maxY);
        const x1: f64 = randomDegree(prng, x_center, x_radius, minX, maxX);
        const y1: f64 = randomDegree(prng, y_center, y_radius, minY, maxY);

        try json.beginObject();
        try json.objectField("x0");
        try json.write(x0);
        try json.objectField("y0");
        try json.write(y0);
        try json.objectField("x1");
        try json.write(x1);
        try json.objectField("y1");
        try json.write(y1);
        try json.endObject();

        const distance = haversine.reference(x0, y0, x1, y1);
        sum += sum_coef * distance;

        _ = try out_answers.write(std.mem.asBytes(&distance));
    }
    try json.endArray();
    try json.endObject();

    _ = try out_answers.write(std.mem.asBytes(&sum));

    try out.flush();
    try out_answers.flush();

    std.log.info("Random seed: {d}", .{seed});
    std.log.info("Pair count: {d}", .{npairs});
    std.log.info("Expected sum: {d}", .{sum});

    std.process.exit(0);
}

fn randomBetween(prng: std.Random, min: f64, max: f64) f64 {
    const rnd = prng.float(f64);
    return (1.0 - rnd) * min + rnd * max;
}

fn randomDegree(prng: std.Random, center: f64, radius: f64, min: f64, max: f64) f64 {
    const min_val = @max(center - radius, min);
    const max_val = @min(center + radius, max);
    return randomBetween(prng, min_val, max_val);
}
