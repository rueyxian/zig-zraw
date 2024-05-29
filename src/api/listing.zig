const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

const model = @import("../model.zig");
const api = @import("../api.zig");
const url_domain = api.url_domain;
const url_domain_oauth = api.url_doman_oauth;
const Thing = model.Thing;

pub const LinksNew = struct {
    subreddit: []const u8,
    after: ?[]const u8 = null,
    before: ?[]const u8 = null,
    count: ?u64 = null,
    limit: ?std.math.IntFittingRange(0, 100) = null,
    sr_detail: ?bool = null,

    pub const path = "/r/{subreddit}/new";
    pub const url = url_domain ++ path ++ ".json";
    pub const url_oauth = url_domain_oauth ++ path;

    pub const method = Method.GET;
    pub const Model = Thing;

    pub const cowFullUrl = api.getCowFullUrlFn(
        @This(),
        url,
        api.fieldNamesTupleExceptFor(@This(), .{"subreddit"}),
    );
    pub const cowFullUrlOauth = api.getCowFullUrlFn(
        @This(),
        url_oauth,
        api.fieldNamesTupleExceptFor(@This(), .{"subreddit"}),
    );

    /// NOTE: Not intended for client-level use
    pub fn writeParamValueLimit(ctx: *const @This(), writer: anytype) !void {
        const limit = ctx.limit orelse return;
        if (limit > 100) {
            @panic("Param `limit` cannot be more than 100");
        }
        try writer.print("{}", .{limit});
    }

    /// NOTE: Not intended for client-level use
    pub fn writeParamValueSrDetail(ctx: *const @This(), writer: anytype) !void {
        const sr_detail = ctx.sr_detail orelse return;
        try writer.writeByte((&[_]u8{ '0', '1' })[@intFromBool(sr_detail)]);
    }
};

// https://www.reddit.com/dev/api/#GET_comments_{article}
// pub fn (comptime subreddit: []const u8, comptime article: []const u8) type {
pub const LinkComments = struct {
    subreddit: []const u8,
    article: []const u8,
    context: ?std.math.IntFittingRange(0, 8) = null,
    depth: ?u64 = null,
    limit: ?u64 = null,
    showedits: ?bool = null,
    showmedia: ?bool = null,
    showmore: ?bool = null,
    showtitle: ?bool = null,
    sort: ?Sort = null,
    sr_detail: ?bool = null,
    theme: ?Theme = null,
    threaded: ?bool = null,
    truncate: ?std.math.IntFittingRange(0, 50) = null,

    pub const Sort = enum { confidence, top, new, controversial, old, random, qa, live };
    pub const Theme = enum { default, dark };

    pub const path = "/r/{subreddit}/comments/{article}";
    pub const url = url_domain ++ path ++ ".json";
    pub const url_oauth = url_domain_oauth ++ path;

    pub const method = Method.GET;
    pub const Model = [2]Thing;

    // pub usingnamespace api.MixinContexFetch(@This());
    // pub const UrlParams = api.PartialByExclusion(@This(), .{"subreddit"});

    // pub const urlParams = api.getPartialByExclusionFn(@This(), .{ "subreddit", "article" });
    pub const cowFullUrl = api.getCowFullUrlFn(
        @This(),
        url,
        api.fieldNamesTupleExceptFor(@This(), .{ "subreddit", "article" }),
    );
    pub const cowFullUrlOauth = api.getCowFullUrlFn(
        @This(),
        url_oauth,
        api.fieldNamesTupleExceptFor(@This(), .{ "subreddit", "article" }),
    );

    /// NOTE: Not intended for client-level use
    pub fn writeParamValueContext(self: *const @This(), writer: anytype) !void {
        const val = self.context orelse return;
        if (val > 10) {
            @panic("Param `context` must be in a range from 0 to 10");
        }
        try writer.print("{}", .{val});
    }

    /// NOTE: Not intended for client-level use
    pub fn writeParamValueTruncate(self: *const @This(), writer: anytype) !void {
        const val = self.truncate orelse return;
        if (val > 50) {
            @panic("Param `truncate` must be in a range from 0 to 50");
        }
        try writer.print("{}", .{val});
    }
};
