const std = @import("std");
const debug = std.debug;
const print = std.debug.print;
const fmt = std.fmt;
const json = std.json;
const http = std.http;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;

const Encoder = std.base64.standard.Encoder;
const Decoder = std.base64.standard.Decoder;

const CowBytes = @import("cow_bytes.zig").CowBytes;

const AccessToken = @import("api/access_token.zig").AccessToken;
const New = @import("api/listing.zig").New;

const Number = u64;

test "walksdjf" {
    if (true) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const src = "hello zig";

    const encoded_length = Encoder.calcSize(src.len);
    const encoded_buffer = try allocator.alloc(u8, encoded_length);
    defer allocator.free(encoded_buffer);

    _ = Encoder.encode(encoded_buffer, src);

    print("\n", .{});
    print("{any}\n", .{src});
    print("{any}\n", .{encoded_buffer});
}

const testOptions = @import("util.zig").testOptions;
const TestOptions = @import("util.zig").TestOptions;

const domain_www = "https://www.reddit.com/";
const domain_oauth = "https://oauth.reddit.com/";

test "open" {
    if (true) return error.SkipZigTest;
    print("\n", .{});

    const opts: TestOptions = testOptions() orelse return error.SkipZigTest;

    // const allocator = std.heap.page_allocator;
    const allocator = std.testing.allocator;

    var client = Client{ .allocator = allocator };
    defer client.deinit();

    const token_payload = blk2: {
        const uri = try std.Uri.parse(domain_www ++ "api/v1/access_token");

        var req = blk: {
            const payload = try allocClientCredential(allocator, opts.user_id, opts.user_pass);
            defer allocator.free(payload);

            const authorization = try allocBasicAuthorization(allocator, opts.app_id, opts.app_pass);
            defer allocator.free(authorization);

            const headers = std.http.Client.Request.Headers{
                .authorization = .{ .override = authorization },
                .user_agent = .{ .override = opts.user_agent },
            };

            var buf: [2048]u8 = undefined;
            var req = try client.open(.POST, uri, .{
                .server_header_buffer = &buf,
                .headers = headers,
            });
            errdefer req.deinit();

            req.transfer_encoding = .{ .content_length = payload.len };
            try req.send();
            try req.writer().writeAll(payload);

            try req.finish();
            try req.wait();

            break :blk req;
        };
        defer req.deinit();

        try std.testing.expectEqual(req.response.status, .ok);

        const payload = try req.reader().readAllAlloc(allocator, 1024 * 1024);
        // defer allocator.free(payload);

        break :blk2 payload;
    };
    defer allocator.free(token_payload);

    print("connection_pool used len: {}\n", .{client.connection_pool.used.len});
    print("connection_pool free len: {}\n", .{client.connection_pool.free_len});

    const parsed_token = try json.parseFromSlice(AccessToken.Payload, allocator, token_payload, .{});
    defer parsed_token.deinit();

    const new_payload = blk2: {
        const Context = New("zig");
        const endpoint = try parseEndpoint(allocator, Context{});
        defer endpoint.deinit(allocator);
        const uri = try std.Uri.parse(endpoint.bytes);

        var req = blk: {
            const authorization = try allocBearerAuthorization(allocator, parsed_token.value.token_type, parsed_token.value.access_token);
            defer allocator.free(authorization);

            const headers = std.http.Client.Request.Headers{
                .authorization = .{ .override = authorization },
                .user_agent = .{ .override = opts.user_agent },
            };

            var buf: [1024 * 1024]u8 = undefined;
            var req = try client.open(Context.method, uri, .{
                .server_header_buffer = &buf,
                .headers = headers,
            });
            errdefer req.deinit();

            // req.transfer_encoding = .{ .content_length = payload.len };
            try req.send();
            // try req.writer().writeAll(payload);

            try req.finish();
            try req.wait();

            break :blk req;
        };
        defer req.deinit();

        try std.testing.expectEqual(req.response.status, .ok);

        const payload = try req.reader().readAllAlloc(allocator, 1024 * 1024);
        // defer allocator.free(payload);

        break :blk2 payload;
    };
    defer allocator.free(new_payload);

    print("connection_pool used len: {}\n", .{client.connection_pool.used.len});
    print("connection_pool free len: {}\n", .{client.connection_pool.free_len});

    // print("new payload: {s}\n", .{new_payload});
}

