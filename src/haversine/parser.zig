const std = @import("std");
const utils = @import("utils");
const profiler = @import("profiler.zig");

const log = std.log.scoped(.parser);

const JsonField = struct {
    key: []const u8,
    value: JsonValue,
};
const JsonValue = union(enum) {
    string: []const u8,
    number: f64,
    object: JsonObject,
    array: JsonArray,
    boolean: bool,
    null: void,

    pub fn asObject(self: JsonValue) ?JsonObject {
        return switch (self) {
            .object => self.object,
            inline else => null,
        };
    }
};
const JsonObject = struct {
    fields: []JsonField,

    pub fn getFloat(self: JsonObject, key: []const u8) ?f64 {
        return for (self.fields) |field| {
            if (std.mem.eql(u8, key, field.key)) {
                break field.value.number;
            }
        } else null;
    }
};

pub const JsonArray = struct {
    index: usize = 0,
    items: []JsonValue,

    pub fn next(self: *JsonArray) ?JsonValue {
        if (self.index >= self.items.len) return null;
        defer self.index += 1;
        return self.items[self.index];
    }
};

pub const JsonElement = union(enum) {
    object: JsonObject,
    array: JsonArray,

    pub fn getArray(self: JsonElement, key: []const u8) ?JsonArray {
        return switch (self) {
            .object => for (self.object.fields) |field| {
                if (std.mem.eql(u8, key, field.key)) {
                    break field.value.array;
                }
            } else null,
            .array => unreachable,
        };
    }
};

const JsonTokenType = enum {
    left_brace,
    right_brace,
    comma,
    colon,
    left_bracket,
    right_bracket,
    string,
    number,
    true,
    false,
    null,
    @"error",
};

const JsonToken = struct {
    type: JsonTokenType = .@"error",
    value: []const u8,
};

fn parseNextToken(allocator: std.mem.Allocator, in: *std.io.Reader) !JsonToken {
    var next = try in.takeByte();
    var value = try allocator.alloc(u8, 1);
    value[0] = next;
    var token = JsonToken{
        .value = value,
    };
    sw: switch (next) {
        '{' => token.type = .left_brace,
        '}' => token.type = .right_brace,
        '[' => token.type = .left_bracket,
        ']' => token.type = .right_bracket,
        ',' => token.type = .comma,
        ':' => token.type = .colon,
        '"' => {
            token.type = .string;
            var string_value = try std.ArrayList(u8).initCapacity(allocator, 20);
            var char = try in.takeByte();
            while (char != '"') {
                try string_value.append(allocator, char);
                char = try in.takeByte();
            }
            token.value = try string_value.toOwnedSlice(allocator);
        },
        '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
            token.type = .number;
            var number_value = try std.ArrayList(u8).initCapacity(allocator, 20);
            try number_value.append(allocator, next);
            while (true) {
                const char = try in.peekByte();
                if (std.ascii.isDigit(char) or char == '.') {
                    try number_value.append(allocator, char);
                    in.toss(1);
                } else {
                    break;
                }
            }
            token.value = try number_value.toOwnedSlice(allocator);
        },
        't' => {
            token.type = .true;
            token.value = "true";
            in.toss(3); // 'rue' part of true
        },
        'f' => {
            token.type = .false;
            token.value = "false";
            in.toss(4); // 'alse' part of false
        },
        'n' => {
            token.type = .null;
            token.value = "null";
            in.toss(3); // 'ull' part of null
        },
        ' ', '\n', '\r' => {
            next = try in.takeByte();
            value = try allocator.alloc(u8, 1);
            value[0] = next;
            token = JsonToken{
                .value = value,
            };
            continue :sw next;
        },
        else => unreachable,
    }
    return token;
}

const JsonError = std.mem.Allocator.Error || std.io.Reader.Error || std.fmt.ParseFloatError || error{BadToken};

fn parseObject(allocator: std.mem.Allocator, in: *std.io.Reader) JsonError!JsonObject {
    // profiler.timeBlock("Parse Object");
    // defer profiler.endTimeBlock("Parse Object");

    log.debug("O>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n", .{});
    defer log.debug("O<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n", .{});
    var fields = try std.ArrayList(JsonField).initCapacity(allocator, 10);
    var key: ?[]const u8 = null;
    while (true) {
        const next = parseNextToken(allocator, in) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        log.debug("Next: type={t} | value={s}\n", .{ next.type, next.value });

        switch (next.type) {
            .string => {
                if (key == null) {
                    key = next.value;
                } else {
                    try fields.append(allocator, .{ .key = key.?, .value = .{ .string = next.value } });
                }
            },
            .colon => {},
            .comma => key = null,
            .number => try fields.append(allocator, .{
                .key = key.?,
                .value = .{ .number = try std.fmt.parseFloat(f64, next.value) },
            }),
            .true, .false => try fields.append(allocator, .{
                .key = key.?,
                .value = .{ .boolean = if (std.mem.eql(u8, next.value, "true")) true else false },
            }),
            .left_brace => try fields.append(allocator, .{
                .key = key.?,
                .value = .{ .object = try parseObject(allocator, in) },
            }),
            .left_bracket => try fields.append(allocator, .{
                .key = key.?,
                .value = .{ .array = try parseArray(allocator, in) },
            }),
            .null => try fields.append(allocator, .{ .key = key.?, .value = .{ .null = {} } }),
            .right_brace => break,
            .right_bracket, .@"error" => {
                log.err("unexpected token found: '{s}'", .{next.value});
                return error.BadToken;
            },
        }
    }

    return JsonObject{ .fields = try fields.toOwnedSlice(allocator) };
}

