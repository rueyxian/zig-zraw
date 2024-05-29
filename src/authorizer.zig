const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const fmt = std.fmt;
const json = std.json;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const Parsed = std.json.Parsed;

const util = @import("util.zig");
const api = @import("api.zig");
const Request = @import("Request.zig");
const ResponseBuffer = Request.ResponseBuffer;
// const AccessToken = @import("model.zig").AccessToken;
const Token = @import("model.zig").Token;
const Scope = @import("model.zig").Scope;
const Duration = @import("api/auth.zig").Duration;

const url_access_token = api.domain_www ++ "/api/v1/access_token";

const Code = struct {
    state: []const u8,
    code: []const u8,

    const Error = error{ParseError} || Allocator.Error;

    fn allocParse(allocator: Allocator, bytes: []const u8) Error!@This() {
        const start = "GET/?".len + 1;
        const end = mem.indexOf(u8, bytes, " HTTP/1.1") orelse return Error.ParseError;
        if (start > end or end > bytes.len) return Error.ParseError;
        const payload = bytes[start..end];

        const state, const code = blk: {
            var it = mem.splitScalar(u8, payload, '&');
            var a = it.next() orelse return Error.ParseError;
            var b = it.next() orelse return Error.ParseError;
            if (a.len < "state=".len) return Error.ParseError;
            if (b.len < "code=".len) return Error.ParseError;
            break :blk .{ a["state=".len..], b["code=".len..] };
        };

        return @This(){
            .state = try allocator.dupe(u8, state),
            .code = try allocator.dupe(u8, code),
        };
    }
};

// =============================

fn allocBasicAuth(allocator: Allocator, client_id: []const u8, client_secret: ?[]const u8) Allocator.Error![]const u8 {
    var fba_buf: [1 << 7]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fba_buf);
    const fballoc = fba.allocator();

    const Base64Encoder = std.base64.standard.Encoder;
    const s = try fmt.allocPrint(fballoc, "{s}:{s}", .{ client_id, client_secret orelse "" }); // NOTE: free not required
    const buf = try fballoc.alloc(u8, Base64Encoder.calcSize(s.len)); // NOTE: free not required

    const encoded = Base64Encoder.encode(buf, s);
    debug.assert(encoded.len == buf.len);
    return try fmt.allocPrint(allocator, "Basic {s}", .{encoded});
}

// =============================

pub const Flow = enum {
    unregistered,
    implicit,
    authorization_code,
    client_credentials,
    resource_owner_password_credentials,
};

pub const Authorizer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const Error = error{ OutOfMemory, NoSpaceLeft } || json.ParseError(json.Scanner) || Request.Error;

    const VTable = struct {
        deinit: *const fn (*const anyopaque, Allocator) void,
        flow: *const fn (*const anyopaque) Flow,
        // isOauth: *const fn (*const anyopaque) bool,
        accessTokenRaw: *const fn (*anyopaque, Allocator, *Client, []u8, []const u8) Error![]const u8,
        accessTokenLeaky: *const fn (*anyopaque, Allocator, *Client, []u8, []const u8) Error!Token,
        // revokeToken: *const fn (*anyopaque, Allocator, *Client, []u8, []const u8) Error!void,
    };

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        return self.vtable.deinit(self.ptr, allocator);
    }

    pub fn flow(self: *const @This()) Flow {
        return self.vtable.flow(self.ptr);
    }

    // pub fn isOauth(self: *const @This()) bool {
    //     return self.vtable.isOauth(self.ptr);
    // }

    pub fn accessTokenRaw(
        self: *@This(),
        allocator: Allocator,
        client: *Client,
        header_buffer: []u8,
        user_agent: []const u8,
    ) Error![]const u8 {
        return self.vtable.accessTokenRaw(self.ptr, allocator, client, header_buffer, user_agent);
    }

    pub fn accessTokenLeaky(
        self: *@This(),
        allocator: Allocator,
        client: *Client,
        header_buffer: []u8,
        user_agent: []const u8,
    ) Error!Token {
        return self.vtable.accessTokenLeaky(self.ptr, allocator, client, header_buffer, user_agent);
    }
};