test "fetch" {
    if (true) return error.SkipZigTest;
    print("\n", .{});

    const opts: TestOptions = testOptions() orelse return error.SkipZigTest;

    // const allocator = std.heap.page_allocator;
    const allocator = std.testing.allocator;

    var client = Client{ .allocator = allocator };
    defer client.deinit();

    const token_payload = blk: {
        const payload = try allocClientCredential(allocator, opts.user_id, opts.user_pass);
        defer allocator.free(payload);

        const authorization = try allocBasicAuthorization(allocator, opts.app_id, opts.app_pass);
        defer allocator.free(authorization);

        const headers = std.http.Client.Request.Headers{
            .authorization = .{ .override = authorization },
            .user_agent = .{ .override = opts.user_agent },
        };

        var buffer = std.ArrayList(u8).init(allocator);

        const fetch_options = std.http.Client.FetchOptions{
            .location = .{ .url = domain_www ++ "api/v1/access_token" },
            .method = .POST,
            .payload = payload,
            .headers = headers,
            .response_storage = .{ .dynamic = &buffer },
        };

        _ = try client.fetch(fetch_options);
        break :blk buffer.items;
    };
    defer allocator.free(token_payload);

    const parsed_token = try json.parseFromSlice(AccessToken.Payload, allocator, token_payload, .{});
    defer parsed_token.deinit();

    print("connection_pool used len: {}\n", .{client.connection_pool.used.len});
    print("connection_pool free len: {}\n", .{client.connection_pool.free_len});

    const new_payload = blk: {
        const authorization = try allocBearerAuthorization(allocator, parsed_token.value.token_type, parsed_token.value.access_token);
        defer allocator.free(authorization);

        const headers = std.http.Client.Request.Headers{
            .authorization = .{ .override = authorization },
            .user_agent = .{ .override = opts.user_agent },
        };

        var buffer = std.ArrayList(u8).init(allocator);

        const Context = New("zig");

        const endpoint = try parseEndpoint(allocator, Context{});
        defer endpoint.deinit(allocator);

        const fetch_options = std.http.Client.FetchOptions{
            .location = .{ .url = endpoint.bytes },
            .method = Context.method,
            .payload = null,
            .headers = headers,
            .response_storage = .{ .dynamic = &buffer },
        };
        _ = try client.fetch(fetch_options);
        break :blk buffer.items;
    };
    defer allocator.free(new_payload);

    print("connection_pool used len: {}\n", .{client.connection_pool.used.len});
    print("connection_pool free len: {}\n", .{client.connection_pool.free_len});
}

