const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const fmt = std.fmt;
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ParseOptions = std.json.ParseOptions;
const Value = std.json.Value;
const Token = std.json.Token;
const TokenType = std.json.TokenType;
const ParseError = std.json.ParseError;

pub const AccountMe = @import("model/account.zig").AccountMe;
pub const Thing = @import("model/listing.zig").Thing;
pub const Listing = @import("model/listing.zig").Listing;
pub const More = @import("model/listing.zig").More;
pub const Link = @import("model/listing.zig").Link;
pub const Comment = @import("model/listing.zig").Comment;

pub const Int = i64;
pub const Uint = u64;
pub const Float = f64;
pub const String = []const u8;

pub const Subreddit = struct {
    default_set: bool,
    user_is_contributor: bool,
    banner_img: String,
    restrict_posting: bool,
    user_is_banned: bool,
    free_form_reports: bool,
    community_icon: ?String,
    show_media: bool,
    icon_color: String,
    // // user_is_muted: bool, // NOTE: unimplemented
    display_name: String,
    header_img: ?String,
    title: String,
    coins: ?Uint = null,
    // // previous_names: [], // NOTE: unimplemented
    over_18: bool,
    icon_size: [2]Uint,
    primary_color: String,
    icon_img: String,
    description: String,
    // // allowed_media_in_comments: [], // NOTE: unimplemented
    submit_link_label: String,
    header_size: ?[2]Uint,
    restrict_commenting: bool,
    subscribers: Uint,
    submit_text_label: String,
    is_default_icon: ?bool = null,
    link_flair_position: String,
    display_name_prefixed: String,
    key_color: String,
    name: String,
    created: ?Uint = null,
    is_default_banner: bool,
    url: String,
    quarantine: bool,
    banner_size: ?[2]Uint,
    user_is_moderator: bool,
    accept_followers: bool,
    public_description: String,
    link_flair_enabled: bool,
    disable_contributor_requests: bool,
    subreddit_type: SubredditType,
    user_is_subscriber: bool,
};

pub const SubredditType = enum {
    user,
    public,
    private,
    restricted,
    gold_restricted,
    archived,
    pub const jsonParse = ImplEnumJsonParseFn(@This()).jsonParse;
};

// https://www.reddit.com/r/redditdev/comments/19ak1b/api_change_distinguished_is_now_available_in_the/
pub const Distinguished = enum {
    moderator,
    admin,
    special,
    pub const jsonParse = ImplEnumJsonParseFn(@This()).jsonParse;
};

// https://praw.readthedocs.io/en/stable/code_overview/models/submission.html#praw.models.Submission.award
pub const Award = struct {
    giver_coin_reward: Uint,
    subreddit_id: ?String,
    is_new: bool,
    days_of_drip_extension: Uint,
    coin_price: Uint,
    id: String,
    penny_donate: Uint,
    coin_reward: Uint,
    icon_url: String,
    days_of_premium: Uint,
    icon_height: Uint,
    // tiers_by_required_awardings: None,
    icon_width: Uint,
    static_icon_width: Uint,
    // start_date: None,
    is_enabled: bool,
    // awardings_required_to_grant_benefits: None,
    description: String,
    // end_date: None,
    subreddit_coin_reward: Uint,
    count: Uint,
    static_icon_height: Uint,
    name: String,
    icon_format: String,
    award_sub_type: String,
    penny_price: Uint,
    award_type: String,
    static_icon_url: String,
};

pub fn ImplEnumJsonParseFn(comptime T: type) type {
    return struct {
        pub fn jsonParse(_: Allocator, source: anytype, _: ParseOptions) !T {
            const Error = ParseError(@TypeOf(source.*));
            switch (try source.next()) {
                .string => |s| {
                    const info = @typeInfo(T).Enum;
                    inline for (info.fields, 0..) |field, i| {
                        if (mem.eql(u8, field.name, s)) {
                            return @enumFromInt(i);
                        }
                    } else return Error.UnexpectedToken;
                },
                else => return Error.UnexpectedToken,
            }
            unreachable;
        }
    };
}

