const std = @import("std");

const Cookie = @This();

pub const Expiration = union(enum) {
    datetime: []const u8, // TODO
    session: void,
};

pub const SameSite = enum {
    None,
    Lax,
    Strict,
};

name: []const u8,
value: []const u8 = "",
max_age: ?u64 = null,
expires: ?Expiration = null,
partitioned: ?bool = null,
domain: ?[]const u8 = null,
path: ?[]const u8 = null,
same_site: ?SameSite = null,
http_only: ?bool = null,
secure: ?bool = null,

// fn parse()