test "fetch buf" {
    // if (true) return error.SkipZigTest;
    print("\n", .{});

    const opts: TestOptions = testOptions() orelse return error.SkipZigTest;

    // const allocator = std.heap.page_allocator;
    const allocator = std.testing.allocator;

    var client = Client{ .allocator = allocator };
    defer client.deinit();

    var resp_buf: [1 << 20]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&resp_buf);

    var buffer = std.ArrayListUnmanaged(u8){};
    try buffer.ensureTotalCapacity(fba.allocator(), 2024);
    // defer buffer.deinit(allodicator);

    const token_payload = blk: {
        const payload = try allocClientCredential(allocator, opts.user_id, opts.user_pass);
        defer allocator.free(payload);

        const authorization = try allocBasicAuthorization(allocator, opts.app_id, opts.app_pass);
        defer allocator.free(authorization);

        const headers = std.http.Client.Request.Headers{
            .authorization = .{ .override = authorization },
            .user_agent = .{ .override = opts.user_agent },
        };

        var buf: [2024]u8 = undefined;

        const fetch_options = std.http.Client.FetchOptions{
            .server_header_buffer = &buf,
            .location = .{ .url = domain_www ++ "api/v1/access_token" },
            .method = .POST,
            .payload = payload,
            .headers = headers,
            .response_storage = .{ .static = &buffer },
            // .response_storage = .{.ignore},
        };

        _ = try client.fetch(fetch_options);

        // print("buffer: {s}\n", .{buffer.items});
        // print("buf: {s}\n", .{buf});

        break :blk buffer.items;
        // break :blk;
    };
    // defer allocator.free(token_payload);

    print("buffer: {s}\n", .{token_payload});

    // const parsed_token = try json.parseFromSlice(AccessToken.Payload, allocator, token_payload, .{});
    // defer parsed_token.deinit();

    // print("connection_pool used len: {}\n", .{client.connection_pool.used.len});
    // print("connection_pool free len: {}\n", .{client.connection_pool.free_len});

    // const new_payload = blk: {
    //     const authorization = try allocBearerAuthorization(allocator, parsed_token.value.token_type, parsed_token.value.access_token);
    //     defer allocator.free(authorization);

    //     const headers = std.http.Client.Request.Headers{
    //         .authorization = .{ .override = authorization },
    //         .user_agent = .{ .override = opts.user_agent },
    //     };

    //     var buffer = std.ArrayList(u8).init(allocator);

    //     const Context = New("zig");

    //     const endpoint = try parseEndpoint(allocator, Context{});
    //     defer endpoint.deinit(allocator);

    //     const fetch_options = std.http.Client.FetchOptions{
    //         .location = .{ .url = endpoint.bytes },
    //         .method = Context.method,
    //         .payload = null,
    //         .headers = headers,
    //         .response_storage = .{ .dynamic = &buffer },
    //     };
    //     _ = try client.fetch(fetch_options);
    //     break :blk buffer.items;
    // };
    // defer allocator.free(new_payload);

    // print("connection_pool used len: {}\n", .{client.connection_pool.used.len});
    // print("connection_pool free len: {}\n", .{client.connection_pool.free_len});
}

fn parseEndpoint(allocator: Allocator, context: anytype) !CowBytes([]const u8) {
    const Context = @TypeOf(context);
    const info = @typeInfo(Context);
    debug.assert(info == .Struct);

    const fields = info.Struct.fields;

    if (fields.len == 0) {
        return CowBytes([]const u8).borrowed(Context.endpoint);
    }

    const buf = try allocator.alloc(u8, endpointLength(context));
    var fba = std.io.fixedBufferStream(buf);
    const w = fba.writer();
    try w.writeAll(Context.endpoint);

    var i: usize = 0;
    inline for (fields) |field| {
        if (@field(context, field.name)) |val| {
            try w.writeByte(([_]u8{ '?', '&' })[@intFromBool(i != 0)]);
            try w.writeAll(field.name);
            try w.writeByte('=');
            switch (@TypeOf(val)) {
                []const u8 => try w.writeAll(val),
                Number => {
                    var _buf: [maxUintLength(Number)]u8 = undefined;
                    const s = try std.fmt.bufPrint(&_buf, "{}", .{val});
                    try w.writeAll(s);
                },
                else => unreachable,
            }
            i += 1;
        }
    }
    debug.assert(try fba.getPos() == buf.len);
    return CowBytes([]const u8).owned(fba.getWritten());
}

fn endpointLength(context: anytype) usize {
    const Context = @TypeOf(context);
    const info = @typeInfo(Context);
    debug.assert(info == .Struct);
    var res = Context.endpoint.len;
    const fields = info.Struct.fields;

    inline for (fields) |field| {
        if (@field(context, field.name)) |val| {
            res += 2; // ('?' or '&') + '='
            res += field.name.len;
            switch (@TypeOf(val)) {
                []const u8 => res += val.len,
                Number => res += uintLength(Number, val),
                else => unreachable,
            }
        }
    }
    return res;
}