pub fn ImplJsonParseTokenTypeAsNullFn(comptime null_repr_token: TokenType, comptime T: type) type {
    return struct {
        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !?T {
            if (try source.peekNextTokenType() == null_repr_token) {
                _ = try source.next();
                return null;
            }
            return try json.innerParse(T, allocator, source, options);
        }
    };
}

pub fn ImplJsonParseEmptyObjectAsNullFn(comptime T: type) type {
    return struct {
        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !?T {
            const Error = ParseError(@TypeOf(source.*));
            const value = try json.innerParse(Value, allocator, source, options);
            switch (value) {
                .object => |obj| {
                    if (obj.count() == 0) return null;
                },
                else => return Error.UnexpectedToken,
            }
            return try json.innerParseFromValue(T, allocator, value, options);
        }
    };
}

pub fn ImplJsonParseEmptyStringAsNullFn(comptime T: type) type {
    return struct {
        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !?T {
            const Error = ParseError(@TypeOf(source.*));

            switch (try source.peekNextTokenType()) {
                .string => {
                    const s = try json.innerParse([]const u8, allocator, source, options);

                    if (s.len == 0) return null;
                    // if (T == String) return s; // TODO uncomment
                    return Error.UnexpectedToken;
                },
                else => {},
                // else => return Error.UnexpectedToken,
            }
            return try json.innerParse(T, allocator, source, options);
        }
    };
}

// NOTE stolen from std/json/static.zig
pub fn fillDefaultStructValues(comptime T: type, r: *T, fields_seen: *[@typeInfo(T).Struct.fields.len]bool) !void {
    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        if (!fields_seen[i]) {
            if (field.default_value) |default_ptr| {
                const default = @as(*align(1) const field.type, @ptrCast(default_ptr)).*;
                @field(r, field.name) = default;
            } else {
                return error.MissingField;
            }
        }
    }
}

pub fn jsonParseAllocString(allocator: Allocator, source: anytype, _: ParseOptions) ![]const u8 {
    const Error = ParseError(@TypeOf(source.*));
    return switch (try source.nextAlloc(allocator, .alloc_always)) {
        .allocated_string => |s| s,
        else => Error.UnexpectedToken,
    };
}

const print = std.debug.print;

const PrettyOptions = struct {
    indent_len: usize = 4,
};

const PrettyPrintState = struct {
    name: ?[]const u8,
    print_type: bool,
    // line_break: bool,
    depth: usize,

    fn setName(self: @This(), name: ?[]const u8) @This() {
        var new_self = self;
        new_self.name = name;
        return new_self;
    }

    fn setPrintType(self: @This(), print_type: bool) @This() {
        var new_self = self;
        new_self.print_type = print_type;
        return new_self;
    }

    fn bumpDepth(self: @This()) @This() {
        var new_self = self;
        new_self.depth += 1;
        return new_self;
    }
};

pub fn allocPrettyPrint(allocator: Allocator, value: anytype) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    const state = PrettyPrintState{
        .name = null,
        .print_type = true,
        .depth = 0,
    };
    const options = PrettyOptions{
        .indent_len = 4,
    };
    try prettyPrint(value, options, state, list.writer());

    return try list.toOwnedSlice();
}

fn prettyPrintString(value: anytype, options: PrettyOptions, state: PrettyPrintState, writer: anytype) @TypeOf(writer).Error!void {
    switch (@typeInfo(@TypeOf(value))) {
        .Pointer => |ptr_info| {
            debug.assert(ptr_info.child == u8);
        },
        else => unreachable,
    }
    const padding = options.indent_len * state.depth;
    for (value) |byte| {
        try writer.writeByte(byte);
        if (byte == '\n') {
            try writer.writeByteNTimes(' ', padding + if (state.name) |nm| nm.len + 2 else 0);
        }
    }
}

