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
const New = @import("api/listings.zig").New;

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

// {
//     "kind": "Listing",
//     "data": {
//         "after": "t3_1cew16o",
//         "dist": 9,
//         "modhash": null,
//         "geo_filter": "",
//         "children": [
//             {
//                 "kind": "t3",
//                 "data": {
//                     "approved_at_utc": null,
//                     "subreddit": "Zig",
//                     "selftext": "https://preview.redd.it/c41mj7styixc1.png?width=956&amp;format=png&amp;auto=webp&amp;s=3ae608fe62ff234fe55fe854aee414a8b44176d5\n\nSurely this is not how you are supposed to do this, but I cant find anything in the docs or anywhere else except one outdated tutorial that uses absolute paths, which are now illegal.",
//                     "author_fullname": "t2_h5pi29pox",
//                     "saved": false,
//                     "mod_reason_title": null,
//                     "gilded": 0,
//                     "clicked": false,
//                     "title": "Is there really not a better way to do this??",
//                     "link_flair_richtext": [],
//                     "subreddit_name_prefixed": "r/Zig",
//                     "hidden": false,
//                     "pwls": 6,
//                     "link_flair_css_class": null,
//                     "downs": 0,
//                     "top_awarded_type": null,
//                     "hide_score": true,
//                     "media_metadata": {
//                         "c41mj7styixc1": {
//                             "status": "valid",
//                             "e": "Image",
//                             "m": "image/png",
//                             "p": [
//                                 {
//                                     "y": 13,
//                                     "x": 108,
//                                     "u": "https://preview.redd.it/c41mj7styixc1.png?width=108&amp;crop=smart&amp;auto=webp&amp;s=e587361a238d3c2aebbc13ddf5c46036cd295ab4"
//                                 },
//                                 {
//                                     "y": 27,
//                                     "x": 216,
//                                     "u": "https://preview.redd.it/c41mj7styixc1.png?width=216&amp;crop=smart&amp;auto=webp&amp;s=e5d1163521ad9041941c2b3aa30d42ca94efbac0"
//                                 },
//                                 {
//                                     "y": 40,
//                                     "x": 320,
//                                     "u": "https://preview.redd.it/c41mj7styixc1.png?width=320&amp;crop=smart&amp;auto=webp&amp;s=08b2f44c7731f28375cf53ff760bfb5df6a18273"
//                                 },
//                                 {
//                                     "y": 80,
//                                     "x": 640,
//                                     "u": "https://preview.redd.it/c41mj7styixc1.png?width=640&amp;crop=smart&amp;auto=webp&amp;s=e4e35cb2376c6efb8a40cb0376bd3a18f3e07979"
//                                 }
//                             ],
//                             "s": {
//                                 "y": 120,
//                                 "x": 956,
//                                 "u": "https://preview.redd.it/c41mj7styixc1.png?width=956&amp;format=png&amp;auto=webp&amp;s=3ae608fe62ff234fe55fe854aee414a8b44176d5"
//                             },
//                             "id": "c41mj7styixc1"
//                         }
//                     },
//                     "name": "t3_1cghc5i",
//                     "quarantine": false,
//                     "link_flair_text_color": "dark",
//                     "upvote_ratio": 0.81,
//                     "author_flair_background_color": null,
//                     "subreddit_type": "public",
//                     "ups": 3,
//                     "total_awards_received": 0,
//                     "media_embed": {},
//                     "author_flair_template_id": null,
//                     "is_original_content": false,
//                     "user_reports": [],
//                     "secure_media": null,
//                     "is_reddit_media_domain": false,
//                     "is_meta": false,
//                     "category": null,
//                     "secure_media_embed": {},
//                     "link_flair_text": null,
//                     "can_mod_post": false,
//                     "score": 3,
//                     "approved_by": null,
//                     "is_created_from_ads_ui": false,
//                     "author_premium": false,
//                     "thumbnail": "",
//                     "edited": false,
//                     "author_flair_css_class": null,
//                     "author_flair_richtext": [],
//                     "gildings": {},
//                     "content_categories": null,
//                     "is_self": true,
//                     "mod_note": null,
//                     "created": 1714442818.0,
//                     "link_flair_type": "text",
//                     "wls": 6,
//                     "removed_by_category": null,
//                     "banned_by": null,
//                     "author_flair_type": "text",
//                     "domain": "self.Zig",
//                     "allow_live_comments": false,
//                     "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;&lt;a href=\"https://preview.redd.it/c41mj7styixc1.png?width=956&amp;amp;format=png&amp;amp;auto=webp&amp;amp;s=3ae608fe62ff234fe55fe854aee414a8b44176d5\"&gt;https://preview.redd.it/c41mj7styixc1.png?width=956&amp;amp;format=png&amp;amp;auto=webp&amp;amp;s=3ae608fe62ff234fe55fe854aee414a8b44176d5&lt;/a&gt;&lt;/p&gt;\n\n&lt;p&gt;Surely this is not how you are supposed to do this, but I cant find anything in the docs or anywhere else except one outdated tutorial that uses absolute paths, which are now illegal.&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
//                     "likes": null,
//                     "suggested_sort": null,
//                     "banned_at_utc": null,
//                     "view_count": null,
//                     "archived": false,
//                     "no_follow": false,
//                     "is_crosspostable": true,
//                     "pinned": false,
//                     "over_18": false,
//                     "all_awardings": [],
//                     "awarders": [],
//                     "media_only": false,
//                     "can_gild": false,
//                     "spoiler": false,
//                     "locked": false,
//                     "author_flair_text": null,
//                     "treatment_tags": [],
//                     "visited": false,
//                     "removed_by": null,
//                     "num_reports": null,
//                     "distinguished": null,
//                     "subreddit_id": "t5_3cf47",
//                     "author_is_blocked": false,
//                     "mod_reason_by": null,
//                     "removal_reason": null,
//                     "link_flair_background_color": "",
//                     "id": "1cghc5i",
//                     "is_robot_indexable": true,
//                     "report_reasons": null,
//                     "author": "QuestionableEthics42",
//                     "discussion_type": null,
//                     "num_comments": 0,
//                     "send_replies": true,
//                     "whitelist_status": "all_ads",
//                     "contest_mode": false,
//                     "mod_reports": [],
//                     "author_patreon_flair": false,
//                     "author_flair_text_color": null,
//                     "permalink": "/r/Zig/comments/1cghc5i/is_there_really_not_a_better_way_to_do_this/",
//                     "parent_whitelist_status": "all_ads",
//                     "stickied": false,
//                     "url": "https://www.reddit.com/r/Zig/comments/1cghc5i/is_there_really_not_a_better_way_to_do_this/",
//                     "subreddit_subscribers": 12771,
//                     "created_utc": 1714442818.0,
//                     "num_crossposts": 0,
//                     "media": null,
//                     "is_video": false
//                 }
//             },
//             {
//                 "kind": "t3",
//                 "data": {
//                     "approved_at_utc": null,
//                     "subreddit": "Zig",
//                     "selftext": "Hi Ziglers! Ziglets? Zigulons? Anyway, apologies for the sort-of crossposting but I posted this to ziggit:\n\n[https://ziggit.dev/t/logging-a-stack-trace-on-bare-metal/4132](https://ziggit.dev/t/logging-a-stack-trace-on-bare-metal/4132)\n\nI got some extremely helpful info which I think will allow me to do an ad hoc diagnosis of a specific crash, but I would ideally like to be able to log a stack trace \\*without\\* access to the ELF file (e.g. for remote debugging purposes), does anyone have an idea if this is possible? This seems to come down to getting hold of the \\`DebugInfo\\` object and passing it to something like [this guy](https://github.com/ziglang/zig/blob/master/lib/std/debug.zig#L778), but I have so far been totally unsuccessful in getting this to work on my embedded device (a Raspberry Pi Pico if anyone cares).",
//                     "author_fullname": "t2_2h47n0d",
//                     "saved": false,
//                     "mod_reason_title": null,
//                     "gilded": 0,
//                     "clicked": false,
//                     "title": "Logging a stack trace on bare metal",
//                     "link_flair_richtext": [],
//                     "subreddit_name_prefixed": "r/Zig",
//                     "hidden": false,
//                     "pwls": 6,
//                     "link_flair_css_class": null,
//                     "downs": 0,
//                     "top_awarded_type": null,
//                     "hide_score": false,
//                     "name": "t3_1cfkmmb",
//                     "quarantine": false,
//                     "link_flair_text_color": "dark",
//                     "upvote_ratio": 0.76,
//                     "author_flair_background_color": null,
//                     "subreddit_type": "public",
//                     "ups": 4,
//                     "total_awards_received": 0,
//                     "media_embed": {},
//                     "author_flair_template_id": null,
//                     "is_original_content": false,
//                     "user_reports": [],
//                     "secure_media": null,
//                     "is_reddit_media_domain": false,
//                     "is_meta": false,
//                     "category": null,
//                     "secure_media_embed": {},
//                     "link_flair_text": null,
//                     "can_mod_post": false,
//                     "score": 4,
//                     "approved_by": null,
//                     "is_created_from_ads_ui": false,
//                     "author_premium": false,
//                     "thumbnail": "",
//                     "edited": false,
//                     "author_flair_css_class": null,
//                     "author_flair_richtext": [],
//                     "gildings": {},
//                     "content_categories": null,
//                     "is_self": true,
//                     "mod_note": null,
//                     "created": 1714347508.0,
//                     "link_flair_type": "text",
//                     "wls": 6,
//                     "removed_by_category": null,
//                     "banned_by": null,
//                     "author_flair_type": "text",
//                     "domain": "self.Zig",
//                     "allow_live_comments": false,
//                     "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;Hi Ziglers! Ziglets? Zigulons? Anyway, apologies for the sort-of crossposting but I posted this to ziggit:&lt;/p&gt;\n\n&lt;p&gt;&lt;a href=\"https://ziggit.dev/t/logging-a-stack-trace-on-bare-metal/4132\"&gt;https://ziggit.dev/t/logging-a-stack-trace-on-bare-metal/4132&lt;/a&gt;&lt;/p&gt;\n\n&lt;p&gt;I got some extremely helpful info which I think will allow me to do an ad hoc diagnosis of a specific crash, but I would ideally like to be able to log a stack trace *without* access to the ELF file (e.g. for remote debugging purposes), does anyone have an idea if this is possible? This seems to come down to getting hold of the `DebugInfo` object and passing it to something like &lt;a href=\"https://github.com/ziglang/zig/blob/master/lib/std/debug.zig#L778\"&gt;this guy&lt;/a&gt;, but I have so far been totally unsuccessful in getting this to work on my embedded device (a Raspberry Pi Pico if anyone cares).&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
//                     "likes": null,
//                     "suggested_sort": null,
//                     "banned_at_utc": null,
//                     "view_count": null,
//                     "archived": false,
//                     "no_follow": false,
//                     "is_crosspostable": true,
//                     "pinned": false,
//                     "over_18": false,
//                     "all_awardings": [],
//                     "awarders": [],
//                     "media_only": false,
//                     "can_gild": false,
//                     "spoiler": false,
//                     "locked": false,
//                     "author_flair_text": null,
//                     "treatment_tags": [],
//                     "visited": false,
//                     "removed_by": null,
//                     "num_reports": null,
//                     "distinguished": null,
//                     "subreddit_id": "t5_3cf47",
//                     "author_is_blocked": false,
//                     "mod_reason_by": null,
//                     "removal_reason": null,
//                     "link_flair_background_color": "",
//                     "id": "1cfkmmb",
//                     "is_robot_indexable": true,
//                     "report_reasons": null,
//                     "author": "simonbreak",
//                     "discussion_type": null,
//                     "num_comments": 0,
//                     "send_replies": true,
//                     "whitelist_status": "all_ads",
//                     "contest_mode": false,
//                     "mod_reports": [],
//                     "author_patreon_flair": false,
//                     "author_flair_text_color": null,
//                     "permalink": "/r/Zig/comments/1cfkmmb/logging_a_stack_trace_on_bare_metal/",
//                     "parent_whitelist_status": "all_ads",
//                     "stickied": false,
//                     "url": "https://www.reddit.com/r/Zig/comments/1cfkmmb/logging_a_stack_trace_on_bare_metal/",
//                     "subreddit_subscribers": 12771,
//                     "created_utc": 1714347508.0,
//                     "num_crossposts": 0,
//                     "media": null,
//                     "is_video": false
//                 }
//             },
//             {
//                 "kind": "t3",
//                 "data": {
//                     "approved_at_utc": null,
//                     "subreddit": "Zig",
//                     "selftext": "Zigar is a tool kit that lets you use Zig code in a JavaScript project. The latest version is a significant upgrade from the initial release. A variety of shortcomings were addressed:\n\n* Pointer handling was completely overhauled. The new system is more performant and has fewer limitations. It’s capable of correctly representing recursive structures, for instance.\n* Old C++ addon based on node-gyp was jettisoned in favor of one based on Node-API. It’s now built using the Zig compiler itself, both eliminating unnecessary dependencies and allowing you to cross-compile for multiple platforms.\n* Support for Windows. The new version is also designed to work with Electron and NW.js. The issue that kept Zigar from working on Node.js 20+ has been resolved.\n* Support for the newly released Zig 0.12.0.\n* Support for obscure Zig types such as enum literal. Problems with error sets were fixed.\n* A proper user guide, complete with tutorials, is now available.\n\nZigar 0.11.1 is basically a second-gen effort. It’s less proof-of-concept in nature and more like a product you can actually use. I hope you’ll take it for a spin!\n\nProject page: [https://github.com/chung-leong/zigar](https://github.com/chung-leong/zigar)",
//                     "author_fullname": "t2_bb8jk",
//                     "saved": false,
//                     "mod_reason_title": null,
//                     "gilded": 0,
//                     "clicked": false,
//                     "title": "Zigar 0.11.1 released--using Zig in JavaScript projects",
//                     "link_flair_richtext": [],
//                     "subreddit_name_prefixed": "r/Zig",
//                     "hidden": false,
//                     "pwls": 6,
//                     "link_flair_css_class": null,
//                     "downs": 0,
//                     "top_awarded_type": null,
//                     "hide_score": false,
//                     "name": "t3_1cfgls0",
//                     "quarantine": false,
//                     "link_flair_text_color": "dark",
//                     "upvote_ratio": 0.95,
//                     "author_flair_background_color": null,
//                     "subreddit_type": "public",
//                     "ups": 18,
//                     "total_awards_received": 0,
//                     "media_embed": {},
//                     "author_flair_template_id": null,
//                     "is_original_content": false,
//                     "user_reports": [],
//                     "secure_media": null,
//                     "is_reddit_media_domain": false,
//                     "is_meta": false,
//                     "category": null,
//                     "secure_media_embed": {},
//                     "link_flair_text": null,
//                     "can_mod_post": false,
//                     "score": 18,
//                     "approved_by": null,
//                     "is_created_from_ads_ui": false,
//                     "author_premium": false,
//                     "thumbnail": "",
//                     "edited": false,
//                     "author_flair_css_class": null,
//                     "author_flair_richtext": [],
//                     "gildings": {},
//                     "content_categories": null,
//                     "is_self": true,
//                     "mod_note": null,
//                     "created": 1714337032.0,
//                     "link_flair_type": "text",
//                     "wls": 6,
//                     "removed_by_category": null,
//                     "banned_by": null,
//                     "author_flair_type": "text",
//                     "domain": "self.Zig",
//                     "allow_live_comments": false,
//                     "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;Zigar is a tool kit that lets you use Zig code in a JavaScript project. The latest version is a significant upgrade from the initial release. A variety of shortcomings were addressed:&lt;/p&gt;\n\n&lt;ul&gt;\n&lt;li&gt;Pointer handling was completely overhauled. The new system is more performant and has fewer limitations. It’s capable of correctly representing recursive structures, for instance.&lt;/li&gt;\n&lt;li&gt;Old C++ addon based on node-gyp was jettisoned in favor of one based on Node-API. It’s now built using the Zig compiler itself, both eliminating unnecessary dependencies and allowing you to cross-compile for multiple platforms.&lt;/li&gt;\n&lt;li&gt;Support for Windows. The new version is also designed to work with Electron and NW.js. The issue that kept Zigar from working on Node.js 20+ has been resolved.&lt;/li&gt;\n&lt;li&gt;Support for the newly released Zig 0.12.0.&lt;/li&gt;\n&lt;li&gt;Support for obscure Zig types such as enum literal. Problems with error sets were fixed.&lt;/li&gt;\n&lt;li&gt;A proper user guide, complete with tutorials, is now available.&lt;/li&gt;\n&lt;/ul&gt;\n\n&lt;p&gt;Zigar 0.11.1 is basically a second-gen effort. It’s less proof-of-concept in nature and more like a product you can actually use. I hope you’ll take it for a spin!&lt;/p&gt;\n\n&lt;p&gt;Project page: &lt;a href=\"https://github.com/chung-leong/zigar\"&gt;https://github.com/chung-leong/zigar&lt;/a&gt;&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
//                     "likes": null,
//                     "suggested_sort": null,
//                     "banned_at_utc": null,
//                     "view_count": null,
//                     "archived": false,
//                     "no_follow": false,
//                     "is_crosspostable": true,
//                     "pinned": false,
//                     "over_18": false,
//                     "all_awardings": [],
//                     "awarders": [],
//                     "media_only": false,
//                     "can_gild": false,
//                     "spoiler": false,
//                     "locked": false,
//                     "author_flair_text": null,
//                     "treatment_tags": [],
//                     "visited": false,
//                     "removed_by": null,
//                     "num_reports": null,
//                     "distinguished": null,
//                     "subreddit_id": "t5_3cf47",
//                     "author_is_blocked": false,
//                     "mod_reason_by": null,
//                     "removal_reason": null,
//                     "link_flair_background_color": "",
//                     "id": "1cfgls0",
//                     "is_robot_indexable": true,
//                     "report_reasons": null,
//                     "author": "chungleong",
//                     "discussion_type": null,
//                     "num_comments": 3,
//                     "send_replies": true,
//                     "whitelist_status": "all_ads",
//                     "contest_mode": false,
//                     "mod_reports": [],
//                     "author_patreon_flair": false,
//                     "author_flair_text_color": null,
//                     "permalink": "/r/Zig/comments/1cfgls0/zigar_0111_releasedusing_zig_in_javascript/",
//                     "parent_whitelist_status": "all_ads",
//                     "stickied": false,
//                     "url": "https://www.reddit.com/r/Zig/comments/1cfgls0/zigar_0111_releasedusing_zig_in_javascript/",
//                     "subreddit_subscribers": 12771,
//                     "created_utc": 1714337032.0,
//                     "num_crossposts": 0,
//                     "media": null,
//                     "is_video": false
//                 }
//             },
//             {
//                 "kind": "t3",
//                 "data": {
//                     "approved_at_utc": null,
//                     "subreddit": "Zig",
//                     "selftext": "The following example of creating a nested hashmap in a function and returning it doesn't work:\n\n    const std = @import(\"std\");\n    const StringHashMap = std.StringHashMap;\n    const str = []const u8;\n    \n    pub fn make_example(allocator: std.mem.Allocator) !StringHashMap(*StringHashMap(str)) {\n        var parentMap = StringHashMap(*StringHashMap(str)).init(allocator);\n        var childMap = StringHashMap(str).init(allocator);\n        try childMap.put(\"hello\", \"world\");\n        try parentMap.put(\"foo\", &amp;childMap);\n        return parentMap;\n    }\n    \n    pub fn main() !void {\n        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);\n        const allocator = arena.allocator();\n        defer arena.deinit();\n        const parentMap = try make_example(allocator);\n        const childMap = parentMap.get(\"foo\") orelse unreachable;\n        const value = childMap.*.get(\"hello\") orelse unreachable;\n        std.debug.print(\"\\nValue: {any}\\n\", .{value});\n    }\n\nIt fails with a segfault when `childMap` is accessed in the main function. But if you initialize `parentMap` in the main function and pass it into `make_example` by reference, it works.\n\nI assumed this was happening because the memory is cleaned up when the function returns, but since both `parentMap` and `childMap` are allocated dynamically I don't see why this would happen.\n\nI tried dynamically allocating the `\"hello\"` and `\"world\"` in `childMap` as well with `allocator.dupe` but it still fails.",
//                     "author_fullname": "t2_rv9cp",
//                     "saved": false,
//                     "mod_reason_title": null,
//                     "gilded": 0,
//                     "clicked": false,
//                     "title": "Question on nesting hashmaps",
//                     "link_flair_richtext": [],
//                     "subreddit_name_prefixed": "r/Zig",
//                     "hidden": false,
//                     "pwls": 6,
//                     "link_flair_css_class": null,
//                     "downs": 0,
//                     "top_awarded_type": null,
//                     "hide_score": false,
//                     "name": "t3_1cfed4z",
//                     "quarantine": false,
//                     "link_flair_text_color": "dark",
//                     "upvote_ratio": 1.0,
//                     "author_flair_background_color": null,
//                     "subreddit_type": "public",
//                     "ups": 3,
//                     "total_awards_received": 0,
//                     "media_embed": {},
//                     "author_flair_template_id": null,
//                     "is_original_content": false,
//                     "user_reports": [],
//                     "secure_media": null,
//                     "is_reddit_media_domain": false,
//                     "is_meta": false,
//                     "category": null,
//                     "secure_media_embed": {},
//                     "link_flair_text": null,
//                     "can_mod_post": false,
//                     "score": 3,
//                     "approved_by": null,
//                     "is_created_from_ads_ui": false,
//                     "author_premium": false,
//                     "thumbnail": "",
//                     "edited": 1714331934.0,
//                     "author_flair_css_class": null,
//                     "author_flair_richtext": [],
//                     "gildings": {},
//                     "content_categories": null,
//                     "is_self": true,
//                     "mod_note": null,
//                     "created": 1714331582.0,
//                     "link_flair_type": "text",
//                     "wls": 6,
//                     "removed_by_category": null,
//                     "banned_by": null,
//                     "author_flair_type": "text",
//                     "domain": "self.Zig",
//                     "allow_live_comments": false,
//                     "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;The following example of creating a nested hashmap in a function and returning it doesn&amp;#39;t work:&lt;/p&gt;\n\n&lt;pre&gt;&lt;code&gt;const std = @import(&amp;quot;std&amp;quot;);\nconst StringHashMap = std.StringHashMap;\nconst str = []const u8;\n\npub fn make_example(allocator: std.mem.Allocator) !StringHashMap(*StringHashMap(str)) {\n    var parentMap = StringHashMap(*StringHashMap(str)).init(allocator);\n    var childMap = StringHashMap(str).init(allocator);\n    try childMap.put(&amp;quot;hello&amp;quot;, &amp;quot;world&amp;quot;);\n    try parentMap.put(&amp;quot;foo&amp;quot;, &amp;amp;childMap);\n    return parentMap;\n}\n\npub fn main() !void {\n    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);\n    const allocator = arena.allocator();\n    defer arena.deinit();\n    const parentMap = try make_example(allocator);\n    const childMap = parentMap.get(&amp;quot;foo&amp;quot;) orelse unreachable;\n    const value = childMap.*.get(&amp;quot;hello&amp;quot;) orelse unreachable;\n    std.debug.print(&amp;quot;\\nValue: {any}\\n&amp;quot;, .{value});\n}\n&lt;/code&gt;&lt;/pre&gt;\n\n&lt;p&gt;It fails with a segfault when &lt;code&gt;childMap&lt;/code&gt; is accessed in the main function. But if you initialize &lt;code&gt;parentMap&lt;/code&gt; in the main function and pass it into &lt;code&gt;make_example&lt;/code&gt; by reference, it works.&lt;/p&gt;\n\n&lt;p&gt;I assumed this was happening because the memory is cleaned up when the function returns, but since both &lt;code&gt;parentMap&lt;/code&gt; and &lt;code&gt;childMap&lt;/code&gt; are allocated dynamically I don&amp;#39;t see why this would happen.&lt;/p&gt;\n\n&lt;p&gt;I tried dynamically allocating the &lt;code&gt;&amp;quot;hello&amp;quot;&lt;/code&gt; and &lt;code&gt;&amp;quot;world&amp;quot;&lt;/code&gt; in &lt;code&gt;childMap&lt;/code&gt; as well with &lt;code&gt;allocator.dupe&lt;/code&gt; but it still fails.&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
//                     "likes": null,
//                     "suggested_sort": null,
//                     "banned_at_utc": null,
//                     "view_count": null,
//                     "archived": false,
//                     "no_follow": false,
//                     "is_crosspostable": true,
//                     "pinned": false,
//                     "over_18": false,
//                     "all_awardings": [],
//                     "awarders": [],
//                     "media_only": false,
//                     "can_gild": false,
//                     "spoiler": false,
//                     "locked": false,
//                     "author_flair_text": null,
//                     "treatment_tags": [],
//                     "visited": false,
//                     "removed_by": null,
//                     "num_reports": null,
//                     "distinguished": null,
//                     "subreddit_id": "t5_3cf47",
//                     "author_is_blocked": false,
//                     "mod_reason_by": null,
//                     "removal_reason": null,
//                     "link_flair_background_color": "",
//                     "id": "1cfed4z",
//                     "is_robot_indexable": true,
//                     "report_reasons": null,
//                     "author": "nbsand",
//                     "discussion_type": null,
//                     "num_comments": 3,
//                     "send_replies": true,
//                     "whitelist_status": "all_ads",
//                     "contest_mode": false,
//                     "mod_reports": [],
//                     "author_patreon_flair": false,
//                     "author_flair_text_color": null,
//                     "permalink": "/r/Zig/comments/1cfed4z/question_on_nesting_hashmaps/",
//                     "parent_whitelist_status": "all_ads",
//                     "stickied": false,
//                     "url": "https://www.reddit.com/r/Zig/comments/1cfed4z/question_on_nesting_hashmaps/",
//                     "subreddit_subscribers": 12771,
//                     "created_utc": 1714331582.0,
//                     "num_crossposts": 0,
//                     "media": null,
//                     "is_video": false
//                 }
//             },
//             {
//                 "kind": "t3",
//                 "data": {
//                     "approved_at_utc": null,
//                     "subreddit": "Zig",
//                     "selftext": "Are types such as C's uint\\_fast32\\_t useful at all in Zig, or do optimizers already \"promote\" integers where possible? These are accessible by a cImport of stdint.h, but if they are useful outside of a C context it would be nice to have them available by default.",
//                     "author_fullname": "t2_woavt5jqo",
//                     "saved": false,
//                     "mod_reason_title": null,
//                     "gilded": 0,
//                     "clicked": false,
//                     "title": "Does Zig need \"fast width\" data types?",
//                     "link_flair_richtext": [],
//                     "subreddit_name_prefixed": "r/Zig",
//                     "hidden": false,
//                     "pwls": 6,
//                     "link_flair_css_class": null,
//                     "downs": 0,
//                     "top_awarded_type": null,
//                     "hide_score": false,
//                     "name": "t3_1cfckft",
//                     "quarantine": false,
//                     "link_flair_text_color": "dark",
//                     "upvote_ratio": 0.91,
//                     "author_flair_background_color": null,
//                     "subreddit_type": "public",
//                     "ups": 8,
//                     "total_awards_received": 0,
//                     "media_embed": {},
//                     "author_flair_template_id": null,
//                     "is_original_content": false,
//                     "user_reports": [],
//                     "secure_media": null,
//                     "is_reddit_media_domain": false,
//                     "is_meta": false,
//                     "category": null,
//                     "secure_media_embed": {},
//                     "link_flair_text": null,
//                     "can_mod_post": false,
//                     "score": 8,
//                     "approved_by": null,
//                     "is_created_from_ads_ui": false,
//                     "author_premium": false,
//                     "thumbnail": "",
//                     "edited": false,
//                     "author_flair_css_class": null,
//                     "author_flair_richtext": [],
//                     "gildings": {},
//                     "content_categories": null,
//                     "is_self": true,
//                     "mod_note": null,
//                     "created": 1714327175.0,
//                     "link_flair_type": "text",
//                     "wls": 6,
//                     "removed_by_category": null,
//                     "banned_by": null,
//                     "author_flair_type": "text",
//                     "domain": "self.Zig",
//                     "allow_live_comments": false,
//                     "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;Are types such as C&amp;#39;s uint_fast32_t useful at all in Zig, or do optimizers already &amp;quot;promote&amp;quot; integers where possible? These are accessible by a cImport of stdint.h, but if they are useful outside of a C context it would be nice to have them available by default.&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
//                     "likes": null,
//                     "suggested_sort": null,
//                     "banned_at_utc": null,
//                     "view_count": null,
//                     "archived": false,
//                     "no_follow": false,
//                     "is_crosspostable": true,
//                     "pinned": false,
//                     "over_18": false,
//                     "all_awardings": [],
//                     "awarders": [],
//                     "media_only": false,
//                     "can_gild": false,
//                     "spoiler": false,
//                     "locked": false,
//                     "author_flair_text": null,
//                     "treatment_tags": [],
//                     "visited": false,
//                     "removed_by": null,
//                     "num_reports": null,
//                     "distinguished": null,
//                     "subreddit_id": "t5_3cf47",
//                     "author_is_blocked": false,
//                     "mod_reason_by": null,
//                     "removal_reason": null,
//                     "link_flair_background_color": "",
//                     "id": "1cfckft",
//                     "is_robot_indexable": true,
//                     "report_reasons": null,
//                     "author": "Disastrous_Floor_972",
//                     "discussion_type": null,
//                     "num_comments": 6,
//                     "send_replies": false,
//                     "whitelist_status": "all_ads",
//                     "contest_mode": false,
//                     "mod_reports": [],
//                     "author_patreon_flair": false,
//                     "author_flair_text_color": null,
//                     "permalink": "/r/Zig/comments/1cfckft/does_zig_need_fast_width_data_types/",
//                     "parent_whitelist_status": "all_ads",
//                     "stickied": false,
//                     "url": "https://www.reddit.com/r/Zig/comments/1cfckft/does_zig_need_fast_width_data_types/",
//                     "subreddit_subscribers": 12771,
//                     "created_utc": 1714327175.0,
//                     "num_crossposts": 0,
//                     "media": null,
//                     "is_video": false
//                 }
//             },
//             {
//                 "kind": "t3",
//                 "data": {
//                     "approved_at_utc": null,
//                     "subreddit": "Zig",
//                     "selftext": "I have a large project that has a couple directories that are utilities, and  want to have a hierarchy for them without polluting the top level name space with basically everything.\n\n```\nsrc\nsrc/collections/hash\nsrc/collections/veb\nsrc/net\nsrc/coroutines\n```\nbut there is also \n\n```\nsrc/debug/assert\nsrc/debug/print\n```\n\n I can't `@import` the debug stuff from the collections.\n\nSome of the debug stuff relied on the collection stuff (such as a fixarraylist or fixedstrintg) but those also use the debug asserts.\n\nI currently imporrt  EVERYTHING with a `src/_all.zig` file that I generated with an awk script. Thais' horrible.",
//                     "author_fullname": "t2_dobfu",
//                     "saved": false,
//                     "mod_reason_title": null,
//                     "gilded": 0,
//                     "clicked": false,
//                     "title": "@import from a sibling directory",
//                     "link_flair_richtext": [],
//                     "subreddit_name_prefixed": "r/Zig",
//                     "hidden": false,
//                     "pwls": 6,
//                     "link_flair_css_class": null,
//                     "downs": 0,
//                     "top_awarded_type": null,
//                     "hide_score": false,
//                     "name": "t3_1cf7b1o",
//                     "quarantine": false,
//                     "link_flair_text_color": "dark",
//                     "upvote_ratio": 1.0,
//                     "author_flair_background_color": null,
//                     "subreddit_type": "public",
//                     "ups": 1,
//                     "total_awards_received": 0,
//                     "media_embed": {},
//                     "author_flair_template_id": null,
//                     "is_original_content": false,
//                     "user_reports": [],
//                     "secure_media": null,
//                     "is_reddit_media_domain": false,
//                     "is_meta": false,
//                     "category": null,
//                     "secure_media_embed": {},
//                     "link_flair_text": null,
//                     "can_mod_post": false,
//                     "score": 1,
//                     "approved_by": null,
//                     "is_created_from_ads_ui": false,
//                     "author_premium": false,
//                     "thumbnail": "",
//                     "edited": false,
//                     "author_flair_css_class": null,
//                     "author_flair_richtext": [],
//                     "gildings": {},
//                     "content_categories": null,
//                     "is_self": true,
//                     "mod_note": null,
//                     "created": 1714313460.0,
//                     "link_flair_type": "text",
//                     "wls": 6,
//                     "removed_by_category": null,
//                     "banned_by": null,
//                     "author_flair_type": "text",
//                     "domain": "self.Zig",
//                     "allow_live_comments": false,
//                     "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;I have a large project that has a couple directories that are utilities, and  want to have a hierarchy for them without polluting the top level name space with basically everything.&lt;/p&gt;\n\n&lt;p&gt;&lt;code&gt;\nsrc\nsrc/collections/hash\nsrc/collections/veb\nsrc/net\nsrc/coroutines\n&lt;/code&gt;\nbut there is also &lt;/p&gt;\n\n&lt;p&gt;&lt;code&gt;\nsrc/debug/assert\nsrc/debug/print\n&lt;/code&gt;&lt;/p&gt;\n\n&lt;p&gt;I can&amp;#39;t &lt;code&gt;@import&lt;/code&gt; the debug stuff from the collections.&lt;/p&gt;\n\n&lt;p&gt;Some of the debug stuff relied on the collection stuff (such as a fixarraylist or fixedstrintg) but those also use the debug asserts.&lt;/p&gt;\n\n&lt;p&gt;I currently imporrt  EVERYTHING with a &lt;code&gt;src/_all.zig&lt;/code&gt; file that I generated with an awk script. Thais&amp;#39; horrible.&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
//                     "likes": null,
//                     "suggested_sort": null,
//                     "banned_at_utc": null,
//                     "view_count": null,
//                     "archived": false,
//                     "no_follow": true,
//                     "is_crosspostable": true,
//                     "pinned": false,
//                     "over_18": false,
//                     "all_awardings": [],
//                     "awarders": [],
//                     "media_only": false,
//                     "can_gild": false,
//                     "spoiler": false,
//                     "locked": false,
//                     "author_flair_text": null,
//                     "treatment_tags": [],
//                     "visited": false,
//                     "removed_by": null,
//                     "num_reports": null,
//                     "distinguished": null,
//                     "subreddit_id": "t5_3cf47",
//                     "author_is_blocked": false,
//                     "mod_reason_by": null,
//                     "removal_reason": null,
//                     "link_flair_background_color": "",
//                     "id": "1cf7b1o",
//                     "is_robot_indexable": true,
//                     "report_reasons": null,
//                     "author": "jnordwick",
//                     "discussion_type": null,
//                     "num_comments": 2,
//                     "send_replies": true,
//                     "whitelist_status": "all_ads",
//                     "contest_mode": false,
//                     "mod_reports": [],
//                     "author_patreon_flair": false,
//                     "author_flair_text_color": null,
//                     "permalink": "/r/Zig/comments/1cf7b1o/import_from_a_sibling_directory/",
//                     "parent_whitelist_status": "all_ads",
//                     "stickied": false,
//                     "url": "https://www.reddit.com/r/Zig/comments/1cf7b1o/import_from_a_sibling_directory/",
//                     "subreddit_subscribers": 12771,
//                     "created_utc": 1714313460.0,
//                     "num_crossposts": 0,
//                     "media": null,
//                     "is_video": false
//                 }
//             },
//             {
//                 "kind": "t3",
//                 "data": {
//                     "approved_at_utc": null,
//                     "subreddit": "Zig",
//                     "selftext": "Newbie here just getting started with Ziglings.\n\nIs there a more elegant way (without breaks and :blk) to assign a variable with different default values if an error occurs?\n\n    const MyErrorTypes = error{ Type1Failure, Type2Failure, Type3Failure };  \n    \n    // this works but kind of ugly (reminiscent of GOTO statements)\n    const value2: u16 = canFail() catch |err| blk: {  \n      if (err == MyErrorTypes.Type1Failure) {  \n        break :blk 100;  \n      }  \n      if (err == MyErrorTypes.Type2Failure) {  \n        break :blk 200;  \n      }  \n      break :blk 300;  \n    };  \n      \n    \\_ = value2;\n    \n    \n    // something like this maybe?\n    const value3: u8 = canFail() catch |err| {\n      if (err == MyErrorTypes.Type1Failure) return 100;\n      if (err == MyErrorTypes.Type2Failure) return 200;\n      return 300;\n    };",
//                     "author_fullname": "t2_79rkily2",
//                     "saved": false,
//                     "mod_reason_title": null,
//                     "gilded": 0,
//                     "clicked": false,
//                     "title": "Question on variable assignment + error handling",
//                     "link_flair_richtext": [],
//                     "subreddit_name_prefixed": "r/Zig",
//                     "hidden": false,
//                     "pwls": 6,
//                     "link_flair_css_class": null,
//                     "downs": 0,
//                     "top_awarded_type": null,
//                     "hide_score": false,
//                     "name": "t3_1cf5gh4",
//                     "quarantine": false,
//                     "link_flair_text_color": "dark",
//                     "upvote_ratio": 0.76,
//                     "author_flair_background_color": null,
//                     "subreddit_type": "public",
//                     "ups": 2,
//                     "total_awards_received": 0,
//                     "media_embed": {},
//                     "author_flair_template_id": null,
//                     "is_original_content": false,
//                     "user_reports": [],
//                     "secure_media": null,
//                     "is_reddit_media_domain": false,
//                     "is_meta": false,
//                     "category": null,
//                     "secure_media_embed": {},
//                     "link_flair_text": null,
//                     "can_mod_post": false,
//                     "score": 2,
//                     "approved_by": null,
//                     "is_created_from_ads_ui": false,
//                     "author_premium": false,
//                     "thumbnail": "",
//                     "edited": false,
//                     "author_flair_css_class": null,
//                     "author_flair_richtext": [],
//                     "gildings": {},
//                     "content_categories": null,
//                     "is_self": true,
//                     "mod_note": null,
//                     "created": 1714307958.0,
//                     "link_flair_type": "text",
//                     "wls": 6,
//                     "removed_by_category": null,
//                     "banned_by": null,
//                     "author_flair_type": "text",
//                     "domain": "self.Zig",
//                     "allow_live_comments": false,
//                     "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;Newbie here just getting started with Ziglings.&lt;/p&gt;\n\n&lt;p&gt;Is there a more elegant way (without breaks and :blk) to assign a variable with different default values if an error occurs?&lt;/p&gt;\n\n&lt;pre&gt;&lt;code&gt;const MyErrorTypes = error{ Type1Failure, Type2Failure, Type3Failure };  \n\n// this works but kind of ugly (reminiscent of GOTO statements)\nconst value2: u16 = canFail() catch |err| blk: {  \n  if (err == MyErrorTypes.Type1Failure) {  \n    break :blk 100;  \n  }  \n  if (err == MyErrorTypes.Type2Failure) {  \n    break :blk 200;  \n  }  \n  break :blk 300;  \n};  \n\n\\_ = value2;\n\n\n// something like this maybe?\nconst value3: u8 = canFail() catch |err| {\n  if (err == MyErrorTypes.Type1Failure) return 100;\n  if (err == MyErrorTypes.Type2Failure) return 200;\n  return 300;\n};\n&lt;/code&gt;&lt;/pre&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
//                     "likes": null,
//                     "suggested_sort": null,
//                     "banned_at_utc": null,
//                     "view_count": null,
//                     "archived": false,
//                     "no_follow": false,
//                     "is_crosspostable": true,
//                     "pinned": false,
//                     "over_18": false,
//                     "all_awardings": [],
//                     "awarders": [],
//                     "media_only": false,
//                     "can_gild": false,
//                     "spoiler": false,
//                     "locked": false,
//                     "author_flair_text": null,
//                     "treatment_tags": [],
//                     "visited": false,
//                     "removed_by": null,
//                     "num_reports": null,
//                     "distinguished": null,
//                     "subreddit_id": "t5_3cf47",
//                     "author_is_blocked": false,
//                     "mod_reason_by": null,
//                     "removal_reason": null,
//                     "link_flair_background_color": "",
//                     "id": "1cf5gh4",
//                     "is_robot_indexable": true,
//                     "report_reasons": null,
//                     "author": "Public_Possibility_5",
//                     "discussion_type": null,
//                     "num_comments": 13,
//                     "send_replies": true,
//                     "whitelist_status": "all_ads",
//                     "contest_mode": false,
//                     "mod_reports": [],
//                     "author_patreon_flair": false,
//                     "author_flair_text_color": null,
//                     "permalink": "/r/Zig/comments/1cf5gh4/question_on_variable_assignment_error_handling/",
//                     "parent_whitelist_status": "all_ads",
//                     "stickied": false,
//                     "url": "https://www.reddit.com/r/Zig/comments/1cf5gh4/question_on_variable_assignment_error_handling/",
//                     "subreddit_subscribers": 12771,
//                     "created_utc": 1714307958.0,
//                     "num_crossposts": 0,
//                     "media": null,
//                     "is_video": false
//                 }
//             },
//             {
//                 "kind": "t3",
//                 "data": {
//                     "approved_at_utc": null,
//                     "subreddit": "Zig",
//                     "selftext": "",
//                     "author_fullname": "t2_3cf1me",
//                     "saved": false,
//                     "mod_reason_title": null,
//                     "gilded": 0,
//                     "clicked": false,
//                     "title": "Leaving Rust gamedev after 3 years",
//                     "link_flair_richtext": [],
//                     "subreddit_name_prefixed": "r/Zig",
//                     "hidden": false,
//                     "pwls": 6,
//                     "link_flair_css_class": null,
//                     "downs": 0,
//                     "top_awarded_type": null,
//                     "hide_score": false,
//                     "name": "t3_1cf3dj9",
//                     "quarantine": false,
//                     "link_flair_text_color": "dark",
//                     "upvote_ratio": 0.88,
//                     "author_flair_background_color": null,
//                     "subreddit_type": "public",
//                     "ups": 80,
//                     "total_awards_received": 0,
//                     "media_embed": {},
//                     "author_flair_template_id": null,
//                     "is_original_content": false,
//                     "user_reports": [],
//                     "secure_media": null,
//                     "is_reddit_media_domain": false,
//                     "is_meta": false,
//                     "category": null,
//                     "secure_media_embed": {},
//                     "link_flair_text": null,
//                     "can_mod_post": false,
//                     "score": 80,
//                     "approved_by": null,
//                     "is_created_from_ads_ui": false,
//                     "author_premium": false,
//                     "thumbnail": "",
//                     "edited": false,
//                     "author_flair_css_class": null,
//                     "author_flair_richtext": [],
//                     "gildings": {},
//                     "content_categories": null,
//                     "is_self": false,
//                     "mod_note": null,
//                     "created": 1714300504.0,
//                     "link_flair_type": "text",
//                     "wls": 6,
//                     "removed_by_category": null,
//                     "banned_by": null,
//                     "author_flair_type": "text",
//                     "domain": "loglog.games",
//                     "allow_live_comments": false,
//                     "selftext_html": null,
//                     "likes": null,
//                     "suggested_sort": null,
//                     "banned_at_utc": null,
//                     "url_overridden_by_dest": "https://loglog.games/blog/leaving-rust-gamedev/",
//                     "view_count": null,
//                     "archived": false,
//                     "no_follow": false,
//                     "is_crosspostable": true,
//                     "pinned": false,
//                     "over_18": false,
//                     "all_awardings": [],
//                     "awarders": [],
//                     "media_only": false,
//                     "can_gild": false,
//                     "spoiler": false,
//                     "locked": false,
//                     "author_flair_text": null,
//                     "treatment_tags": [],
//                     "visited": false,
//                     "removed_by": null,
//                     "num_reports": null,
//                     "distinguished": null,
//                     "subreddit_id": "t5_3cf47",
//                     "author_is_blocked": false,
//                     "mod_reason_by": null,
//                     "removal_reason": null,
//                     "link_flair_background_color": "",
//                     "id": "1cf3dj9",
//                     "is_robot_indexable": true,
//                     "report_reasons": null,
//                     "author": "cztomsik",
//                     "discussion_type": null,
//                     "num_comments": 36,
//                     "send_replies": true,
//                     "whitelist_status": "all_ads",
//                     "contest_mode": false,
//                     "mod_reports": [],
//                     "author_patreon_flair": false,
//                     "author_flair_text_color": null,
//                     "permalink": "/r/Zig/comments/1cf3dj9/leaving_rust_gamedev_after_3_years/",
//                     "parent_whitelist_status": "all_ads",
//                     "stickied": false,
//                     "url": "https://loglog.games/blog/leaving-rust-gamedev/",
//                     "subreddit_subscribers": 12771,
//                     "created_utc": 1714300504.0,
//                     "num_crossposts": 0,
//                     "media": null,
//                     "is_video": false
//                 }
//             },
//             {
//                 "kind": "t3",
//                 "data": {
//                     "approved_at_utc": null,
//                     "subreddit": "Zig",
//                     "selftext": "I was looking through the bootstrap process and I noticed that it uses the `zig translate-c` feature stored as a blob at `zig/stage1/zig1.wasm`. I understand that there's a need to be fast with the development and remove the constraints of maintaining the c++ compiler.\n\nMaybe the initial wasm binary should be generated by CI and  hosted somewhere so zig can keep it's repositories without binaries? If this is temporary until 1.0 then I completely understand. Maybe following a strategy where the previous compiler bootstraps the next after 1.0 makes sense.\n\nThe reason I ask this is mostly because of the recent news with xz and so forth.",
//                     "author_fullname": "t2_z1y3j",
//                     "saved": false,
//                     "mod_reason_title": null,
//                     "gilded": 0,
//                     "clicked": false,
//                     "title": "Is WASM bootstrap the plan post 1.0?",
//                     "link_flair_richtext": [],
//                     "subreddit_name_prefixed": "r/Zig",
//                     "hidden": false,
//                     "pwls": 6,
//                     "link_flair_css_class": null,
//                     "downs": 0,
//                     "top_awarded_type": null,
//                     "hide_score": false,
//                     "name": "t3_1cew16o",
//                     "quarantine": false,
//                     "link_flair_text_color": "dark",
//                     "upvote_ratio": 1.0,
//                     "author_flair_background_color": null,
//                     "subreddit_type": "public",
//                     "ups": 5,
//                     "total_awards_received": 0,
//                     "media_embed": {},
//                     "author_flair_template_id": null,
//                     "is_original_content": false,
//                     "user_reports": [],
//                     "secure_media": null,
//                     "is_reddit_media_domain": false,
//                     "is_meta": false,
//                     "category": null,
//                     "secure_media_embed": {},
//                     "link_flair_text": null,
//                     "can_mod_post": false,
//                     "score": 5,
//                     "approved_by": null,
//                     "is_created_from_ads_ui": false,
//                     "author_premium": false,
//                     "thumbnail": "",
//                     "edited": false,
//                     "author_flair_css_class": null,
//                     "author_flair_richtext": [],
//                     "gildings": {},
//                     "content_categories": null,
//                     "is_self": true,
//                     "mod_note": null,
//                     "created": 1714272426.0,
//                     "link_flair_type": "text",
//                     "wls": 6,
//                     "removed_by_category": null,
//                     "banned_by": null,
//                     "author_flair_type": "text",
//                     "domain": "self.Zig",
//                     "allow_live_comments": false,
//                     "selftext_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;I was looking through the bootstrap process and I noticed that it uses the &lt;code&gt;zig translate-c&lt;/code&gt; feature stored as a blob at &lt;code&gt;zig/stage1/zig1.wasm&lt;/code&gt;. I understand that there&amp;#39;s a need to be fast with the development and remove the constraints of maintaining the c++ compiler.&lt;/p&gt;\n\n&lt;p&gt;Maybe the initial wasm binary should be generated by CI and  hosted somewhere so zig can keep it&amp;#39;s repositories without binaries? If this is temporary until 1.0 then I completely understand. Maybe following a strategy where the previous compiler bootstraps the next after 1.0 makes sense.&lt;/p&gt;\n\n&lt;p&gt;The reason I ask this is mostly because of the recent news with xz and so forth.&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
//                     "likes": null,
//                     "suggested_sort": null,
//                     "banned_at_utc": null,
//                     "view_count": null,
//                     "archived": false,
//                     "no_follow": false,
//                     "is_crosspostable": true,
//                     "pinned": false,
//                     "over_18": false,
//                     "all_awardings": [],
//                     "awarders": [],
//                     "media_only": false,
//                     "can_gild": false,
//                     "spoiler": false,
//                     "locked": false,
//                     "author_flair_text": null,
//                     "treatment_tags": [],
//                     "visited": false,
//                     "removed_by": null,
//                     "num_reports": null,
//                     "distinguished": null,
//                     "subreddit_id": "t5_3cf47",
//                     "author_is_blocked": false,
//                     "mod_reason_by": null,
//                     "removal_reason": null,
//                     "link_flair_background_color": "",
//                     "id": "1cew16o",
//                     "is_robot_indexable": true,
//                     "report_reasons": null,
//                     "author": "PCJesus",
//                     "discussion_type": null,
//                     "num_comments": 21,
//                     "send_replies": true,
//                     "whitelist_status": "all_ads",
//                     "contest_mode": false,
//                     "mod_reports": [],
//                     "author_patreon_flair": false,
//                     "author_flair_text_color": null,
//                     "permalink": "/r/Zig/comments/1cew16o/is_wasm_bootstrap_the_plan_post_10/",
//                     "parent_whitelist_status": "all_ads",
//                     "stickied": false,
//                     "url": "https://www.reddit.com/r/Zig/comments/1cew16o/is_wasm_bootstrap_the_plan_post_10/",
//                     "subreddit_subscribers": 12771,
//                     "created_utc": 1714272426.0,
//                     "num_crossposts": 0,
//                     "media": null,
//                     "is_video": false
//                 }
//             }
//         ],
//         "before": "t3_1cghc5i"
//     }
// }