fn maxUintLength(comptime T: type) usize {
    const info = @typeInfo(T);
    debug.assert(info == .Int);
    debug.assert(info.Int.signedness == .unsigned);
    comptime var res: usize = 0;
    comptime var num = std.math.maxInt(T);
    inline while (num != 0) {
        num /= 10;
        res += 1;
    }
    return res;
}

fn uintLength(comptime T: type, number: T) usize {
    const info = @typeInfo(T);
    debug.assert(info == .Int);
    debug.assert(info.Int.signedness == .unsigned);
    const pow_tens = blk: {
        var tens: [maxUintLength(T) - 1]T = undefined;
        inline for (&tens, 1..) |*n, i| {
            n.* = std.math.pow(T, 10, i);
        }
        break :blk tens;
    };
    var i: usize = 1;
    for (pow_tens) |n| {
        if (number < n) break;
        i += 1;
    }
    return i;
}

pub fn allocClientCredential(allocator: Allocator, user_id: []const u8, user_pass: []const u8) ![]const u8 {
    return try fmt.allocPrint(allocator, "grant_type=password&username={s}&password={s}", .{ user_id, user_pass });
}

pub fn allocBasicAuthorization(allocator: Allocator, app_id: []const u8, app_pass: []const u8) ![]const u8 {
    const Base64Encoder = std.base64.standard.Encoder;
    const src = try fmt.allocPrint(allocator, "{s}:{s}", .{ app_id, app_pass });
    defer allocator.free(src);
    const encoded = try allocator.alloc(u8, Base64Encoder.calcSize(src.len));
    defer allocator.free(encoded);
    _ = Base64Encoder.encode(encoded, src);
    return fmt.allocPrint(allocator, "Basic {s}", .{encoded});
}

pub fn allocBearerAuthorization(allocator: Allocator, token_type: []const u8, access_token: []const u8) ![]const u8 {
    return fmt.allocPrint(allocator, "{s} {s}", .{ token_type, access_token });
}