fn prettyPrint(value: anytype, options: PrettyOptions, state: PrettyPrintState, writer: anytype) @TypeOf(writer).Error!void {
    const T = @TypeOf(value);

    const padding = options.indent_len * state.depth;

    const ccyan = "\x1b[36m";
    const creset = "\x1b[0m";

    const type_name = ccyan ++ @typeName(T) ++ creset;

    try writer.writeByteNTimes(' ', padding);
    if (state.name) |name| {
        try writer.print(".{s}: ", .{name});
    }
    if (state.print_type) {
        try writer.print("{s} = ", .{type_name});
    }

    try prettyPrintValue(value, options, state, writer);

    try writer.print(", ", .{});

    try writer.print("\n", .{});
}

fn prettyPrintValue(value: anytype, options: PrettyOptions, state: PrettyPrintState, writer: anytype) @TypeOf(writer).Error!void {
    const T = @TypeOf(value);

    const padding = options.indent_len * state.depth;

    const cgreen = "\x1b[32m";
    // const ccyan = "\x1b[36m";
    const cmagenta = "\x1b[35m";
    const creset = "\x1b[0m";

    switch (@typeInfo(T)) {
        .Void => |_| {
            try writer.print("{s}", .{cmagenta});
            try writer.print("{{}}", .{});
            try writer.print("{s}", .{creset});
        },
        .Optional => |_| {
            if (value) |payload| {
                try prettyPrintValue(payload, options, state, writer);
            } else {
                try writer.print("{s}", .{cmagenta});
                try writer.print("null", .{});
                try writer.print("{s}", .{creset});
            }
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .Slice => {
                    //
                    if (ptr_info.child == u8) {
                        try writer.print("{s}", .{cgreen});
                        try writer.print("\"", .{});

                        for (value) |byte| {
                            try writer.writeByte(byte);
                            if (byte == '\n') {
                                var total_padding = padding;
                                if (state.name) |nm| total_padding += nm.len + 3;
                                if (state.print_type) total_padding += @typeName(T).len + 4;
                                try writer.writeByteNTimes(' ', total_padding);
                            }
                        }

                        try writer.print("\"", .{});
                        try writer.print("{s}", .{creset});
                    } else {
                        //
                        try writer.print("[\n", .{});
                        for (value) |val| {
                            try prettyPrint(val, options, state.bumpDepth(), writer);
                        }

                        try writer.writeByteNTimes(' ', padding);
                        try writer.writeByte(']');
                    }
                },
                else => {
                    try prettyPrintValue(value.*, options, state, writer);
                },
            }
        },
        .Array => |_| {
            try writer.print("[\n", .{});
            for (value) |child| {
                try prettyPrint(child, options, state.bumpDepth().setName(null), writer);
            }
            try writer.writeByteNTimes(' ', padding);
            try writer.writeByte(']');
        },
        .Union => |union_info| {
            try writer.print("{{\n", .{});

            const tagname = @tagName(value);
            inline for (union_info.fields) |field| {
                if (mem.eql(u8, tagname, field.name)) {
                    try prettyPrint(@field(value, field.name), options, state.bumpDepth().setName(field.name), writer);
                    break;
                }
            }

            try writer.writeByteNTimes(' ', padding);
            try writer.writeByte('}');
        },
        .Struct => |struct_info| {
            try writer.print("{{\n", .{});

            inline for (struct_info.fields) |field| {
                try prettyPrint(@field(value, field.name), options, state.bumpDepth().setName(field.name), writer);
            }

            try writer.writeByteNTimes(' ', padding);
            try writer.writeByte('}');
        },
        else => {
            try writer.print("{s}", .{cmagenta});
            try writer.print("{any}", .{value});
            try writer.print("{s}", .{creset});
        },
    }
}