fn MixinAuthorizer(comptime T: type) type {
    return struct {
        pub fn authorizer(self: *T) Authorizer {
            return Authorizer{
                .ptr = self,
                .vtable = &.{
                    .deinit = _deinit,
                    .flow = _flow,
                    // .isOauth = _isOauth,
                    .accessTokenRaw = _accessTokenRaw,
                    .accessTokenLeaky = _accessTokenLeaky,
                },
            };
        }

        fn _deinit(ctx: *const anyopaque, allocator: Allocator) void {
            const self: *const T = @ptrCast(@alignCast(ctx));
            self.deinit(allocator);
        }

        fn _flow(ctx: *const anyopaque) Flow {
            const self: *const T = @ptrCast(@alignCast(ctx));
            return self.flow();
        }

        // fn _isOauth(ctx: *const anyopaque) bool {
        //     const self: *const T = @ptrCast(@alignCast(ctx));
        //     return self.isOauth();
        // }

        fn _accessTokenRaw(
            ctx: *anyopaque,
            allocator: Allocator,
            client: *Client,
            header_buffer: []u8,
            user_agent: []const u8,
        ) Authorizer.Error![]const u8 {
            const self: *T = @ptrCast(@alignCast(ctx));
            return self.accessTokenRaw(allocator, client, header_buffer, user_agent);
        }

        fn _accessTokenLeaky(
            ctx: *anyopaque,
            allocator: Allocator,
            client: *Client,
            header_buffer: []u8,
            user_agent: []const u8,
        ) Authorizer.Error!Token {
            const self: *T = @ptrCast(@alignCast(ctx));
            return self.accessTokenLeaky(allocator, client, header_buffer, user_agent);
        }

        // fn _revokeToken(ctx: *const anyopaque, allocator: Allocator, client: *Client, user_agent: []const u8, response_buffer: ResponseBuffer) Authorizer.Error!void {
        //     const self: *const T = @ptrCast(@alignCast(ctx));
        //     return self.revokeToken(allocator, client, user_agent, response_buffer);
        // }

    };
}

pub const Unregistered = struct {
    usingnamespace MixinAuthorizer(@This());

    // pub fn initAuthorizer() Authorizer {
    //     return @constCast(&init()).authorizer();
    // }

    pub fn init() @This() {
        return @This(){};
    }

    pub fn deinit(_: *const @This(), _: Allocator) void {}

    pub fn flow(_: *const @This()) Flow {
        return Flow.unregistered;
    }

    pub fn accessTokenRaw(_: *@This(), _: Allocator, _: *Client, _: []u8, _: []const u8) Authorizer.Error![]const u8 {
        unreachable;
    }

    pub fn accessTokenLeaky(_: *@This(), _: Allocator, _: *Client, _: []u8, _: []const u8) Authorizer.Error!Token {
        unreachable;
    }

    // pub fn revokeToken(_: *@This(), _: Allocator, _: *Client, _: []const u8, _: ResponseBuffer) Authorizer.Error!void {
    //     unreachable;
    // }
};

pub const Implicit = struct {
    client_id: []const u8,
};

pub const CodeGrant = struct {
    // client_id: []const u8,
    // client_secret: []const u8,
    // code: []const u8,
    // redirect_uri: []const u8,

    basic_auth: []const u8,
    payload: []const u8,

    usingnamespace MixinAuthorizer(@This());

    pub const InitOptions = struct {
        client_id: []const u8,
        client_secret: []const u8,
        code: []const u8,
        redirect_uri: []const u8,
    };

    pub fn init(allocator: Allocator, options: InitOptions) Authorizer.Error!@This() {
        var self = blk: {
            var self: @This() = undefined;
            try util.fieldsCopyDeepPartial(allocator, &self, &options);
            break :blk self;
        };
        const ctx = blk: {
            var ctx: api.AccessToken = undefined;
            util.fieldsCopyShallowPartial(&ctx, &self);
            break :blk ctx;
        };
        self.basic_auth = try ctx.allocBasicAuth(allocator);
        self.payload = try ctx.allocPayloadClientCredentialsGrant(allocator);
        return self;
    }
};

