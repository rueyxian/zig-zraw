const std = @import("std");
const Method = std.http.Method;

const domain_oauth = @import("../api.zig").domain_oauth;

pub fn New(comptime subreddit: []const u8) type {
    return struct {
        after: ?[]const u8 = null,
        before: ?[]const u8 = null,
        count: ?u64 = null,
        limit: ?u64 = null,
        pub const endpoint = domain_oauth ++ "r/" ++ subreddit ++ "/new";
        pub const method = Method.GET;
        pub const Payload = struct {
            //
        };
    };
}