test "asaoieud" {
    if (true) return error.SkipZigTest;
    print("\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const Qux = union(enum) {
        aa: ?usize,
        bb: []const u8,
        cc: void,
    };

    const Baz = struct {
        pos: struct {
            x: i32,
            y: i32,
        },
        loc: []const u8,
    };

    const Foo = struct {
        names: [3][]const u8,
        qux: Qux,

        maybe: ?u32,
        maybe_maybe: ?[]const u8,
        slice_of_qux: []Qux,
        slice_of_nums: []i32,
        slice_of_baz: []Baz,
        text: []const u8,
    };

    var slice_of_qux = try allocator.alloc(Qux, 3);
    slice_of_qux[0] = Qux{ .aa = null };
    slice_of_qux[1] = Qux{ .bb = "meh" };
    slice_of_qux[2] = Qux.cc;

    var slice_of_baz = try allocator.alloc(Baz, 3);
    slice_of_baz[0] = Baz{ .pos = .{ .x = 12, .y = -34 }, .loc = "terra" };
    slice_of_baz[1] = Baz{ .pos = .{ .x = -9, .y = 123 }, .loc = "inferno" };
    slice_of_baz[2] = Baz{ .pos = .{ .x = 1, .y = 99 }, .loc = "andromeda" };

    var nums = [_]i32{ 4, 97, 42, 32 };

    const foo = Foo{
        .names = .{ "spell breaker", "obsidian destoryer", "shaman" },
        .qux = Qux{ .aa = 42 },
        .maybe = null,
        .maybe_maybe = "maybe not",
        .slice_of_qux = slice_of_qux,
        .slice_of_nums = &nums,
        .slice_of_baz = slice_of_baz,
        .text = "To: uwu\nHello, how are you?\nI'm fine thank you and you?",
    };

    const pretty = try allocPrettyPrint(allocator, foo);
    print("{s}\n", .{pretty});
}

test "listing  new" {
    // if (true) return error.SkipZigTest;
    print("\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    // const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    const parsed = blk: {

        // const file = @embedFile("testjson/listing_comment_author_deleted.json");
        // const file = @embedFile("testjson/listing_new_dota2.json");
        // const file = @embedFile("testjson/listing_new_zig_short.json");
        const file = @embedFile("testjson/listing_new_zig.json");
        // const file = @embedFile("testjson/listing_new3.json");
        // const file = @embedFile("testjson/listing_new_simple.json");

        const s = try allocator.dupe(u8, file);
        defer allocator.free(s);

        const parsed = try json.parseFromSlice(Thing, allocator, s, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        break :blk parsed;
    };
    defer parsed.deinit();

    // print("{any}\n", .{parsed.value});
    const pretty = try allocPrettyPrint(allocator, parsed.value);
    print("{s}\n", .{pretty});
}

test " json user comments" {
    // if (true) return error.SkipZigTest;

    print("\n", .{});

    // const allocator = std.heap.page_allocator;
    const allocator = std.testing.allocator;

    const parsed = blk: {
        const file = @embedFile("testjson/user_comment_spez.json");

        const s = try allocator.dupe(u8, file);
        defer allocator.free(s);

        const parsed = try json.parseFromSlice(Thing, allocator, s, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        break :blk parsed;
    };
    defer parsed.deinit();

    const pretty = try allocPrettyPrint(allocator, parsed.value);
    defer allocator.free(pretty);
    print("{s}\n", .{pretty});
}

test "account me" {
    // if (true) return error.SkipZigTest;

    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    const parsed = blk: {
        const file = @embedFile("testjson/me.json");

        const s = try allocator.dupe(u8, file);
        defer allocator.free(s);

        const Model = AccountMe;
        const parsed = try json.parseFromSlice(Model, allocator, s, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        break :blk parsed;
    };
    defer parsed.deinit();

    const root = parsed.value;

    const pretty = try allocPrettyPrint(allocator, root);
    print("{s}\n", .{pretty});
}

test " json listing comments" {
    if (true) return error.SkipZigTest;

    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    // const parsed = try json.parseFromSlice(JsonValue, allocator, s, .{
    const parsed = blk: {
        const file = @embedFile("testjson/comments.json");
        // const file = @embedFile("testjson/comments4_metadata.json");
        // const file = @embedFile("testjson/listing_comment_author_deleted.json");

        const s = try allocator.dupe(u8, file);
        defer allocator.free(s);

        const Model = [2]Thing;

        const parsed = try json.parseFromSlice(Model, allocator, s, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        break :blk parsed;
    };
    defer parsed.deinit();

    const root = parsed.value;

    const pretty = try allocPrettyPrint(allocator, root);
    print("{s}\n", .{pretty});
}