pub const ClientCredentials = struct {
    // client_id: []const u8,
    // client_secret: []const u8,
    // device_id: ?[]const u8,
    // scope: ?[]const Scope = null,

    basic_auth: []const u8,
    payload: []const u8,

    usingnamespace MixinAuthorizer(@This());

    pub const InitOptions = struct {
        client_id: []const u8,
        client_secret: []const u8,
        device_id: ?[]const u8 = null,
        scope: ?[]const Scope = null,
    };

    pub fn init(allocator: Allocator, options: InitOptions) Authorizer.Error!@This() {
        var self = blk: {
            var self: @This() = undefined;
            try util.fieldsCopyDeepPartial(allocator, &self, &options);
            break :blk self;
        };
        const ctx = blk: {
            var ctx: api.AccessToken = undefined;
            util.fieldsCopyShallowPartial(&ctx, &self);
            break :blk ctx;
        };
        self.basic_auth = try ctx.allocBasicAuth(allocator);
        self.payload = try ctx.allocPayloadClientCredentialsGrant(allocator);
        return self;
    }

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        util.freeIfNeeded(allocator, self);
    }

    pub fn flow(_: *const @This()) Flow {
        return Flow.client_credentials;
    }

    // pub fn isOauth(_: *const @This()) bool {
    //     return false;
    // }

    pub fn accessTokenRaw(
        self: *@This(),
        allocator: Allocator,
        client: *Client,
        header_buffer: []u8,
        user_agent: []const u8,
    ) Authorizer.Error![]const u8 {
        const url = try (@as(api.AccessToken, undefined)).cowFullUrl(undefined);
        defer url.deinit(undefined);
        var request = try Request.open(.{
            .client = client,
            .header_buffer = header_buffer,
            .url = url.value,
            .method = api.AccessToken.method,
            .user_agent = user_agent,
            .authorization = self.basic_auth,
            .payload = self.payload,
        });
        try request.send();
        defer request.deinit();
        return request.reader().readAllAlloc(allocator);
    }

    pub fn accessTokenLeaky(
        self: *@This(),
        allocator: Allocator,
        client: *Client,
        header_buffer: []u8,
        user_agent: []const u8,
    ) Authorizer.Error!Token {
        const payload = try self.accessTokenRaw(allocator, client, header_buffer, user_agent);
        defer allocator.free(payload);
        return try json.parseFromSliceLeaky(Token, allocator, payload, .{
            .allocate = .alloc_always,
        });
    }
};

// pub fn passwordCredentialsAuthorizer(allocator: Allocator, options: PasswordCredentialsAuthorizerOptions) Authorizer.Error!Authorizer {
//     return (try PasswordCredentialsAuthorizer.init(allocator, options)).authorizer();
// }

pub const PasswordCredentials = struct {
    // client_id: []const u8,
    // client_secret: []const u8,
    // username: []const u8,
    // password: []const u8,
    // scope: ?[]const Scope,

    // auth: *const ConfidentialClient,
    basic_auth: []const u8,
    payload: []const u8,

    pub usingnamespace MixinAuthorizer(@This());

    // pub const InitOptions = struct {
    //     client_id: []const u8,
    //     client_secret: []const u8,
    //     username: []const u8,
    //     password: []const u8,
    //     scope: ?[]const Scope = null,
    // };

    // fn apiAccessToken(self: *const @This()) api.AccessToken {
    //     var ctx: api.AccessToken = undefined;
    //     util.fieldsCopyShallowPartial(&ctx, self);
    //     return ctx;
    // }

    pub const InitOptions = struct {
        client_id: []const u8,
        client_secret: []const u8,
        username: []const u8,
        password: []const u8,
        scope: ?[]const Scope = null,
    };

    // pub fn initAuthorizer(allocator: Allocator, options: InitOptions) Authorizer.Error!Authorizer {
    //     var auth = try @This().init(allocator, options);
    //     return auth.authorizer();
    // }

    pub fn init(allocator: Allocator, options: InitOptions) Authorizer.Error!@This() {
        const basic_auth = try allocBasicAuth(allocator, options.client_id, options.client_secret);
        const ctx = api.AccessToken{
            .grant_type = .password,
            .username = options.username,
            .password = options.password,
            .scope = options.scope,
        };
        const payload = try ctx.allocPayload(allocator);
        return PasswordCredentials{
            .basic_auth = basic_auth,
            .payload = payload,
        };
    }

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        util.freeIfNeeded(allocator, self);
    }

    pub fn flow(_: *const @This()) Flow {
        return Flow.resource_owner_password_credentials;
    }

    // pub fn isOauth(_: *const @This()) bool {
    //     return true;
    // }

    pub fn accessTokenRaw(
        self: *@This(),
        allocator: Allocator,
        client: *Client,
        header_buffer: []u8,
        user_agent: []const u8,
    ) Authorizer.Error![]const u8 {
        const url = try (@as(api.AccessToken, undefined)).cowFullUrl(undefined);
        defer url.deinit(undefined);
        var request = try Request.open(.{
            .client = client,
            .header_buffer = header_buffer,
            .url = url.value,
            .method = api.AccessToken.method,
            .user_agent = user_agent,
            .authorization = self.basic_auth,
            .payload = self.payload,
        });
        try request.send();
        defer request.deinit();
        return try request.reader().readAllAlloc(allocator, 1024 * 1024 * 2);
    }

    pub fn accessTokenLeaky(
        self: *@This(),
        allocator: Allocator,
        client: *Client,
        header_buffer: []u8,
        user_agent: []const u8,
    ) Authorizer.Error!Token {
        const payload = try self.accessTokenRaw(allocator, client, header_buffer, user_agent);
        defer allocator.free(payload);
        return try json.parseFromSliceLeaky(Token, allocator, payload, .{
            .allocate = .alloc_always,
        });
    }

    // pub fn revokeToken(
    //     self: *@This(),
    //     allocator: Allocator,
    //     client: *Client,
    //     user_agent: []const u8,
    //     header_buffer: []u8,
    //     token: []const u8,
    // ) Authorizer.Error!void {
    //     const ctx = api.RevokeToken{
    //         .client_id = self.client_id,
    //         .client_secret = self.client_secret,
    //         .token = token,
    //         .token_type_hint = .access_token,
    //     };

    //     const url = try ctx.cowFullUrl(allocator);
    //     defer url.deinit(allocator);

    //     const payload = try ctx.allocPayload(allocator);
    //     defer allocator.free(payload);
    //     // print("\n\npayload: {s}\n\n", .{payload});

    //     var request = try Request.open(.{
    //         .client = client,
    //         .header_buffer = header_buffer,
    //         .url = url.value,
    //         .method = api.RevokeToken.method,
    //         .user_agent = user_agent,
    //         .authorization = self.basic_auth,
    //         .payload = payload,
    //     });
    //     try request.send();
    //     defer request.deinit();

    //     // print("revoke token: {s}\n", .{response.payload});
    // }
};