// "approved_at_utc": null,
// "subreddit": "Zig",
// "selftext": "I use zig with raylib-zig but I don't quite understand how to draw formatted text. I have the following problem: I want to draw this formatted string “Ticks: {d}” with the function drawText(text: \\[:0\\]const u8, ...).\n\nSo far so good, I format the string   \n`var buf: [100]u8 = undefined;`  \n`const res = try fmt.bufPrint(&amp;buf, \"Ticks {d}\", .{nes.ticks});`  \n and now I have `res` with the type of `[]u8` but i need a `[:0]const u8` and i'm a bit lost to be honest. I am still quite new to the language and have not yet understood everything in the documentation so I would be very grateful if someone could help me. Oh and how exactly can I format code on reddit?",
// "author_fullname": "t2_3hxbmx00",
// "saved": false,
// "mod_reason_title": null,
// "gilded": 0,
// "clicked": false,
// "title": "I don't get how I can convert a []u8 to a [:0]const u8",
// "link_flair_richtext": [],
// "subreddit_name_prefixed": "r/Zig",
// "hidden": false,
// "pwls": 6,
// "link_flair_css_class": null,
// "downs": 0,
// "top_awarded_type": null,
// "hide_score": false,
// "name": "t3_1chue6x",
// "quarantine": false,
// "link_flair_text_color": "dark",
// "upvote_ratio": 0.9,
// "author_flair_background_color": null,
// "subreddit_type": "public",
// "ups": 7,
// "total_awards_received": 0,
// "media_embed": {},
// "author_flair_template_id": null,
// "is_original_content": false,
// "user_reports": [],
// "secure_media": null,
// "is_reddit_media_domain": false,
// "is_meta": false,
// "category": null,
// "secure_media_embed": {},
// "link_flair_text": null,
// "can_mod_post": false,
// "score": 7,
// "approved_by": null,
// "is_created_from_ads_ui": false,
// "author_premium": false,
// "thumbnail": "",
// "edited": false,
// "author_flair_css_class": null,
// "author_flair_richtext": [],
// "gildings": {},
// "content_categories": null,
// "is_self": true,
// "mod_note": null,
// "created": 1714590482.0,
// "link_flair_type": "text",
// "wls": 6,
// "removed_by_category": null,
// "banned_by": null,
// "author_flair_type": "text",
// "domain": "self.Zig",
// "allow_live_comments": false,
// "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;I use zig with raylib-zig but I don&amp;#39;t quite understand how to draw formatted text. I have the following problem: I want to draw this formatted string “Ticks: {d}” with the function drawText(text: [:0]const u8, ...).&lt;/p&gt;\n\n&lt;p&gt;So far so good, I format the string&lt;br/&gt;\n&lt;code&gt;var buf: [100]u8 = undefined;&lt;/code&gt;&lt;br/&gt;\n&lt;code&gt;const res = try fmt.bufPrint(&amp;amp;buf, &amp;quot;Ticks {d}&amp;quot;, .{nes.ticks});&lt;/code&gt;&lt;br/&gt;\n and now I have &lt;code&gt;res&lt;/code&gt; with the type of &lt;code&gt;[]u8&lt;/code&gt; but i need a &lt;code&gt;[:0]const u8&lt;/code&gt; and i&amp;#39;m a bit lost to be honest. I am still quite new to the language and have not yet understood everything in the documentation so I would be very grateful if someone could help me. Oh and how exactly can I format code on reddit?&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
// "likes": null,
// "suggested_sort": null,
// "banned_at_utc": null,
// "view_count": null,
// "archived": false,
// "no_follow": false,
// "is_crosspostable": true,
// "pinned": false,
// "over_18": false,
// "all_awardings": [],
// "awarders": [],
// "media_only": false,
// "can_gild": false,
// "spoiler": false,
// "locked": false,
// "author_flair_text": null,
// "treatment_tags": [],
// "visited": false,
// "removed_by": null,
// "num_reports": null,
// "distinguished": null,
// "subreddit_id": "t5_3cf47",
// "author_is_blocked": false,
// "mod_reason_by": null,
// "removal_reason": null,
// "link_flair_background_color": "",
// "id": "1chue6x",
// "is_robot_indexable": true,
// "report_reasons": null,
// "author": "Zeusenikus",
// "discussion_type": null,
// "num_comments": 4,
// "send_replies": true,
// "whitelist_status": "all_ads",
// "contest_mode": false,
// "mod_reports": [],
// "author_patreon_flair": false,
// "author_flair_text_color": null,
// "permalink": "/r/Zig/comments/1chue6x/i_dont_get_how_i_can_convert_a_u8_to_a_0const_u8/",
// "parent_whitelist_status": "all_ads",
// "stickied": false,
// "url": "https://www.reddit.com/r/Zig/comments/1chue6x/i_dont_get_how_i_can_convert_a_u8_to_a_0const_u8/",
// "subreddit_subscribers": 12830,
// "created_utc": 1714590482.0,
// "num_crossposts": 0,
// "media": null,
// "is_video": false

