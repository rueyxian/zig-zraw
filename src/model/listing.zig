const std = @import("std");
const debug = std.debug;
const json = std.json;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ParseOptions = std.json.ParseOptions;
const ParseError = std.json.ParseError;

const model = @import("../model.zig");

const Int = model.Int;
const Uint = model.Uint;
const Float = model.Float;
const String = model.String;

const Subreddit = model.Subreddit;
const SubredditType = model.SubredditType;
const Distinguished = model.Distinguished;

const ImplJsonParseEmptyObjectAsNullFn = model.ImplJsonParseEmptyObjectAsNullFn;
const ImplEnumJsonParseFn = model.ImplEnumJsonParseFn;
const ImplJsonParseTokenTypeAsNullFn = model.ImplJsonParseTokenTypeAsNullFn;
const ImplJsonParseEmptyStringAsNullFn = model.ImplJsonParseEmptyStringAsNullFn;
const fillDefaultStructValues = model.fillDefaultStructValues;

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
            }
            //
            else if (mem.eql(u8, kind_val, "t1")) {
                break :blk .{ .comment = try json.innerParse(*Comment, allocator, source, options) };
            }
            //
            else if (mem.eql(u8, kind_val, "t2")) {
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
    // modhash: ?String, // NOTE: unimplemented
    // geo_filter: String, // NOTE: unimplemented
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
    sr_detail: ?Subreddit = null,
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

pub const TextColor = enum {
    dark,
    light,
    pub const jsonParse = ImplEnumJsonParseFn(@This()).jsonParse;
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
