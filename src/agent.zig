const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const Headers = std.http.Headers;

const AccessToken = @import("api/access_token.zig").AccessToken;
const ApiRequest = @import("ApiRequest.zig");
const ApiResponse = ApiRequest.ApiResponse;
const api = @import("api.zig");

pub const Number = u64;

pub const Config = struct {
    thread_safe: bool = !@import("builtin").single_threaded,
    MutexType: ?type = null,
};

pub const AuthorizationOptions = struct {
    user_agent: []const u8,
    app_id: []const u8,
    app_pass: []const u8,
    user_id: []const u8,
    user_pass: []const u8,
};

const Authorization = struct {
    authorization: []const u8,

    pub const Self = @This();

    pub fn fetch(allocator: Allocator, options: AuthorizationOptions) !Self {
        // const buffer: [1 << 14]u8 = undefined;
        // var fba = std.heap.FixedBufferAllocator.init(&buffer);

        // TODO continue here

        var client = Client{ .allocator = allocator };
        defer client.deinit();

        var response_buffer: [1 << 10]u8 = undefined;

        const response = blk: {
            const basic_auth = bauth: {
                const Base64Encoder = std.base64.standard.Encoder;
                const src = try fmt.allocPrint(allocator, "{s}:{s}", .{ options.app_id, options.app_pass });
                defer allocator.free(src);
                const encoded = try allocator.alloc(u8, Base64Encoder.calcSize(src.len));
                defer allocator.free(encoded);
                _ = Base64Encoder.encode(encoded, src);
                break :bauth try fmt.allocPrint(allocator, "Basic {s}", .{encoded});
            };
            defer allocator.free(basic_auth);

            const requ_payload = try fmt.allocPrint(allocator, "grant_type=password&username={s}&password={s}", .{ options.user_id, options.user_pass });
            defer allocator.free(requ_payload);

            const endpoint = try api.Endpoint.parse(allocator, AccessToken{});
            defer endpoint.deinit(allocator);

            const request = ApiRequest{
                .uri = endpoint.url.bytes,
                .method = endpoint.method,
                .user_agent = options.user_agent,
                .authorization = basic_auth,
                .payload = requ_payload,
            };
            break :blk try request.fetch(&client, .{ .static = &response_buffer });
        };
        const payload = try response.parse(AccessToken.Payload, allocator);

        const authorization = try fmt.allocPrint(allocator, "{s} {s}", .{ payload.token_type, payload.access_token });
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

const Agent = struct {
    user_agent: []const u8,
    authorization: []const u8,
    client: Client,
    response_buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.response_buffer.deinit();
        self.client.deinit();
    }

    pub fn fetch(self: *Self, endpoint: api.Endpoint) !ApiResponse {
        self.response_buffer.clearRetainingCapacity();
        const request = ApiRequest{
            .uri = endpoint.url.bytes,
            .method = endpoint.method,
            .user_agent = self.user_agent,
            .authorization = self.authorization,
            .payload = null,
        };
        return request.fetch(&self.client, .{ .dynamic = &self.response_buffer });
    }

    pub fn fetchWithContext(self: *Self, allocator: Allocator, api_context: anytype) !ApiResponse {
        const endpoint = try api.Endpoint.parse(allocator, api_context);
        defer endpoint.deinit(allocator);
        return self.fetch(endpoint);
    }
};

const print = std.debug.print;

const testOptions = @import("util.zig").testOptions;
const TestOptions = @import("util.zig").TestOptions;

test "auth" {
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
        const New = @import("api/listings.zig").New;
        const res = try agent.fetchWithContext(allocator, New("zig"){
            .count = 2,
        });
        defer res.deinit(allocator);

        print("{s}\n", .{res.payload});
    }

    {
        const Me = @import("api/account.zig").Me;
        const res = try agent.fetchWithContext(allocator, Me{});
        defer res.deinit(allocator);

        print("{s}\n", .{res.payload});
    }

    // print("connection_pool used len: {}\n", .{agent.client.connection_pool.used.len});
    // print("connection_pool free len: {}\n", .{agent.client.connection_pool.free_len});

    // const res = try agent.fetch(allocator, );
}
