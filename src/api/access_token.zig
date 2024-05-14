const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

const api = @import("../api.zig");
const domain_www = api.domain_www;

pub const AccessToken = struct {
    pub const url = domain_www ++ "api/v1/access_token";
    pub const method: Method = .POST;
    pub const Model = struct {
        access_token: []const u8,
        token_type: []const u8,
        expires_in: u64,
        scope: []const u8,
    };

    pub usingnamespace api.MixinContexFetch(@This());
};

pub const RevokeToken = struct {
    token: []const u8,
    token_type: []const u8,

    pub const url = domain_www ++ "api/v1/revoke_token";
    pub const method: Method = .POST;
    // pub const Model = struct {
    //     access_token: []const u8,
    //     token_type: []const u8,
    //     expires_in: u64,
    //     scope: []const u8,
    // };

    pub usingnamespace api.MixinContexFetch(@This());
};
