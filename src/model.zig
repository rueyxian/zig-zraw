const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ParseOptions = std.json.ParseOptions;
const Value = std.json.Value;
// const Parsed = std.json.Parsed;
// const Scanner = std.json.Scanner;
const Token = std.json.Token;
const TokenType = std.json.TokenType;
const ParseError = std.json.ParseError;

pub const Int = i64;
pub const Uint = u64;
pub const Float = f64;
pub const String = []const u8;

fn ImplEnumJsonParseFn(comptime T: type) type {
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

fn ImplJsonParseTokenTypeAsNullFn(comptime null_repr_token: TokenType, comptime T: type) type {
    return struct {
        fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !?T {
            if (try source.peekNextTokenType() == null_repr_token) {
                _ = try source.next();
                return null;
            }
            return try json.innerParse(T, allocator, source, options);
        }
    };
}

fn ImplJsonParseEmptyObjectAsNullFn(comptime T: type) type {
    return struct {
        fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !?T {
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

fn ImplJsonParseEmptyStringAsNullFn(comptime T: type) type {
    return struct {
        fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !?T {
            const Error = ParseError(@TypeOf(source.*));

            switch (try source.peekNextTokenType()) {
                .string => {
                    const s = try json.innerParse([]const u8, allocator, source, options);

                    // const s = switch (try source.next()) {
                    //     .string => |s| s,
                    //     else => return Error.UnexpectedToken,
                    // };
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

// NOTE stold from std/json/static.zig
fn fillDefaultStructValues(comptime T: type, r: *T, fields_seen: *[@typeInfo(T).Struct.fields.len]bool) !void {
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

pub const SubredditType = enum {
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

pub const TextType = enum {
    text,
    richtext,

    pub const jsonParse = ImplEnumJsonParseFn(@This()).jsonParse;
};

pub const MediaType = enum {
    img,
    gif,
    video,
    rich,

    pub const jsonParse = ImplEnumJsonParseFn(@This()).jsonParse;
};

pub const MediaEmbeded = struct {
    content: String,
    width: Uint,
    height: Uint,
    scrolling: bool,
};

fn jsonParseOptionalMediaEmbeded(allocator: Allocator, source: anytype, options: ParseOptions) !?MediaEmbeded {
    const Error = ParseError(@TypeOf(source.*));

    if (try source.next() != .object_begin) {
        return Error.UnexpectedToken;
    }

    if (try source.peekNextTokenType() == .object_end) {
        debug.assert(try source.next() == .object_end);
        return null;
    }

    var ret: MediaEmbeded = undefined;
    const info = @typeInfo(MediaEmbeded).Struct;

    while (true) {
        const field_name = switch (try source.next()) {
            .object_end => break,
            .string => |s| s,
            else => return Error.UnexpectedToken,
        };
        inline for (info.fields) |field| {
            if (mem.eql(u8, field_name, field.name)) {
                @field(ret, field.name) = try json.innerParse(field.type, allocator, source, options);
                break;
            }
        } else {
            if (options.ignore_unknown_fields) {
                try source.skipValue();
            } else {
                return error.UnknownField;
            }
        }
    }
    return ret;
}

pub const Media = struct {
    reddit_video: ?RedditVideo = null,
    oembed: ?Oembed = null,
    type: ?String = null,

    pub const RedditVideo = struct {
        bitrate_kbps: Uint,
        fallback_url: String,
        has_audio: bool,
        height: Uint,
        width: Uint,
        scrubber_media_url: String,
        dash_url: String,
        duration: Uint,
        hls_url: String,
        is_gif: bool,
        transcoding_status: String,
    };

    pub const Oembed = struct {
        provider_url: String,
        version: String,
        title: ?String = null,
        type: MediaType,
        thumbnail_width: ?Uint = null,
        height: ?Uint,
        width: Uint,
        html: String,
        author_name: ?String = null,
        provider_name: String,
        thumbnail_url: ?String = null,
        thumbnail_height: ?Uint = null,
        author_url: ?String = null,
        cache_age: ?Uint = null,
    };
};

pub const MediaMetadata = struct {
    id: String,
    status: String,
    e: String,
    m: String,
    ext: ?String = null,
    t: ?String = null,
    o: ?[]O = null,
    p: []P,
    s: ?S = null,
    pub const O = struct {
        x: Uint,
        y: Uint,
        u: String,
    };
    pub const P = struct {
        x: Uint,
        y: Uint,
        u: String,
    };
    pub const S = struct {
        x: Uint,
        y: Uint,
        u: ?String = null,
        gif: ?String = null,
        mp4: ?String = null,
    };
};

pub fn jsonParseMediaMetadataSlice(allocator: Allocator, source: anytype, options: ParseOptions) ![]MediaMetadata {
    const Error = ParseError(@TypeOf(source.*));

    // const value: Value = try json.innerParse(Value, allocator, source, options);
    // // _ = value; // autofix
    // // print("{any}\n", .{value});

    // const obj_map: json.ObjectMap = switch (value) {
    //     .object => |obj| obj,
    //     else => Error.UnexpectedToken,
    // };
    // debug.assert(obj_map.count != 0);

    // const ret = try std.ArrayList(MediaMetadata).initCapacity(allocator, obj_map.count);

    // // const ret: *MediaMetadata = try allocator.alloc(MediaMetadata);
    // // ret.ensureTotalCapacity(obj_map.count);
    // var it_obj = obj_map.iterator();
    // while (it_obj.next()) |e| {
    //     const val = try json.innerParseFromValue(MediaMetadata, allocator, e.value_ptr.*, options);
    //     // ret.putAssumeCapacityNoClobber(e.key_ptr.*, val);
    //     ret.appendAssumeCapacity(val);
    // }
    // // return ret;
    // return try ret.toOwnedSlice();

    // ==========================

    // const value: Value = try json.innerParse(Value, allocator, source, options);

    // const obj_map: json.ObjectMap = switch (value) {
    //     .object => |obj| obj,
    //     else => Error.UnexpectedToken,
    // };
    // debug.assert(obj_map.count != 0);

    // ==============================

    if (try source.next() != .object_begin) {
        return Error.UnexpectedToken;
    }
    var ret = std.ArrayList(MediaMetadata).init(allocator);
    while (true) {
        const field_name = switch (try source.next()) {
            .object_end => break,
            .string => |s| s,
            else => return Error.UnexpectedToken,
        };
        const val = try json.innerParse(MediaMetadata, allocator, source, options);
        // print("metadata id: {s}\n", .{field_name});
        debug.assert(mem.eql(u8, field_name, val.id));
        try ret.append(val);
    }
    return try ret.toOwnedSlice();
}

pub const TextColor = enum {
    dark,
    light,

    pub const jsonParse = ImplEnumJsonParseFn(@This()).jsonParse;
};

pub const FlairRichtext = union(enum) {
    emoji: struct {
        award: String,
        url: String,
    },
    text: String,

    pub fn jsonParse(allocator: Allocator, source: anytype, _: ParseOptions) !@This() {
        const Error = ParseError(@TypeOf(source.*));
        if (try source.next() != .object_begin) {
            return Error.UnexpectedToken;
        }
        // TODO to improve
        var opt_e: ?String = null;
        var opt_a: ?String = null;
        var opt_u: ?String = null;
        var opt_t: ?String = null;
        while (true) {
            const field_name: []const u8 = switch (try source.next()) {
                .object_end => break,
                .string => |s| s,
                else => return Error.UnexpectedToken,
            };
            const val: []const u8 = switch (try source.nextAlloc(allocator, .alloc_always)) {
                .allocated_string => |s| s,
                else => return Error.UnexpectedToken,
            };
            if (mem.eql(u8, field_name, "e")) {
                if (opt_e != null) return Error.UnexpectedToken;
                opt_e = val;
            } else if (mem.eql(u8, field_name, "a")) {
                if (opt_a != null) return Error.UnexpectedToken;
                opt_a = val;
            } else if (mem.eql(u8, field_name, "u")) {
                if (opt_u != null) return Error.UnexpectedToken;
                opt_u = val;
            } else if (mem.eql(u8, field_name, "t")) {
                if (opt_t != null) return Error.UnexpectedToken;
                opt_t = val;
            } else return Error.UnexpectedToken;
        }
        const e = opt_e orelse return Error.UnexpectedToken;
        if (mem.eql(u8, e, "text")) {
            if (opt_a != null or opt_u != null) return Error.UnexpectedToken;
            const t = opt_t orelse return Error.UnexpectedToken;
            return @This(){ .text = t };
        } else if (mem.eql(u8, e, "emoji")) {
            if (opt_t != null) return Error.UnexpectedToken;
            const a = opt_a orelse return Error.UnexpectedToken;
            const u = opt_u orelse return Error.UnexpectedToken;
            return @This(){ .emoji = .{ .award = a, .url = u } };
        } else return Error.UnexpectedToken;
        unreachable;
    }
};

pub const SrDetail = struct {
    default_set: bool,
    banner_img: String,
    // allowed_media_in_comments: ,  // NOTE: unimplemented
    user_is_banned: bool,
    free_form_reports: bool,
    community_icon: ?String,
    show_media: bool,
    description: String,
    // user_is_muted: ,  // NOTE: unimplemented
    display_name: String,
    // // header_img:  // NOTE: unimplemented
    title: String,
    // // previous_names:  // NOTE: unimplemented
    user_is_moderator: bool,
    over_18: bool,
    icon_size: [2]Uint,
    primary_color: String,
    icon_img: String,
    icon_color: String,
    submit_link_label: String,
    header_size: ?[2]Uint,
    restrict_posting: bool,
    restrict_commenting: bool,
    subscribers: Uint,
    submit_text_label: String,
    link_flair_position: String,
    // display_name_prefixed: String, // NOTE: unimplemented, duplicated data
    key_color: String,
    name: String,
    created: Uint,
    url: String,
    quarantine: bool,
    created_utc: Uint,
    banner_size: ?[2]Uint,
    user_is_contributor: bool,
    accept_followers: bool,
    public_description: String,
    link_flair_enabled: bool,
    disable_contributor_requests: bool,
    subreddit_type: SubredditType,
    user_is_subscriber: bool,
};

pub const Thing = union(enum) {
    listing: Listing,
    more: More,
    link: Link,
    comment: *Comment,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !Thing {
        const Error = ParseError(@TypeOf(source.*));

        // debug.assert(try source.next() == .object_start);

        if (try source.next() != .object_begin) {
            return Error.UnexpectedToken;
        }

        switch (try source.next()) {
            .string => |s| if (!mem.eql(u8, s, "kind")) {
                return Error.UnexpectedToken;
            },
            else => return Error.UnexpectedToken,
        }

        const kind_val = switch (try source.next()) {
            .string => |s| s,
            else => return Error.UnexpectedToken,
        };

        switch (try source.next()) {
            .string => |s| if (!mem.eql(u8, s, "data")) {
                return Error.UnexpectedToken;
            },
            else => return Error.UnexpectedToken,
        }

        // print("kind_val: {s}\n", .{kind_val});

        const thing: Thing = blk: {
            if (mem.eql(u8, kind_val, "Listing")) {
                break :blk .{ .listing = try json.innerParse(Listing, allocator, source, options) };
            } else if (mem.eql(u8, kind_val, "more")) {
                break :blk .{ .more = try json.innerParse(More, allocator, source, options) };
            } else if (mem.eql(u8, kind_val, "t1")) {
                break :blk .{ .comment = try json.innerParse(*Comment, allocator, source, options) };
            } else if (mem.eql(u8, kind_val, "t2")) {
                @panic("TODO");
            } else if (mem.eql(u8, kind_val, "t3")) {
                break :blk .{ .link = try json.innerParse(Link, allocator, source, options) };
            } else if (mem.eql(u8, kind_val, "t4")) {
                @panic("TODO");
            } else if (mem.eql(u8, kind_val, "t5")) {
                @panic("TODO");
            } else if (mem.eql(u8, kind_val, "t6")) {
                @panic("TODO");
            } else {}
            return Error.UnexpectedToken;
        };

        if (try source.next() != .object_end) {
            return Error.UnexpectedToken;
        }

        return thing;
    }
};

pub const More = struct {
    count: Uint,
    name: String,
    id: String,
    depth: Uint,
    children: []String,
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
    approved_at_utc: ?Uint,
    subreddit: String,
    selftext: String,
    author_fullname: ?String = null,
    saved: bool,
    mod_reason_title: ?String,
    // gilded: Uint, // NOTE: unimplemented
    clicked: bool,
    title: String,
    link_flair_richtext: []FlairRichtext,
    subreddit_name_prefixed: String,
    hidden: bool,
    // pwls: Uint,  // NOTE: unimplemented
    link_flair_css_class: ?String,
    downs: Int,
    // // top_awarded_type: null,  // NOTE: unimplemented
    hide_score: bool,
    media_metadata: ?[]MediaMetadata = null,
    name: String,
    quarantine: bool,
    link_flair_text_color: TextColor,
    upvote_ratio: Float,
    author_flair_background_color: ?String,
    subreddit_type: SubredditType,
    ups: Int,
    total_awards_received: Uint,
    media_embed: ?MediaEmbeded,
    author_flair_template_id: ?String,
    is_original_content: bool,
    // // user_reports: [],  // NOTE: unimplemented
    // // secure_media: null,  // NOTE: unimplemented
    is_reddit_media_domain: bool,
    // // is_meta: bool,  // NOTE: unimplemented
    // // category: null,  // NOTE: unimplemented
    secure_media_embed: ?MediaEmbeded,
    link_flair_text: ?String,
    // // can_mod_post: bool, // NOTE: unimplemented
    score: Int,
    approved_by: ?String,
    is_created_from_ads_ui: bool,
    author_premium: bool,
    thumbnail: String,
    edited: ?Uint,
    // // author_flair_css_class: null,  // NOTE: unimplemented
    author_flair_richtext: []FlairRichtext,
    // // gildings: {},  // NOTE: unimplemented
    // // content_categories: null,  // NOTE: unimplemented
    is_self: bool,
    // // mod_note: null, // NOTE: unimplemented
    created: Uint,
    link_flair_type: TextType,
    // // wls: 6,  // NOTE: unimplemented
    // // removed_by_category: null,  // NOTE: unimplemented
    // // banned_by: ?String, // NOTE: unimplemented
    author_flair_type: TextType,
    domain: String,
    // // // allow_live_comments: bool, // NOTE: unimplemented
    selftext_html: ?String,
    likes: ?bool,
    // // suggested_sort: null,  // NOTE: unimplemented
    // // banned_at_utc: ?Uint, // NOTE: unimplemented
    // // view_count: Uint, // NOTE: unimplemented
    archived: bool,
    no_follow: bool,
    is_crosspostable: bool,
    pinned: bool,
    over_18: bool,
    // // all_awardings: [],  // NOTE: unimplemented
    // // awarders: [],  // NOTE: unimplemented
    media_only: bool,
    sr_detail: ?SrDetail = null,
    // // can_gild: bool, // NOTE: unimplemented
    spoiler: bool,
    locked: bool,
    author_flair_text: ?String,
    // // treatment_tags: [],  // NOTE: unimplemented
    visited: bool,
    // // removed_by: ?String, // NOTE: unimplemented
    // // num_reports: Uint, // NOTE: unimplemented
    distinguished: ?Distinguished,
    subreddit_id: String,
    author_is_blocked: bool,
    // // mod_reason_by: null,   // NOTE: unimplemented
    // // removal_reason: null, // NOTE: unimplemented
    // // link_flair_background_color: "", // NOTE: unimplemented
    id: String,
    is_robot_indexable: bool,
    // // report_reasons: null,  // NOTE: unimplemented
    author: String,
    // // discussion_type: null,  // NOTE: unimplemented
    num_comments: Uint,
    send_replies: bool,
    // // whitelist_status: "all_ads",// NOTE: unimplemented
    // // contest_mode: false,  // NOTE: unimplemented
    // // mod_reports: [],  // NOTE: unimplemented
    // // author_patreon_flair: false, // NOTE: unimplemented
    // // author_flair_text_color: null,  // NOTE: unimplemented
    permalink: String,
    // // parent_whitelist_status: "all_ads" // NOTE: unimplemented,
    stickied: bool,
    url: String,
    subreddit_subscribers: Uint,
    created_utc: Uint,
    num_crossposts: Uint,
    media: ?Media,
    is_video: bool,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !@This() {
        const Error = ParseError(@TypeOf(source.*));

        if (try source.next() != .object_begin) {
            return Error.UnexpectedToken;
        }

        var ret: @This() = undefined;

        const info = @typeInfo(@This()).Struct;
        var fields_seen = [_]bool{false} ** info.fields.len;

        while (true) {
            const field_name = switch (try source.next()) {
                .object_end => break,
                .string => |s| s,
                else => return Error.UnexpectedToken,
            };

            inline for (info.fields, 0..) |field, i| {
                if (mem.eql(u8, field_name, field.name)) {
                    if (field.type == ?MediaEmbeded) {
                        @field(ret, field.name) = try ImplJsonParseEmptyObjectAsNullFn(MediaEmbeded).jsonParse(allocator, source, options);
                    } else if (mem.eql(u8, field.name, "edited")) {
                        const optional_info = switch (@typeInfo(field.type)) {
                            .Optional => |optional_info| optional_info,
                            else => unreachable,
                        };
                        const T = optional_info.child;
                        @field(ret, field.name) = try ImplJsonParseTokenTypeAsNullFn(.false, T).jsonParse(allocator, source, options);
                    } else if (field.type == ?[]MediaMetadata and mem.eql(u8, field_name, "media_metadata")) {
                        // const val = try jsonParseMediaMetadataSlice(allocator, source, options);
                        // @field(ret, field.name) = val;

                        @field(ret, field.name) = try jsonParseMediaMetadataSlice(allocator, source, options);
                    } else {
                        @field(ret, field.name) = try json.innerParse(field.type, allocator, source, options);
                    }
                    fields_seen[i] = true;
                    break;
                }
            } else {
                if (options.ignore_unknown_fields) {
                    try source.skipValue();
                } else {
                    return error.UnknownField;
                }
            }
        }
        try fillDefaultStructValues(@This(), &ret, &fields_seen);
        return ret;
    }
};

pub const Comment = struct {
    subreddit_id: String,
    approved_at_utc: ?Uint,
    author_is_blocked: bool,
    // comment_type: null,  // NOTE: unimplemented
    // awarders: [],  // NOTE: unimplemented
    // mod_reason_by: null,  // NOTE: unimplemented
    // banned_by: null,  // NOTE: unimplemented
    author_flair_type: ?TextType = null,
    total_awards_received: Uint,
    subreddit: String,
    author_flair_template_id: ?String,
    likes: ?bool,
    replies: ?Thing,
    // // // user_reports: [], // NOTE: unimplemented
    saved: bool,
    id: String,
    // // banned_at_utc: null, // NOTE: unimplemented
    // // mod_reason_title: null, // NOTE: unimplemented
    // // gilded: 0, // NOTE: unimplemented
    archived: bool,
    // // collapsed_reason_code: null,  // NOTE: unimplemented
    no_follow: bool,
    author: String,
    // // can_mod_post: false,  // NOTE: unimplemented
    created_utc: Uint,
    send_replies: bool,
    parent_id: String,
    score: Int,
    author_fullname: ?String = null,
    approved_by: ?String,
    // mod_note: null,  // NOTE: unimplemented
    // all_awardings: [],  // NOTE: unimplemented
    // collapsed: bool, // NOTE: unimplemented
    body: String,
    edited: ?Uint,
    // top_awarded_type: null, // NOTE: unimplemented
    // author_flair_css_class: null,  // NOTE: unimplemented
    name: String,
    is_submitter: bool,
    downs: Int,
    author_flair_richtext: ?[]FlairRichtext = null,
    // author_patreon_flair: false, // NOTE: unimplemented
    body_html: String,
    // removal_reason: null,  // NOTE: unimplemented
    // collapsed_reason: null,  // NOTE: unimplemented
    distinguished: ?Distinguished,
    // associated_award: null,  // NOTE: unimplemented
    stickied: bool,
    author_premium: ?bool = null,
    // can_gild: false, // NOTE: unimplemented
    // gildings: {},  // NOTE: unimplemented
    // unrepliable_reason: null,  // NOTE: unimplemented
    // author_flair_text_color: null,  // NOTE unimplemented
    score_hidden: bool,
    permalink: String,
    subreddit_type: SubredditType,
    locked: bool,
    // report_reasons: null, // NOTE unimplemented
    created: Uint,
    media_metadata: ?[]MediaMetadata = null,
    author_flair_text: ?String,
    // treatment_tags: [], // NOTE unimplemented
    link_id: String,
    subreddit_name_prefixed: String,
    // controversiality: 0, // NOTE unimplemented
    depth: ?Uint = null,
    author_flair_background_color: ?String,
    // collapsed_because_crowd_control: null, // NOTE unimplemented
    // mod_reports: [],  // NOTE unimplemented
    // num_reports: null,  // NOTE unimplemented
    ups: Int,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !@This() {
        const Error = ParseError(@TypeOf(source.*));
        if (try source.next() != .object_begin) {
            return Error.UnexpectedToken;
        }
        var ret: @This() = undefined;
        const info = @typeInfo(@This()).Struct;
        var fields_seen = [_]bool{false} ** info.fields.len;

        while (true) {
            const field_name = switch (try source.next()) {
                .object_end => break,
                .string => |s| s,
                else => return Error.UnexpectedToken,
            };
            inline for (info.fields, 0..) |field, i| {
                if (mem.eql(u8, field_name, field.name)) {
                    if (mem.eql(u8, field.name, "replies")) {
                        const optional_info = switch (@typeInfo(field.type)) {
                            .Optional => |optional_info| optional_info,
                            else => unreachable,
                        };
                        const T = optional_info.child;
                        debug.assert(T == Thing);
                        @field(ret, field.name) = try ImplJsonParseEmptyStringAsNullFn(T).jsonParse(allocator, source, options);
                    } else if (mem.eql(u8, field.name, "edited")) {
                        const optional_info = switch (@typeInfo(field.type)) {
                            .Optional => |optional_info| optional_info,
                            else => unreachable,
                        };
                        const T = optional_info.child;
                        @field(ret, field.name) = try ImplJsonParseTokenTypeAsNullFn(.false, T).jsonParse(allocator, source, options);
                    }

                    // else if (mem.eql(u8, field.name, "author_flair_background_color")) {
                    //     const optional_info = switch (@typeInfo(field.type)) {
                    //         .Optional => |optional_info| optional_info,
                    //         else => unreachable,
                    //     };
                    //     const T = optional_info.child;
                    //     debug.assert(T == Thing);
                    //     @field(ret, field.name) = try ImplJsonParseEmptyStringAsNullFn(T).jsonParse(allocator, source, options);
                    // }

                    else if (field.type == ?[]MediaMetadata and mem.eql(u8, field.name, "media_metadata")) {
                        @field(ret, field.name) = try jsonParseMediaMetadataSlice(allocator, source, options);
                    } else {
                        @field(ret, field.name) = try json.innerParse(field.type, allocator, source, options);
                    }
                    fields_seen[i] = true;
                    break;
                }
            } else {
                if (options.ignore_unknown_fields) {
                    try source.skipValue();
                } else {
                    return error.UnknownField;
                }
            }
        }
        try fillDefaultStructValues(@This(), &ret, &fields_seen);
        return ret;
    }
};

const UserComment = struct {
    //
};

const print = std.debug.print;

test "asdf" {
    if (true) return error.SkipZigTest;

    const allocator = std.heap.page_allocator;
    {
        var hm1 = std.StringHashMapUnmanaged(MediaMetadata){};
        var hm2 = std.StringHashMap(MediaMetadata).init(allocator);
        // var hm = std.StringArrayHashMapUnmanaged(usize){};
        defer hm1.deinit(allocator);
        defer hm2.deinit();

        print("size usize: {any}\n", .{@sizeOf(usize)});
        print("size hm1: {any}\n", .{@sizeOf(@TypeOf(hm1))});
        print("size hm2: {any}\n", .{@sizeOf(@TypeOf(hm2))});

        // print("cap: {any}\n", .{hm1.capacity()});

        // try hm.ensureTotalCapacity(allocator, 4);
        try hm1.ensureUnusedCapacity(allocator, 4);
        try hm2.ensureUnusedCapacity(4);

        print("size hm1: {any}\n", .{@sizeOf(@TypeOf(hm1))});
        print("size hm2: {any}\n", .{@sizeOf(@TypeOf(hm2))});
        // try hm.ensureTotalCapacity(4);
        // try hm.ensure(allocator, 12);
    }

    {
        const list = try std.ArrayList(usize).initCapacity(allocator, 3);
        print("{}\n", .{list.capacity});
    }

    // print("cap: {any}\n", .{hm1.capacity()});

    // hm.ensureTotalCapacityContext(, , )
    // hm.ensureTotalCapacity(, )

    // const link: Link = undefined;
    // print("{any}\n", .{link.sr_detail});
    // print("{any}\n", .{link.name});
}

test "customize json listing new" {
    if (true) return error.SkipZigTest;
    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    // const s = @embedFile("testjson/listing_comment_author_deleted.json");
    const s = @embedFile("testjson/listing_new_dota2.json");
    // const s = @embedFile("testjson/listing_new_zig.json");
    // const s = @embedFile("testjson/listing_new.json");
    // const s = @embedFile("testjson/listing_new3.json");
    // const s = @embedFile("testjson/listing_new2.json");

    const parsed = try json.parseFromSlice(Thing, allocator, s, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    // print("{any}\n", .{parsed.value});

    const children = parsed.value.listing.children;
    for (children) |thing| {
        const link = thing.link;
        print("title: {s}\n", .{link.title});
        // print("title: {any}\n", .{link.subreddit_type});
        // print("link flair type: {s}\n", .{link.link_flair_richtext});
        // print("sr type: {s}\n", .{link.sr_detail.?.subreddit_type});
        // print("sr_detail: {any}\n", .{link.sr_detail});

        // print("media embed: {any}\n", .{link.media_embed});

        // for (link.author_flair_richtext) |flair| {
        //     switch (flair) {
        //         .emoji => |e| {
        //             print("{s}\n", .{e.award});
        //             print("{s}\n", .{e.url});
        //             print("\n", .{});
        //         },
        //         .text => |t| {
        //             print("{s}\n", .{t});
        //             print("\n", .{});
        //         },
        //     }
        // }

        // link.media_metadata
        // if (link.media_metadata) |metadata| {
        //     for (metadata) |mt| {
        //         print("{any}\n", .{mt});
        //     }

        // } else {
        // }

        print("==================\n", .{});
    }
}

test " json user comments" {
    // if (true) return error.SkipZigTest;

    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    // const s = @embedFile("testjson/comments.json");
    const s = @embedFile("testjson/user_comment.json");
    // const s = @embedFile("testjson/listing_comment_author_deleted.json");

    const Model = Thing;
    // _ = Model; // autofix

    // const parsed = try json.parseFromSlice(JsonValue, allocator, s, .{
    const parsed = try json.parseFromSlice(Model, allocator, s, .{
        .ignore_unknown_fields = true,
    });
    // const root = parsed.value;

    const root = parsed.value;

    print("#######################\n", .{});

    // print("{any}\n", .{root[0]});
    // print("{any}\n", .{root[1]});

    {
        const comment_children = root.listing.children;

        for (comment_children) |child| {
            const comment = child.comment;
            // print("{s}\n", .{comment.body});
            print("{s}\n", .{comment.author});

            // for (comment.replies)
            if (comment.replies) |replies_thing| {
                const reply_children = replies_thing.listing.children;
                // print("   {any}\n", .{replies_thing});

                for (reply_children) |reply| {
                    const comment2 = reply.comment;

                    print("      {s}\n", .{comment2.author});
                }
            }
        }
    }

    // recurPrintComments(root[1], 0);
}

test " json listing comments" {
    if (true) return error.SkipZigTest;

    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    // const s = @embedFile("testjson/comments.json");
    const s = @embedFile("testjson/comments4_metadata.json");
    // const s = @embedFile("testjson/listing_comment_author_deleted.json");

    const Model = [2]Thing;
    // _ = Model; // autofix

    // const parsed = try json.parseFromSlice(JsonValue, allocator, s, .{
    const parsed = try json.parseFromSlice(Model, allocator, s, .{
        .ignore_unknown_fields = true,
    });
    // const root = parsed.value;

    const root = parsed.value;

    print("#######################\n", .{});
    print("#######################\n", .{});

    // print("{any}\n", .{root[0]});
    // print("{any}\n", .{root[1]});

    {
        const link_children = root[0].listing.children;
        _ = link_children; // autofix
    }

    recurPrintComments(root[1], 0);
}

fn recurPrintComments(thing: Thing, level: usize) void {
    //

    const children = thing.listing.children;

    const padding = "  > ";

    for (children) |child| {
        switch (child) {
            .comment => |comment| {
                // for (0..level) |_| print("{s}", .{padding});

                print("{s}: ", .{comment.author});
                print("{s}\n", .{comment.body});

                // print("\n", .{});

                // for (0..level) |_| print("{s}", .{padding});

                // // print("----------\n", .{});

                // if (comment.replies) |reply| {
                //     recurPrintComments(reply, level + 1);
                // }

                // print("{}\n", .{comment.media_metadata});

                if (comment.media_metadata) |metadata| {
                    // print("{}\n", .{metadata});
                    for (metadata) |mt| {
                        print("{any}\n", .{mt});
                        //
                    }
                }
            },
            .more => |more| {
                //

                for (0..level) |_| print("{s}", .{padding});

                print("more: \n", .{});

                for (more.children) |reply| {
                    print("{s}, ", .{reply});
                }

                print("\n", .{});

                for (0..level) |_| print("{s}", .{padding});

                // print("----------\n", .{});
            },
            else => unreachable,
        }
    }

    for (0..level) |_| print("{s}", .{padding});
    print("-------------\n", .{});
}