// ===============================

const print = std.debug.print;
const Headers = std.http.Client.Request.Headers;

const testDataAlloc = @import("util.zig").testDataAlloc;
const testData = @import("util.zig").testData;

test "authorization implicit" {
    if (true) return error.SkipZigTest;

    // const allocator = std.testing.allocator;
    const allocator = std.heap.page_allocator;

    var client = Client{ .allocator = allocator };
    defer client.deinit();

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();
    // const respbuf = ResponseBuffer{ .dynamic = &list };

    const td = try testDataAlloc(allocator);

    const ctx = api.Authorize{
        .client_id = td.installed_client_id,
        .response_type = .token,
        .state = "alksudc;oliau;",
        .redirect_uri = td.redirect_uri,
    };

    const url = try ctx.cowFullUrl(allocator);
    defer url.deinit(allocator);
    const uri = try std.Uri.parse(url.value);

    var headers = Headers{};
    // if (self.authorization) |authorization| headers.authorization = .{ .override = authorization };
    headers.user_agent = .{ .override = td.user_agent };

    var header_buf: [1 << 13]u8 = undefined;
    const request_options = Client.RequestOptions{
        .server_header_buffer = &header_buf,
        .headers = headers,
    };

    var req = try client.open(.POST, uri, request_options);
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    switch (req.response.status) {
        .ok => {},
        else => |status| {
            std.debug.print("status: {any}\n", .{status});
            return error.Undefined;
        },
    }

    req.reader().readAllArrayList(&list, 2 * 1024 * 1024) catch return error.ResponseBufferOutOfMemory;
    const payload = list.toOwnedSlice() catch return error.ResponseBufferOutOfMemory;
    _ = payload;

    // req.response.iterateHeaders();

    print("\n", .{});
    // print("header_buf:\n{s}\n\n", .{header_buf});

    {
        const hparser = std.http.HeadParser;
        _ = hparser;

        // req.response.parse()
        var it = req.response.iterateHeaders();

        while (it.next()) |h| {
            print("{s}: {s}\n", .{ h.name, h.value });
        }
    }

    // const request = Request{
    //     .client = &client,
    //     .response_buffer = respbuf,
    //     .url = url.value,
    //     .method = api.Authorize.method,
    //     .user_agent = td.user_agent,
    // };

}
