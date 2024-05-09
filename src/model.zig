const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Parsed = std.json.Parsed;
const Scanner = std.json.Scanner;
const Token = std.json.Token;
const TokenType = std.json.TokenType;

pub const Int = i64;
pub const Uint = u64;
pub const Float = f64;
pub const String = []const u8;

pub const ParseError = json.ParseError(Scanner);

pub fn parse(comptime T: type, allocator: Allocator, s: []const u8) ParseError!Parsed(T) {
    var parsed = Parsed(T){
        .arena = try allocator.create(ArenaAllocator),
        .value = undefined,
    };
    parsed.arena.* = ArenaAllocator.init(allocator);
    var scanner = Scanner.initCompleteInput(parsed.arena.allocator(), s);
    parsed.value = try innerParse(T, parsed.arena, &scanner);
    if (!scanner.is_end_of_input) {
        debug.assert(try scanner.next() == .end_of_document);
    }
    debug.assert(scanner.is_end_of_input);
    // if (s[0 .. s.len - 1] == '\n') {
    //     debug.assert(try scanner.next() == .end_of_document);
    // }

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

pub const Thing = union(enum) {
    listing: Listing,
    more: More,
    link: Link,
    comment: *Comment,
};

pub const More = struct {
    count: Uint,
    name: String,
    id: String,
    depth: Uint,
    children: []String,
};

pub const SrDetail = struct {
    default_set: bool,
    banner_img: String,
    // allowed_media_in_comments: ,
    user_is_banned: bool,
    free_form_reports: bool,
    community_icon: String,
    show_media: bool,
    description: String,
    // user_is_muted: ,
    display_name: String,
    // // header_img:
    title: String,
    // previous_names:
    user_is_moderator: bool,
    over_18: bool,
    icon_size: []const Uint,
    primary_color: String,
    icon_img: String,
    icon_color: String,
    submit_link_label: String,
    header_size: ?Uint,
    restrict_posting: bool,
    restrict_commenting: bool,
    subscribers: Uint,
    submit_text_label: String,
    link_flair_position: String,
    display_name_prefixed: String,
    key_color: String,
    name: String,
    created: Uint,
    url: String,
    quarantine: bool,
    created_utc: Uint,
    // banner_size: ?
    user_is_contributor: bool,
    accept_followers: bool,
    public_description: String,
    link_flair_enabled: bool,
    disable_contributor_requests: bool,
    subreddit_type: String,
    user_is_subscriber: bool,
};

pub const Listing = struct {
    before: ?String,
    after: ?String,
    dist: ?Uint,
    modhash: ?String,
    geo_filter: String,
    children: []Thing,
};

pub const Link = struct {
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

    // title: String,
    selftext: ?String,
    // selftext_html: ?String,

    // author: String,
    // author_fullname: String,

    // suggested_sort: ?String,

    // sr_detail: ?SrDetail,
};

pub const Comment = struct {
    name: String,
    body: ?String,
    replies: ?Thing,
    author: String,
};

const print = std.debug.print;

test "customize json listing new" {
    if (true) return error.SkipZigTest;
    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    // const s = @embedFile("testjson/listing_new.json");
    // const s = @embedFile("testjson/listing_new_simple.json");
    const s = @embedFile("testjson/listing_new2.json");

    const Model = Thing;
    const parsed = try parse(Model, allocator, s);
    defer parsed.deinit();

    // print("{any}\n", .{parsed.value});

    // for (parsed.children) |link| {
    //     _ = link; // autofix
    // }
}
