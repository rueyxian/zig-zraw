const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

const model = @import("../model.zig");
// const getEndpoint = @import("../endpoint.zig").getEndpoint;
const endpoint = @import("../endpoint.zig");
const getToEndpointFn = @import("../endpoint.zig").getToEndpointFn;
const domain_oauth = endpoint.domain_oauth;
// const Number = api.Number;
const Thing = model.Thing;
// const api = @import("../api.zig");

pub fn New(comptime subreddit: []const u8) type {
    return struct {
        after: ?[]const u8 = null,
        before: ?[]const u8 = null,
        count: ?u64 = null,
        limit: ?u64 = null,
        pub const url = domain_oauth ++ "r/" ++ subreddit ++ "/new";
        pub const method = Method.GET;
        pub const Model = model.Thing(model.Listing);
        // pub fn toEndpoint(self: @This(), allocator: Allocator) Endpoint(Model) { getEndpoint(allocator, self);
        // }

        // pub const toEndpoint = getToEndpointFn(@This());
    };
}

// https://www.reddit.com/dev/api/#GET_comments_{article}
pub fn Comments(comptime subreddit: []const u8, comptime article: []const u8) type {
    _ = subreddit; // autofix
    _ = article; // autofix
    return struct {
        // article: []const

    };
}

// pub fn ListingData(comptime T: type) type {
//     return struct {
//         after: ?[]const u8,
//         dist: ?Number,
//         modhash: ?[]const u8,
//         children: []const GenericPayload(T),
//     };
// }

// pub fn
