const std = @import("std");
const debug = std.debug;
const json = std.json;
const mem = std.mem;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Parsed = std.json.Parsed;
const Scanner = std.json.Scanner;
const Token = std.json.Token;
const TokenType = std.json.TokenType;

// pub const Bool = bool;

const model = @import("model.zig");
const Thing = model.Thing;

pub const Int = i64;
pub const Uint = u64;
pub const Float = f64;
pub const String = []const u8;

// const ParseError = blk: {
//     const Err = json.ParseError(Scanner);
//     break :blk Err.OutOfMemory || Err.UnexpectedToken;
// };

pub const ParseError = json.ParseError(Scanner);

pub fn parse(comptime T: type, allocator: Allocator, s: []const u8) ParseError!Parsed(T) {
    var parsed = Parsed(T){
        .arena = try allocator.create(ArenaAllocator),
        .value = undefined,
    };
    parsed.arena.* = ArenaAllocator.init(allocator);
    var scanner = Scanner.initCompleteInput(parsed.arena.allocator(), s);
    parsed.value = try innerParse(T, parsed.arena, &scanner);
    debug.assert((try scanner.next() == .end_of_document));
    return parsed;
}

fn innerParse(comptime T: type, arena: *ArenaAllocator, scanner: *Scanner) ParseError!T {
    const allocator = arena.allocator();

    // debug.print("\nT: {any}\n", .{T});

    switch (@typeInfo(T)) {
        .Optional => |optional_info| {
            switch (try scanner.peekNextTokenType()) {
                .null => {
                    debug.assert(try scanner.next() == .null);
                    return null;
                },
                .string => {
                    const s = switch (try scanner.nextAlloc(allocator, .alloc_always)) {
                        .allocated_string => |s| s,
                        else => unreachable,
                    };
                    switch (optional_info.child) {
                        Thing => {
                            debug.assert(s.len == 0);
                            return null;
                        },
                        []const u8 => return s,
                        else => unreachable,
                    }
                },
                else => return try innerParse(optional_info.child, arena, scanner),
            }
        },
        .Bool => {
            const token: Token = try scanner.next();
            return switch (token) {
                .true => true,
                .false => false,
                else => unreachable,
            };
        },
        .Int, .Float => {
            const s = (try scanner.next()).number;
            return switch (T) {
                Uint => std.fmt.parseInt(Uint, s, 10) catch unreachable,
                Int => std.fmt.parseInt(Int, s, 10) catch unreachable,
                Float => std.fmt.parseFloat(Float, s) catch unreachable,
                else => unreachable,
            };
        },
        .Array => |array_info| {
            debug.assert((try scanner.next()) == .array_begin);
            const Child = array_info.child;
            var ret: [array_info.len]Child = undefined;
            for (0..array_info.len) |i| {
                ret[i] = try innerParse(Child, arena, scanner);
            }
            debug.assert((try scanner.next()) == .array_end);
            return ret;
        },
        .Pointer => |pointer_info| {
            switch (pointer_info.size) {
                .One => {
                    const Child = pointer_info.child;
                    const ret: *Child = try allocator.create(Child);
                    ret.* = try innerParse(Child, arena, scanner);
                    return ret;
                },
                .Slice => {
                    switch (try scanner.peekNextTokenType()) {
                        .array_begin => {
                            debug.assert((try scanner.next()) == .array_begin);
                            const Child = pointer_info.child;
                            var list = std.ArrayList(Child).init(allocator);
                            while (true) {
                                switch (try scanner.peekNextTokenType()) {
                                    .array_end => {
                                        debug.assert((try scanner.next()) == .array_end);
                                        break;
                                    },
                                    else => {},
                                }
                                const val = try innerParse(Child, arena, scanner);
                                try list.ensureUnusedCapacity(1);
                                list.appendAssumeCapacity(val);
                            }
                            return list.toOwnedSlice();
                        },
                        .string => {
                            if (pointer_info.child != u8) unreachable;
                            debug.assert(pointer_info.is_const == true);
                            debug.assert(pointer_info.sentinel == null);
                            const token: Token = try scanner.nextAlloc(allocator, .alloc_always);
                            return switch (token) {
                                .allocated_string => |s| s,
                                else => unreachable,
                            };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .Union => {
            debug.assert((try scanner.next()) == .object_begin);
            if (T != Thing) @panic("expect enum `Thing` only");

            const kind_name = (try scanner.next()).string;
            debug.assert(mem.eql(u8, kind_name, "kind"));

            const kind_value = (try scanner.next()).string;

            const data_name = (try scanner.next()).string;
            debug.assert(mem.eql(u8, data_name, "data"));

            const ret: Thing = if (mem.eql(u8, kind_value, "Listing"))
                .{ .listing = try innerParse(Listing, arena, scanner) }
            else if (mem.eql(u8, kind_value, "more"))
                .{ .more = try innerParse(More, arena, scanner) }
            else if (mem.eql(u8, kind_value, "t1"))
                .{ .comment = try innerParse(*Comment, arena, scanner) }
            else if (mem.eql(u8, kind_value, "t3"))
                .{ .link = try innerParse(Link, arena, scanner) }
            else
                unreachable;

            debug.assert((try scanner.next()) == .object_end);
            return ret;
        },
        .Struct => |struct_info| {
            debug.assert((try scanner.next()) == .object_begin);
            debug.assert(struct_info.is_tuple == false);

            const fields = struct_info.fields;
            var field_count: usize = 0;

            var ret: T = undefined;
            while (true) {
                const name_token: Token = try scanner.next();
                const field_name = switch (name_token) {
                    inline .string => |s| s,
                    .object_end => break,
                    else => unreachable,
                };
                // debug.print("field_name: {s}\n", .{field_name});

                inline for (fields) |field| {
                    if (field.is_comptime) @compileError("comptime fields are not supported: " ++ @typeName(T) ++ "." ++ field.name);

                    if (mem.eql(u8, field.name, field_name)) {
                        const val = try innerParse(field.type, arena, scanner);

                        // debug.print("field.type: {any}\n", .{field.type});
                        // switch (field.type) {
                        //     []const u8 => {
                        //         debug.print("val: {s}\n", .{val});
                        //     },
                        //     ?[]const u8 => {
                        //         if (val) |v| {
                        //             debug.print("val: {s}\n", .{v});
                        //         } else {
                        //             debug.print("val: null\n", .{});
                        //         }
                        //     },
                        //     else => {
                        //         debug.print("val: {any}\n", .{val});
                        //     },
                        // }

                        @field(ret, field.name) = val;
                        field_count += 1;
                        break;
                    }
                } else {
                    _ = try scanner.skipValue();
                }
            }
            debug.assert(struct_info.fields.len == field_count);
            return ret;
        },
        else => {
            unreachable;
        },
    }
    // return undefined;
    unreachable;
}

// const Thing = union(enum) {
//     listing: Listing,
//     more: More,
//     link: Link,
//     comment: *Comment,
// };

const Listing = struct {
    // before: ?String,
    // after: ?String,
    // dist: ?Uint,
    // modhash: ?String,
    // geo_filter: String,
    // children: []Thing,

    before: ?String,
    after: ?String,
    dist: ?Uint,
    modhash: ?String,
    geo_filter: String,
    children: []Thing,
};

const More = struct {
    count: Uint,
    name: String,
    id: String,
    depth: Uint,
    children: []String,
};

const Link = struct {
    // id: String,

    name: String,
    // url: String,
    // permalink: String,
    // over_18: bool,

    // created: Uint,
    // created_utc: Uint,

    // approved_at_utc: ?Uint,
    // approved_by: ?String,

    // subreddit: String,
    // subreddit_id: String,
    // domain: String,

    // num_comments: Uint,
    // num_crossposts: Uint,
    // ups: Uint,
    // downs: Uint,
    // score: Uint,
    // upvote_ratio: Float,

    title: String,
    selftext: ?String,
    // selftext_html: ?String,

    author: String,
    // author_fullname: String,

    // suggested_sort: ?String,

};

const Comment = struct {
    name: String,
    body: ?String,
    replies: ?Thing,
    author: String,
};

// fn FieldNames(comptime T: type) type {
//     const fields = @typeInfo(T).Struct.fields;
//     return [fields.len][]const u8;
// }

pub fn FilteredComment(comptime T: type, field_names: anytype) type {
    const StructField = std.builtin.Type.StructField;

    var buf: [1 << 13]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var field_list: [field_names.len]StructField = undefined;
    const struct_info = @typeInfo(T).Struct;
    const fields = struct_info.fields;

    var i: usize = 0;
    for (fields) |field| {
        for (field_names) |name| {
            if (mem.eql(u8, field.name, name)) {
                const new_field = StructField{
                    .name = fba.threadSafeAllocator().dupeZ(u8, name) catch unreachable,
                    .type = field.type,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field.type),
                };
                field_list[i] = new_field;
                i += 1;
            }
        }
    }

    return @Type(std.builtin.Type{
        .Struct = .{
            .layout = .auto,
            .backing_integer = null,
            .fields = &field_list,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub fn getThing2(ptr: anytype, kind: []const u8) Thing2 {
    // const T = @TypeOf(ptr);
    // const info = @typeInfo(T).Pointer;
    // debug.assert(info.size == .One);
    // const Child = info.child;
    return Thing2{
        .ctx = @as(*anyopaque, @ptrCast(@alignCast(ptr))),
        .kind = kind,
    };
}

const Thing2 = struct {
    ctx: *anyopaque,
    kind: []const u8,
    fn get(self: *const Thing2) *opaque {} {
        const T = if (mem.eql(u8, self.kind, "Listing"))
            Listing
        else if (mem.eql(u8, self.kind, "more"))
            More
        else if (mem.eql(u8, self.kind, "t1"))
            Comment
        else if (mem.eql(u8, self.kind, "t3"))
            Link
        else
            unreachable;

        return @as(T, @ptrCast(@alignCast(self.ctx)));
    }
};

const print = std.debug.print;

test "fileterd struct" {
    if (true) return error.SkipZigTest;
    print("\n", .{});

    const allocator = std.heap.page_allocator;

    const more: *More = try allocator.create(More);
    const link: *Link = try allocator.create(Link);

    const t1 = getThing2(more, "more");
    const t2 = getThing2(link, "t3");

    const ts: [2]Thing2 = .{ t1, t2 };
    _ = ts; // autofix

    const m1 = t1.get();
    _ = m1; // autofix

    // const T = FilteredComment(More, .{ "count", "id" });
    // const val = T{
    //     .count = 4,
    //     .id = "haha",
    // };

    // print("{any}\n", .{val});
}

test "customize json listing new" {
    // if (true) return error.SkipZigTest;
    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    // const s = @embedFile("testjson/listing_new.json");
    const s = @embedFile("testjson/listing_new_simple.json");

    const Model = Thing;
    const parsed = try parse(Model, allocator, s);
    _ = parsed; // autofix

    // for (parsed.children) |link| {
    //     _ = link; // autofix
    // }
}

test "customize json listing comments" {
    if (true) return error.SkipZigTest;

    print("\n", .{});

    // const allocator = std.heap.page_allocator;
    const allocator = std.testing.allocator;

    const s = @embedFile("testjson/comments2.json");

    const Model = [2]Thing;
    // const Model = []Thing;
    // _ = Model; // autofix

    const parsed = try parse(Model, allocator, s);
    defer parsed.deinit();

    const thing = parsed.value;

    {
        const listing = thing[0].listing.children;
        _ = listing; // autofix
        // const link = thing[0].tisting;

        // for (listing_link) |_link| {
        //     const link = _link.link;
        //     // print("{s}\n", .{link});

        // }
    }

    {
        // const listing = thing[1].listing.children;

        // for (thing[1].listing.children) |thing| {
        //     thing.comment;
        // }
    }

    // ====================

}

test " json listing comments" {
    if (true) return error.SkipZigTest;

    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    const s = @embedFile("testjson/comments.json");

    const Model = struct { Listing(Link), Listing(Comment) };
    // _ = Model; // autofix

    // const parsed = try json.parseFromSlice(JsonValue, allocator, s, .{
    const parsed = try json.parseFromSlice(Model, allocator, s, .{
        .ignore_unknown_fields = true,
    });
    const root = parsed.value;
    _ = root; // autofix

}

test "token stream json" {
    if (true) return error.SkipZigTest;

    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    // const content = @embedFile("testjson/listing_new.json");
    const content = @embedFile("testjson/listing_new_simple.json");
    // const content = @embedFile("testjson/comments2.json");

    // const content =
    //     \\[
    //     \\  "", "a\nb",
    //     \\  0, 0.0, -1.1e-1,
    //     \\  true, false, null,
    //     \\  {"a": {}},
    //     \\  []
    //     \\]
    // ;

    // const content =
    //     \\{
    //     \\  "Image": {
    //     \\      "Width":  800,
    //     \\      "Height": 600,
    //     \\      "Title":  "View from 15th Floor",
    //     \\      "Thumbnail": {
    //     \\          "Url":    "http://www.example.com/image/481989943",
    //     \\          "Height": 125,
    //     \\          "Width":  100
    //     \\      },
    //     \\      "Animated" : false,
    //     \\      "IDs": [116, 943, 234, 38793]
    //     \\    }
    //     \\}
    // ;

    var scanner = json.Scanner.initCompleteInput(allocator, content);

    // pub const Token = union(enum) {
    //     object_begin,
    //     object_end,
    //     array_begin,
    //     array_end,

    //     true,
    //     false,
    //     null,

    //     number: []const u8,
    //     partial_number: []const u8,
    //     allocated_number: []u8,

    //     string: []const u8,
    //     partial_string: []const u8,
    //     partial_string_escaped_1: [1]u8,
    //     partial_string_escaped_2: [2]u8,
    //     partial_string_escaped_3: [3]u8,
    //     partial_string_escaped_4: [4]u8,

    //     allocated_string: []u8,

    //     end_of_document,
    // };

    // const Model = Listing(Link);
    print("\n\n", .{});

    while (true) {
        // const token = scanner.next() catch unreachable;
        const token = scanner.nextAlloc(allocator, .alloc_if_needed) catch unreachable;
        // const token = scanner.nextAlloc(allocator, .alloc_always) catch unreachable;

        switch (token) {
            .end_of_document => break,
            .false => {
                print("false\n", .{});
            },
            .true => {
                print("true\n", .{});
            },
            .null => {
                print("null\n", .{});
            },
            .number => |s| {
                print("num: {s}\n", .{s});
            },
            .partial_number => |s| {
                print("partial num: {s}\n", .{s});
            },
            .allocated_number => |s| {
                print("alloc num: {s}\n", .{s});
            },
            .string => |val| {
                print("str: {s}\n", .{val});
            },
            .allocated_string => |s| {
                print("alloc str: {s}\n", .{s});
            },
            .partial_string => |s| {
                print("p str: {s}\n", .{s});
            },
            .partial_string_escaped_1 => |s| {
                print("p str esc1: {any}\n", .{&s});
            },
            .partial_string_escaped_2 => |s| {
                print("p str esc2: {any}\n", .{&s});
            },
            .partial_string_escaped_3 => |s| {
                print("p str esc3: {any}\n", .{&s});
            },
            .partial_string_escaped_4 => |s| {
                print("p str esc4: {any}\n", .{&s});
            },
            else => |val| {
                print("{any}\n", .{val});
            },
        }

        // print("\n", .{});
        // print("{any}\n", .{try scanner.peekNextTokenType()});
    }

    // while (try scanner.next()) |token| {
    //     switch (token) {
    //         .string => |val| {
    //             print("{s}\n", .{val});
    //         },
    //         else => |val| {
    //             print("{any}\n", .{val});
    //         },
    //     }
    // }

    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});
    // print("{any}\n", .{try scanner.next()});

    // try parse(Model, allocator, s);
}

test "apoieur" {
    if (true) return error.SkipZigTest;

    const info = @typeInfo(Thing);
    const union_info = info.Union;

    print("\n", .{});

    const fields = union_info.fields;
    inline for (fields) |field| {
        print("{s}\n", .{field.name});
        print("{}\n", .{field.type});
        print("\n", .{});
    }

    // print("{any}\n", .{union_info.layout});
    // print("{any}\n", .{union_info.fields});
    // print("{any}\n", .{dinfo.Union.tag_type});
    // print("{}\n", .{info});
    // @compileError(info.Enum.);
}