fn parseArray(allocator: std.mem.Allocator, in: *std.io.Reader) !JsonArray {
    log.debug("A>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n", .{});
    defer log.debug("A<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n", .{});
    var items = try std.ArrayList(JsonValue).initCapacity(allocator, 10);
    while (true) {
        const next = parseNextToken(allocator, in) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        log.debug("Next: type={t} | value={s}\n", .{ next.type, next.value });

        switch (next.type) {
            .string => try items.append(allocator, .{ .string = next.value }),
            .number => try items.append(allocator, .{ .number = try std.fmt.parseFloat(f64, next.value) }),
            .true, .false => try items.append(allocator, .{ .boolean = if (std.mem.eql(u8, next.value, "true")) true else false }),
            .left_brace => try items.append(allocator, .{ .object = try parseObject(allocator, in) }),
            .left_bracket => try items.append(allocator, .{ .array = try parseArray(allocator, in) }),
            .null => try items.append(allocator, .{ .null = {} }),
            .comma => {},
            .right_bracket => break,
            .right_brace, .colon, .@"error" => {
                log.err("unexpected token found: '{s}'", .{next.value});
                return error.BadToken;
            },
        }
    }
    return JsonArray{ .items = try items.toOwnedSlice(allocator) };
}

pub fn parse(allocator: std.mem.Allocator, in: *std.io.Reader) !JsonElement {
    const next = parseNextToken(allocator, in) catch |err| switch (err) {
        error.EndOfStream => {
            log.err("file ended unexpectedly", .{});
            return err;
        },
        else => return err,
    };
    log.debug("Next: type={t} | value={s}\n", .{ next.type, next.value });

    return switch (next.type) {
        .left_brace => .{ .object = try parseObject(allocator, in) },
        .left_bracket => .{ .array = try parseArray(allocator, in) },
        else => unreachable,
    };
}

pub const HaversineInput = struct { x0: f64, y0: f64, x1: f64, y1: f64 };

pub fn parseHaversineInputs(allocator: std.mem.Allocator, in: *std.io.Reader, expected_size: usize) ![]HaversineInput {
    profiler.timeBlock("Parse");
    defer profiler.endTimeBlock("Parse");

    var inputs = try std.ArrayList(HaversineInput).initCapacity(allocator, expected_size);

    const json = try parse(allocator, in);

    profiler.timeBlock("Lookup and Convert");
    var pairs = json.getArray("pairs").?;
    while (pairs.next()) |pair| {
        const obj = pair.asObject() orelse return fail("expected 'pairs' to be an object but was of type '{s}'", .{@tagName(pair)});
        const input = try inputs.addOne(allocator);
        input.* = .{
            .x0 = obj.getFloat("x0") orelse return fail("expected 'x0' to be a float", .{}),
            .y0 = obj.getFloat("y0") orelse return fail("expected 'y0' to be a float", .{}),
            .x1 = obj.getFloat("x1") orelse return fail("expected 'x1' to be a float", .{}),
            .y1 = obj.getFloat("y1") orelse return fail("expected 'y1' to be a float", .{}),
        };
    }
    profiler.endTimeBlock("Lookup and Convert");

    return inputs.toOwnedSlice(allocator);
}

fn fail(comptime format: []const u8, args: anytype) ![]HaversineInput {
    log.err(format, args);
    return error.JsonParseError;
}

test {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const reader = try utils.openFileReaderAlloc(allocator, "./src/haversine/tests/data_10_12344846.json");
    const in = &reader.file_reader.interface;

    const inputs = try parseHaversineInputs(allocator, in, 10);
    try std.testing.expectEqualSlices(HaversineInput, &expectedInputs, inputs);
}

const expectedInputs = [_]HaversineInput{
    .{ .x0 = 142.26714450020526, .y0 = -87.04773502092395, .x1 = 179.6634149679651, .y1 = -64.44171554018267 },
    .{ .x0 = -151.6097544064065, .y0 = 31.69390733244844, .x1 = -165.6724419771865, .y1 = 33.03468527469353 },
    .{ .x0 = 173.82281317190592, .y0 = -68.81541601681299, .x1 = 52.767443092745495, .y1 = 26.880429952403667 },
    .{ .x0 = 171.61699131486142, .y0 = -52.635980483380806, .x1 = 77.57835596803272, .y1 = -14.464313883961996 },
    .{ .x0 = -64.91966952704952, .y0 = 24.01873335223311, .x1 = 90.73404830536916, .y1 = 11.589255062986163 },
    .{ .x0 = 93.7151335878169, .y0 = 71.4738127512829, .x1 = 128.26992122893458, .y1 = 45.59023134902394 },
    .{ .x0 = 97.83733435598464, .y0 = -37.15368851784143, .x1 = 53.28766709513775, .y1 = -34.27167312566802 },
    .{ .x0 = 108.14859591114566, .y0 = 1.1201970118394584, .x1 = 175.62641944868662, .y1 = -37.4672595349445 },
    .{ .x0 = -120.40531355823526, .y0 = -57.97369998551621, .x1 = -131.7413507924263, .y1 = -68.94743564578545 },
    .{ .x0 = 107.67573451452397, .y0 = -43.298090046427234, .x1 = 0.9233920580320643, .y1 = -34.34187530528029 },
};
