const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const testing = std.testing;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const Headers = std.http.Headers;
const Parsed = std.json.Parsed;

const AccessToken = @import("endpoint/access_token.zig").AccessToken;
const ApiRequest = @import("ApiRequest.zig");
const ApiResponse = ApiRequest.ApiResponse;
const getEndpoint = @import("endpoint.zig").getEndpoint;
// const api = @import("endpoint.zig");

pub const Bool = bool;
pub const Integer = i64;
pub const Float = f64;
pub const String = []const u8;
// pub const

// pub const Config = struct {
//     thread_safe: bool = !@import("builtin").single_threaded,
//     MutexType: ?type = null,
// };

pub const AuthorizationOptions = struct {
    user_agent: []const u8,
    app_id: []const u8,
    app_pass: []const u8,
    user_id: []const u8,
    user_pass: []const u8,
};

pub const Authorization = struct {
    authorization: []const u8,

    pub const Self = @This();

    pub fn fetch(allocator: Allocator, options: AuthorizationOptions) !Self {
        var buffer: [1 << 14]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const fballoc = fba.allocator();

        var client = Client{ .allocator = allocator };
        defer client.deinit();

        const response = blk: {
            const basic_auth = bauth: {
                const Base64Encoder = std.base64.standard.Encoder;
                const src = try fmt.allocPrint(fballoc, "{s}:{s}", .{ options.app_id, options.app_pass });
                defer fballoc.free(src);
                const encoded = try fballoc.alloc(u8, Base64Encoder.calcSize(src.len));
                defer fballoc.free(encoded);
                _ = Base64Encoder.encode(encoded, src);
                break :bauth try fmt.allocPrint(fballoc, "Basic {s}", .{encoded});
            };
            defer fballoc.free(basic_auth);

            const requ_payload = try fmt.allocPrint(fballoc, "grant_type=password&username={s}&password={s}", .{ options.user_id, options.user_pass });
            defer fballoc.free(requ_payload);

            // const endpoint = try api.Endpoint.parse(fballoc, AccessToken{});
            const endpoint = try getEndpoint(fballoc, AccessToken{});
            defer endpoint.deinit(fballoc);

            const request = ApiRequest{
                .uri = endpoint.url.value,
                .method = endpoint.method,
                .user_agent = options.user_agent,
                .authorization = basic_auth,
                .payload = requ_payload,
            };
            // break :blk try request.fetch(&client, .{ .static = &response_buffer });

            var response_buffer = std.ArrayList(u8).init(fballoc);
            break :blk try request.fetch(&client, .{ .dynamic = &response_buffer });
        };
        const parsed = try response.parse(AccessToken.Model, fballoc);
        defer parsed.deinit();
        const authorization = try fmt.allocPrint(allocator, "{s} {s}", .{ parsed.value.token_type, parsed.value.access_token });
        return Self{ .authorization = authorization };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.authorization);
    }

    pub fn agent(self: *const Self, allocator: Allocator, user_agent: []const u8) Agent {
        const client = Client{ .allocator = allocator };
        const response_buffer = std.ArrayList(u8).init(allocator);
        return Agent{
            .user_agent = user_agent,
            .authorization = self.authorization,
            .client = client,
            .response_buffer = response_buffer,
        };
    }
};

