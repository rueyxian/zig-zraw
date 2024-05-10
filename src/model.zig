const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ParseOptions = std.json.ParseOptions;
// const Value = std.json.Value;
// const Parsed = std.json.Parsed;
// const Scanner = std.json.Scanner;
const Token = std.json.Token;
// const TokenType = std.json.TokenType;
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

pub const Oembed = struct {
    provider_url: String,
    version: String,
    title: ?String = null,
    type: MediaType,
    thumbnail_width: ?Uint = null,
    height: ?Uint,
    width: Uint,
    html: String,
    author_name: String,
    provider_name: String,
    thumbnail_url: ?String = null,
    thumbnail_height: ?Uint = null,
    author_url: String,
    cache_age: ?Uint = null,
};

pub const Media = struct {
    type: String,
    oembed: Oembed,
};

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

        // var e: ?String = null;
        // var a: ?String = null;
        // var u: ?String = null;
        // var t: ?String = null;

        while (true) {
            const field_name = switch (try source.next()) {
                .string => |s| s,
                else => Error.UnexpectedToken,
            };
            print("fname: {any}\n", .{field_name});
            print("fname: {any}\n", .{@TypeOf(field_name)});
            const val = switch (try source.nextAlloc(allocator, .alloc_always)) {
                .object_end => break,
                .allocated_string => |s| s,
                else => Error.UnexpectedToken,
            };

            print("val: {any}\n", .{val});
            print("val: {any}\n", .{@TypeOf(val)});
            print("\n", .{});

            // if (mem.eql(u8, field_name, "e")) {
            //     if (e != null) return Error.UnexpectedToken;
            //     e = val;
            // } else if (mem.eql(u8, field_name, "a")) {
            //     if (a != null) return Error.UnexpectedToken;
            //     a = val;
            // } else if (mem.eql(u8, field_name, "u")) {
            //     if (u != null) return Error.UnexpectedToken;
            //     u = val;
            // } else if (mem.eql(u8, field_name, "t")) {
            //     if (t != null) return Error.UnexpectedToken;
            //     t = val;
            // } else Error.UnexpectedToken;
        }

        // if (mem.eql(u8, e, "text")) {
        //     if (a != null or u != null) return Error.UnexpectedToken;
        //     return @This(){ .text = t };
        // } else if (mem.eql(u8, e, "emoji")) {
        //     if (t != null) return Error.UnexpectedToken;
        //     return @This(){ .emoji = .{ .award = a, .url = u } };
        // } else Error.UnexpectedToken;
        return undefined;
    }
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

        const thing: Thing = if (mem.eql(u8, kind_val, "Listing"))
            .{ .listing = try json.innerParse(Listing, allocator, source, options) }
        else if (mem.eql(u8, kind_val, "more"))
            .{ .more = try json.innerParse(More, allocator, source, options) }
        else if (mem.eql(u8, kind_val, "t1"))
            .{ .comment = try json.innerParse(*Comment, allocator, source, options) }
        else if (mem.eql(u8, kind_val, "t2")) {
            @panic("TODO");
        } else if (mem.eql(u8, kind_val, "t3"))
            .{ .link = try json.innerParse(Link, allocator, source, options) }
        else if (mem.eql(u8, kind_val, "t4")) {
            @panic("TODO");
        } else if (mem.eql(u8, kind_val, "t5")) {
            @panic("TODO");
        } else if (mem.eql(u8, kind_val, "t6")) {
            @panic("TODO");
        } else return Error.UnexpectedToken;

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
    display_name_prefixed: String,
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
    author_fullname: String,
    saved: bool,
    mod_reason_title: ?String,
    // gilded: Uint, // NOTE: unimplemented
    clicked: bool,
    title: String,
    link_flair_richtext: []FlairRichtext,
    // subreddit_name_prefixed: String,
    // hidden: bool,
    // // pwls: Uint,  // NOTE: unimplemented
    // // link_flair_css_class: null,  // NOTE: unimplemented
    // downs: Uint,
    // // top_awarded_type: null,  // NOTE: unimplemented
    // hide_score: bool,
    // name: String,
    // quarantine: bool,
    // link_flair_text_color: TextColor, // TODO enum
    // upvote_ratio: Float,
    // // author_flair_background_color: null,
    subreddit_type: SubredditType,
    // ups: Uint,
    // total_awards_received: Uint,
    // // media_embed: {},  // NOTE: unimplemented
    // // author_flair_template_id: null,  // NOTE: unimplemented
    // is_original_content: bool,
    // // user_reports: [],  // NOTE: unimplemented
    // // secure_media: null,  // NOTE: unimplemented
    // is_reddit_media_domain: bool,
    // // is_meta: bool,  // NOTE: unimplemented
    // // category: null,  // NOTE: unimplemented
    // // secure_media_embed: {},  // NOTE: unimplemented
    // // link_flair_text: null,  // NOTE: unimplemented
    // can_mod_post: bool,
    // score: Int,
    // approved_by: ?String,
    // is_created_from_ads_ui: bool,
    // author_premium: bool,
    // // thumbnail: "",  // NOTE: unimplemented
    // edited: bool,
    // // author_flair_css_class: null,  // NOTE: unimplemented
    // // author_flair_richtext: [],  // NOTE: unimplemented
    // // gildings: {},  // NOTE: unimplemented
    // // content_categories: null,  // NOTE: unimplemented
    // is_self: bool,
    // // mod_note: null,
    // created: Uint,
    link_flair_type: TextType, // TODO enum
    // // wls: 6,  // NOTE: unimplemented
    // // removed_by_category: null,  // NOTE: unimplemented
    // banned_by: ?String,
    // // author_flair_type: TextType, // TODO enum
    // domain: String,
    // allow_live_comments: bool,
    // selftext_html: ?String,
    // likes: ?bool,
    // // suggested_sort: null,  // NOTE: unimplemented
    // banned_at_utc: ?Uint,
    // view_count: Uint,
    // archived: bool,
    // no_follow: bool,
    // is_crosspostable: bool,
    // pinned: bool,
    // over_18: bool,
    // // all_awardings: [],  // NOTE: unimplemented
    // // awarders: [],  // NOTE: unimplemented
    // media_only: bool,
    sr_detail: ?SrDetail = null,
    // can_gild: bool,
    // spoiler: bool,
    // locked: bool,
    // author_flair_text: bool,
    // // treatment_tags: [],  // NOTE: unimplemented
    // visited: bool,
    // removed_by: ?String,
    // num_reports: Uint,
    // // distinguished: ?Distinguished, // TODO
    // subreddit_id: String,
    // author_is_blocked: bool,
    // // mod_reason_by: null,   // NOTE: unimplemented
    // // removal_reason: null, // NOTE: unimplemented
    // // link_flair_background_color: "", // NOTE: unimplemented
    // id: String,
    // is_robot_indexable: bool,
    // // report_reasons: null,  // NOTE: unimplemented
    // author: String,
    // // discussion_type: null,  // NOTE: unimplemented
    // num_comments: Uint,
    // send_replies: bool,
    // // whitelist_status: "all_ads",// NOTE: unimplemented
    // // contest_mode: false,  // NOTE: unimplemented
    // // mod_reports: [],  // NOTE: unimplemented
    // // author_patreon_flair: false, // NOTE: unimplemented
    // // author_flair_text_color: null,  // NOTE: unimplemented
    // permalink: String,
    // // parent_whitelist_status: "all_ads" // NOTE: unimplemented,
    // stickied: bool,
    // url: String,
    // subreddit_subscribers: Uint,
    // created_utc: Uint,
    // num_crossposts: Uint,
    media: ?Media, // TODO
    // is_video: bool,

    // =================================

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !Link {
        const Error = ParseError(@TypeOf(source.*));

        // debug.assert(try source.next() == .object_start);

        if (try source.next() != .object_begin) {
            return Error.UnexpectedToken;
        }

        var ret: Link = undefined;
        // _ = link; // autofix

        const info = @typeInfo(Link).Struct;

        // var fields_seen = [_]bool{false} ** info.fields.len;
        // _ = fields_seen; // autofix

        // for (info.fields) |field| {
        //     _ = field; // autofix
        //     //
        // }

        while (true) {
            const field_name = switch (try source.next()) {
                .object_end => break,
                .string => |s| s,
                else => return Error.UnexpectedToken,
            };

            // if (mem.eql(u8, field_name, "LKULIUfads")) {
            //     //
            // } else {
            //     //
            // }

            print("field name: {s}\n", .{field_name});

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

            // const T = @TypeOf(@field(ret, field_name));
            // @field(ret, field_name) = json.innerParse(T, allocator, source, options);

            // const value: Value = try source.next();

            // const value = switch(try source.peekNextTokenType) {
            // };

        }

        return ret;
    }
};

