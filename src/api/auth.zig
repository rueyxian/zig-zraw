const std = @import("std");
const fmt = std.fmt;
const debug = std.debug;
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

const api = @import("../api.zig");
const kvs = @import("../kvs.zig");
const url_domain = api.url_domain;

const CowString = @import("../CowString.zig");

const Token = @import("../model/auth.zig").Token;
const Scope = @import("../model/auth.zig").Scope;

pub const Duration = enum {
    temporary,
    permanent,
};

pub const ResponseType = enum { code, token };

pub const GrantType = enum {
    authorization_code,
    client_credentials,
    password,
    refresh_token,
};

pub const TokenTypeHint = enum {
    access_token,
    refresh_token,
};

pub const Authorize = struct {
    client_id: []const u8,
    response_type: ResponseType,
    state: []const u8,
    redirect_uri: []const u8,
    duration: ?Duration = null, // NOTE: temporary by default
    scope: []const Scope,

    pub const path = "/api/v1/authorize";
    pub const url = url_domain ++ path;

    pub const method: Method = .POST;
    pub const Model = Token;

    pub fn cowFullUrl(self: *const @This(), allocator: Allocator) api.ApiError!CowString {
        return switch (self.response_type) {
            .code => try self.cowFullUrlCodeGrant(allocator),
            .token => try self.cowFullUrlImplicitGrant(allocator),
        };
    }

    pub const cowFullUrlCodeGrant = api.getCowFullUrlFn(
        @This(),
        url,
        .{ "client_id", "response_type", "state", "redirect_uri", "duration", "scope" },
    );
    pub const cowFullUrlImplicitGrant = api.getCowFullUrlFn(
        @This(),
        url,
        .{ "client_id", "response_type", "state", "redirect_uri", "scope" },
    );

    /// NOTE: Not intended for client-level use
    pub const writeParamValueScope = getWriteParamValueScopeFn(@This());
};

pub const AccessToken = struct {
    grant_type: GrantType,
    code: ?[]const u8 = null,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    device_id: ?[]const u8 = null,
    redirect_uri: ?[]const u8 = null,
    scope: ?[]const Scope = null,
    refresh_token: ?[]const u8 = null,

    pub const path = "/api/v1/access_token";
    pub const url = url_domain ++ path;
    pub const method: Method = .POST;

    pub const Model = Token;

    pub const cowFullUrl = api.getCowFullUrlFn(
        @This(),
        url,
        .{},
    );

    // pub const allocBasicAuth = getAllocBasicAuthFn(@This());
    pub fn allocPayload(self: *const @This(), allocator: Allocator) api.Error![]const u8 {
        return switch (self.grant_type) {
            .authorization_code => try self.allocPayloadCodeGrant(allocator),
            .client_credentials => try self.allocPayloadClientCredentialsGrant(allocator),
            .password => try self.allocPayloadPasswordGrant(allocator),
            .refresh_token => try self.allocPayloadRefreshTokenGrant(allocator),
        };
    }

    pub const allocPayloadCodeGrant = api.getAllocPayloadFn(
        @This(),
        .{ "grant_type", "code", "redirect_uri" },
    );

    pub const allocPayloadPasswordGrant = api.getAllocPayloadFn(
        @This(),
        .{ "grant_type", "username", "password" },
    );

    pub const allocPayloadClientCredentialsGrant = api.getAllocPayloadFn(
        @This(),
        .{ "grant_type", "device_id" },
    );

    pub const allocPayloadRefreshTokenGrant = api.getAllocPayloadFn(
        @This(),
        .{ "grant_type", "refresh_token" },
    );

    /// NOTE: Not intended for client-level use
    pub fn writeParamValueGrant(self: *const @This(), writer: anytype) api.ApiError!void {
        const device_id = self.device_id orelse "DO_NOT_TRACK_THIS_DEVICE";
        try writer.writeAll(device_id);
    }

    /// NOTE: Not intended for client-level use
    pub const writeParamValueScope = getWriteParamValueScopeFn(@This());
};

pub const RevokeToken = struct {
    client_id: []const u8,
    client_secret: ?[]const u8,
    token: []const u8,
    token_type_hint: ?TokenTypeHint = null, // NOTE: will still succeed per normal if not given though may be slower.

    pub const path = "/api/v1/revoke_token";
    pub const url = url_domain ++ path;
    pub const method: Method = .POST;

    pub const cowFullUrl = api.getCowFullUrlFn(
        @This(),
        url,
        .{},
    );

    pub const allocBasicAuth = getAllocBasicAuthFn(@This());
    pub const allocPayload = api.getAllocPayloadFn(
        @This(),
        .{ "token", "token_type_hint" },
    );
};

fn getWriteParamValueScopeFn(Context: type) fn (*const Context, anytype) api.ApiError!void {
    return struct {
        pub fn func(self: *const Context, writer: anytype) api.ApiError!void {
            const scope = self.scope orelse return;
            for (scope, 0..) |e, i| {
                if (i != 0) {
                    try writer.writeByte(' ');
                }
                try writer.writeAll(@tagName(e));
            }
        }
    }.func;
}

fn getAllocBasicAuthFn(comptime Context: type) fn (*const Context, allocator: Allocator) api.ApiError![]const u8 {
    return struct {
        pub fn func(self: *const Context, allocator: Allocator) api.ApiError![]const u8 {
            var fba_buf: [1 << 7]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&fba_buf);
            const fballoc = fba.allocator();

            const Base64Encoder = std.base64.standard.Encoder;
            const s = try fmt.allocPrint(fballoc, "{s}:{s}", .{ self.client_id, self.client_secret orelse "" }); // NOTE: free not required
            const buf = try fballoc.alloc(u8, Base64Encoder.calcSize(s.len)); // NOTE: free not required

            const encoded = Base64Encoder.encode(buf, s);
            debug.assert(encoded.len == buf.len);
            return try fmt.allocPrint(allocator, "Basic {s}", .{encoded});
        }
    }.func;
}