pub const Agent = struct {
    user_agent: []const u8,
    authorization: []const u8,
    client: Client,
    response_buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.response_buffer.deinit();
        self.client.deinit();
    }

    // pub fn fetch(self: *Self, allocator: Allocator, api_context: anytype) !Parsed(@TypeOf(api_context).Model) {
    //     return self.fetchModelWithContext(@TypeOf(api_context).Model, allocator, api_context);
    // }

    fn verifyEndpoint(EndpointType: type) bool {
        const info = @typeInfo(EndpointType);
        debug.assert(info == .Struct);

        const fields = info.Struct.fields;
        const field_url = fields[0];
        _ = field_url; // autofix
        const field_method = fields[1];

        _ = field_method; // autofix
        // if (fields[0].  )

        // if (mem.eql(u8, field_url.name, "url") or mem.eql(u8, field_url.type, "method") or field_url.type =) {
        //     //
        // }

        // if (field_url or mem.eql(u8, field_url.type, "method")) {
        //     //
        // }

    }

    pub fn fetch(self: *Self, allocator: Allocator, endpoint: anytype) !Parsed(@TypeOf(endpoint).Model) {
        const response = try self.fetchRaw(endpoint);
        return try json.parseFromSlice(@TypeOf(endpoint).Model, allocator, response.payload, .{
            .ignore_unknown_fields = true,
        });
    }

    pub fn fetchWithContext(self: *Self, allocator: Allocator, context: anytype) !Parsed(@TypeOf(context).Model) {
        const endpoint = try getEndpoint(@TypeOf(context).Model).parse(allocator, context);
        defer endpoint.deinit(allocator);
        return self.fetch(endpoint);
    }

    pub fn fetchRaw(self: *Self, endpoint: anytype) !ApiResponse {
        self.response_buffer.clearRetainingCapacity();
        const request = ApiRequest{
            .uri = endpoint.url.value,
            .method = endpoint.method,
            .user_agent = self.user_agent,
            .authorization = self.authorization,
            .payload = null,
        };
        return request.fetch(&self.client, .{ .dynamic = &self.response_buffer });
    }

    pub fn fetchRawWithContext(self: *Self, allocator: Allocator, context: anytype) !ApiResponse {
        const endpoint = try getEndpoint(@TypeOf(context).Model).parse(allocator, context);
        defer endpoint.deinit(allocator);
        return self.fetchRaw(endpoint);
    }

    // pub fn fetchModelWithContext(self: *Self, comptime Model: type, allocator: Allocator, api_context: anytype) !Parsed(Model) {
    //     const endpoint = try api.Endpoint.parse(allocator, api_context);
    //     defer endpoint.deinit(allocator);
    //     return self.fetchModel(Model, allocator, endpoint);
    // }
};

const print = std.debug.print;

const testOptions = @import("util.zig").testOptions;
const TestOptions = @import("util.zig").TestOptions;

test "auth" {
    if (true) return error.SkipZigTest;

    const testopts: TestOptions = testOptions() orelse return error.SkipZigTest;

    const allocator = std.testing.allocator;
    // const allocator = std.heap.page_allocator;

    const user_agent = testopts.user_agent;

    var client = Client{ .allocator = allocator };
    defer client.deinit();

    var auth = try Authorization.fetch(allocator, .{
        .user_agent = user_agent,
        .app_id = testopts.app_id,
        .app_pass = testopts.app_pass,
        .user_id = testopts.user_id,
        .user_pass = testopts.user_pass,
    });
    defer auth.deinit(allocator);

    var agent = auth.agent(allocator, user_agent);
    defer agent.deinit();

    {
        const New = @import("endpoint/listing.zig").New;
        // const res = try agent.fetchRawWithContext(allocator, New("zig"){
        //     .count = 2,
        // });
        // defer res.deinit(allocator);

        // print("{s}\n", .{res.payload});

        // const model = try agent.fetch(allocator, New("zig"){
        //     .count = 2,
        // });

        // const children = model.data.children;
        // const x = children[0].data;

        // const model = try agent.fetchModelWithContext(New("zig").Model, allocator, New("zig"){
        //     .count = 3,
        // });

        const Context = New("zig");

        // const parsed = try agent.fetchModelWithContext(Context, allocator, Context{
        //     .count = 3,
        // });
        // defer parsed.deinit();

        // const endpoint = api.Endpoint.parsed(Context{
        //     .count = 3,
        // });

        const endpoint = try getEndpoint(allocator, Context{
            .limit = 1,
            // .sr_detail = true,
        });
        defer endpoint.deinit(allocator);

        print("{s}\n", .{endpoint.url.value});

        // const context = Context{ .count = 3 }.toEndpoint();

        const parsed = try agent.fetch(allocator, endpoint);
        defer parsed.deinit();

        // print("{any}\n", .{x.id});

        // ================

        // const parsed = try json.parseFromSlice(GenericPayload(ListingPayload), allocator, res.payload, .{
        //     .ignore_unknown_fields = true,
        // });
        // print("{any}\n", .{parsed.value});

        // ================

        // const Value = std.json.Value;
        // const parsed = try json.parseFromSlice(Value, allocator, res.payload, .{
        //     .ignore_unknown_fields = true,
        // });

        // const root = parsed.value;

        // const kind = root.object.get("kind").?.string;
        // print("kind: {s}\n", .{kind});

        // const data = root.object.get("data").?.object;
        // print("data: {any}\n", .{data});

        // const selftext = root.object.get("selftext").?;

        // print("{any}\n", .{root.object});
        // print("{any}\n", .{@TypeOf(root.o)});
    }

    {
        // const Me = @import("api/account.zig").Me;
        // const res = try agent.fetchRawWithContext(allocator, Me{});
        // defer res.deinit(allocator);

        // print("{s}\n", .{res.payload});
    }

    // print("connection_pool used len: {}\n", .{agent.client.connection_pool.used.len});
    // print("connection_pool free len: {}\n", .{agent.client.connection_pool.free_len});

    // const res = try agent.fetch(allocator, );
}