pub const Comment = struct {
    name: String,
    body: ?String,
    replies: ?Thing,
    author: String,
};

const print = std.debug.print;

test "asdf" {
    if (true) return error.SkipZigTest;
    print("\n", .{});

    const info = @typeInfo(TextType).Enum;

    _ = info; // autofix

    const x = @as(TextType, @enumFromInt(1));

    print("{any}\n", .{x});

    // const link: Link = undefined;
    // print("{any}\n", .{link.sr_detail});
    // print("{any}\n", .{link.name});
}

test "customize json listing new" {
    // if (true) return error.SkipZigTest;
    print("\n", .{});

    const allocator = std.heap.page_allocator;
    // const allocator = std.testing.allocator;

    // const s = @embedFile("testjson/listing_new.json");
    const s = @embedFile("testjson/listing_new3.json");
    // const s = @embedFile("testjson/listing_new_simple.json");
    // const s = @embedFile("testjson/listing_new2.json");

    const parsed = try json.parseFromSlice(Thing, allocator, s, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    // print("{any}\n", .{parsed.value});

    const children = parsed.value.listing.children;
    for (children) |thing| {
        const link = thing.link;
        // print("title: {s}\n", .{link.title});
        // print("title: {any}\n", .{link.subreddit_type});
        print("link flair type: {any}\n", .{link.link_flair_type});
        // print("sr type: {s}\n", .{link.sr_detail.?.subreddit_type});
        // print("sr_detail: {any}\n", .{link.sr_detail});
        // print("text_color: {any}\n", .{link.link_flair_text_color});
        print("==================\n", .{});
    }

    // for (parsed.children) |link| {
    //     _ = link; // autofix
    // }
}
