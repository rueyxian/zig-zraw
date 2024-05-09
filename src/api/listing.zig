const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

const model = @import("../model.zig");
const api = @import("../api.zig");
const domain_oauth = api.domain_oauth;
const Thing = model.Thing;
// const api = @import("../api.zig");

const ApiRequest = @import("../ApiRequest.zig");
const ApiResponse = ApiRequest.ApiResponse;

pub fn ListingNew(comptime subreddit: []const u8) type {
    return struct {
        after: ?[]const u8 = null,
        before: ?[]const u8 = null,
        count: ?u64 = null,
        limit: ?u64 = null,
        sr_detail: ?bool = null,
        pub const url = domain_oauth ++ "r/" ++ subreddit ++ "/new";
        pub const method = Method.GET;
        pub const Model = Thing;
        // pub const fetchAdaptor = api.contextFetchAdaptor;
        pub const fetchAdaptor = api.getContextFetchAdaptorFn(@This());

        // pub fn fetchAdaptor(self: *const @This(), allocator: std.mem.Allocator, options: api.FetchOptions) !ApiResponse {
        //     // return api.getContextFetchFn(@This())(self, allocator, options);
        //     // std.debug.print("DEBUG MODEL: {}\n", .{@This().Model});

        //     return api.ImplFetchAdaptorFn(@This()).fetchAdaptor(self, allocator, options);
        // }
    };
}

// https://www.reddit.com/dev/api/#GET_comments_{article}
pub fn ListingComments(comptime subreddit: []const u8, comptime article: []const u8) type {
    return struct {
        pub const url = domain_oauth ++ "r/" ++ subreddit ++ "/comments/" ++ article;
        pub const method = Method.GET;
        pub const Model = [2]Thing;
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