const json = std.json;

const model = @import("model.zig");

const Thing = model.Thing;
const Listing = model.Listing;
const Comment = model.Comment;

test "test json" {
    if (true) return error.SkipZigTest;

    print("\n", .{});
    const allocator = std.heap.page_allocator;

    const s = @embedFile("testjson/listing_new.json");

    const Value = std.json.Value;
    const parsed = try json.parseFromSlice(Value, allocator, s, .{
        .ignore_unknown_fields = true,
    });

    const root = parsed.value;

    const kind = root.object.get("kind").?.string;
    print("kind: {s}\n", .{kind});

    const data = root.object.get("data").?.object;
    print("data: {any}\n", .{data});

    print("type: {}", .{@TypeOf(data)});

    // const
    // var scanner = JsonScanner.initCompleteInput(testing.allocator, "123");

    // const selftext = root.object.get("selftext").?;
}

test "test json static" {
    if (true) return error.SkipZigTest;

    print("\n", .{});
    const allocator = std.heap.page_allocator;

    const s = @embedFile("testjson/listing_new.json");

    const parsed = try json.parseFromSlice(Thing(Listing), allocator, s, .{
        .ignore_unknown_fields = true,
    });
    // print("{any}\n", .{parsed.value});

    const listing = parsed.value;

    const children = listing.data.children;

    const c0 = children[0].data;
    _ = c0; // autofix

    // print("{s}\n", .{c0.url});
    // print("{s}\n", .{c0.url.?});
    // print("{s}\n", .{c0.author.?});
    // print("{s}\n", .{c0.selftext.?});

    // const
    // var scanner = JsonScanner.initCompleteInput(testing.allocator, "123");

    // const selftext = root.object.get("selftext").?;
}

test "test json static comment" {
    // if (true) return error.SkipZigTest;

    print("\n", .{});
    const allocator = std.heap.page_allocator;

    const s = @embedFile("testjson/comments2.json");

    const Model = struct {
        Thing(Listing),
        Thing(Comment),
    };

    const parsed = try json.parseFromSlice(Model, allocator, s, .{
        .ignore_unknown_fields = true,
    });
    // print("{any}\n", .{parsed.value});

    const comments = parsed.value;
    _ = comments; // autofix

    // const children = listing.data.children;

    // const c0 = children[0].data;

    // print("{s}\n", .{c0.url});
    // print("{s}\n", .{c0.url.?});
    // print("{s}\n", .{c0.author.?});
    // print("{s}\n", .{c0.selftext.?});

    // const
    // var scanner = JsonScanner.initCompleteInput(testing.allocator, "123");

    // const selftext = root.object.get("selftext").?;
}

fn testparse(comptime T: type, allocator: Allocator, s: []const u8) !T {
    //
    // json.parseFromTokenSource(, , , )
    const parsed = try json.parseFromSlice(T, allocator, s, .{
        .ignore_unknown_fields = true,
    });
    _ = parsed; // autofix
}
