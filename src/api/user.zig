const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

const model = @import("../model.zig");
const api = @import("../api.zig");
const domain_oauth = api.domain_oauth;
const Thing = model.Thing;

const ApiRequest = @import("../ApiRequest.zig");
const ApiResponse = ApiRequest.ApiResponse;

pub fn UserComments(comptime subreddit: []const u8) type {
    return struct {
        context: std.math.IntFittingRange(2, 10) = null,
        // show: // NOTE unimplemented
        after: ?[]const u8 = null,
        before: ?[]const u8 = null,
        // show
        count: ?u64 = null,
        limit: ?u64 = null,
        sr_detail: ?bool = null,
        pub const url = domain_oauth ++ "r/" ++ subreddit ++ "/new";
        pub const method = Method.GET;
        pub const Model = Thing;
        pub usingnamespace api.MixinContexFetch(@This());
    };
}