// "approved_at_utc": null,
// "subreddit": "Zig",
// "selftext": "I use zig with raylib-zig but I don't quite understand how to draw formatted text. I have the following problem: I want to draw this formatted string “Ticks: {d}” with the function drawText(text: \\[:0\\]const u8, ...).\n\nSo far so good, I format the string   \n`var buf: [100]u8 = undefined;`  \n`const res = try fmt.bufPrint(&amp;buf, \"Ticks {d}\", .{nes.ticks});`  \n and now I have `res` with the type of `[]u8` but i need a `[:0]const u8` and i'm a bit lost to be honest. I am still quite new to the language and have not yet understood everything in the documentation so I would be very grateful if someone could help me. Oh and how exactly can I format code on reddit?",
// "author_fullname": "t2_3hxbmx00",
// "saved": false,
// "mod_reason_title": null,
// "gilded": 0,
// "clicked": false,
// "title": "I don't get how I can convert a []u8 to a [:0]const u8",
// "link_flair_richtext": [],
// "subreddit_name_prefixed": "r/Zig",
// "hidden": false,
// "pwls": 6,
// "link_flair_css_class": null,
// "downs": 0,
// "top_awarded_type": null,
// "hide_score": false,
// "name": "t3_1chue6x",
// "quarantine": false,
// "link_flair_text_color": "dark",
// "upvote_ratio": 1.0,
// "author_flair_background_color": null,
// "subreddit_type": "public",
// "ups": 8,
// "total_awards_received": 0,
// "media_embed": {},
// "author_flair_template_id": null,
// "is_original_content": false,
// "user_reports": [],
// "secure_media": null,
// "is_reddit_media_domain": false,
// "is_meta": false,
// "category": null,
// "secure_media_embed": {},
// "link_flair_text": null,
// "can_mod_post": false,
// "score": 8,
// "approved_by": null,
// "is_created_from_ads_ui": false,
// "author_premium": false,
// "thumbnail": "",
// "edited": false,
// "author_flair_css_class": null,
// "author_flair_richtext": [],
// "gildings": {},
// "content_categories": null,
// "is_self": true,
// "mod_note": null,
// "created": 1714590482.0,
// "link_flair_type": "text",
// "wls": 6,
// "removed_by_category": null,
// "banned_by": null,
// "author_flair_type": "text",
// "domain": "self.Zig",
// "allow_live_comments": false,
// "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;I use zig with raylib-zig but I don&amp;#39;t quite understand how to draw formatted text. I have the following problem: I want to draw this formatted string “Ticks: {d}” with the function drawText(text: [:0]const u8, ...).&lt;/p&gt;\n\n&lt;p&gt;So far so good, I format the string&lt;br/&gt;\n&lt;code&gt;var buf: [100]u8 = undefined;&lt;/code&gt;&lt;br/&gt;\n&lt;code&gt;const res = try fmt.bufPrint(&amp;amp;buf, &amp;quot;Ticks {d}&amp;quot;, .{nes.ticks});&lt;/code&gt;&lt;br/&gt;\n and now I have &lt;code&gt;res&lt;/code&gt; with the type of &lt;code&gt;[]u8&lt;/code&gt; but i need a &lt;code&gt;[:0]const u8&lt;/code&gt; and i&amp;#39;m a bit lost to be honest. I am still quite new to the language and have not yet understood everything in the documentation so I would be very grateful if someone could help me. Oh and how exactly can I format code on reddit?&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
// "likes": null,
// "suggested_sort": null,
// "banned_at_utc": null,
// "view_count": null,
// "archived": false,
// "no_follow": false,
// "is_crosspostable": true,
// "pinned": false,
// "over_18": false,
// "all_awardings": [],
// "awarders": [],
// "media_only": false,
// "can_gild": false,
// "spoiler": false,
// "locked": false,
// "author_flair_text": null,
// "treatment_tags": [],
// "visited": false,
// "removed_by": null,
// "num_reports": null,
// "distinguished": null,
// "subreddit_id": "t5_3cf47",
// "author_is_blocked": false,
// "mod_reason_by": null,
// "removal_reason": null,
// "link_flair_background_color": "",
// "id": "1chue6x",
// "is_robot_indexable": true,
// "report_reasons": null,
// "author": "Zeusenikus",
// "discussion_type": null,
// "num_comments": 4,
// "send_replies": true,
// "whitelist_status": "all_ads",
// "contest_mode": false,
// "mod_reports": [],
// "author_patreon_flair": false,
// "author_flair_text_color": null,
// "permalink": "/r/Zig/comments/1chue6x/i_dont_get_how_i_can_convert_a_u8_to_a_0const_u8/",
// "parent_whitelist_status": "all_ads",
// "stickied": false,
// "url": "https://www.reddit.com/r/Zig/comments/1chue6x/i_dont_get_how_i_can_convert_a_u8_to_a_0const_u8/",
// "subreddit_subscribers": 12830,
// "created_utc": 1714590482.0,
// "num_crossposts": 0,
// "media": null,
// "is_video": false
