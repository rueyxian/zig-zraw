const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

const model = @import("../model.zig");
const api = @import("../api.zig");
const domain_oauth = api.domain_oauth;
const Thing = model.Thing;

pub fn ListingNew(comptime subreddit: []const u8) type {
    return struct {
        after: ?[]const u8 = null,
        before: ?[]const u8 = null,
        count: ?u64 = null,
        limit: ?std.math.IntFittingRange(0, 100) = null,
        sr_detail: ?bool = null,

        pub const url = domain_oauth ++ "r/" ++ subreddit ++ "/new";
        pub const method = Method.GET;
        pub const Model = Thing;

        pub usingnamespace api.MixinContexFetch(@This());

        /// WARNING: Not intended for client-level use
        pub fn writeParamValueLimit(self: *const @This(), writer: anytype) !void {
            const limit = self.limit orelse return;
            if (limit > 100) {
                @panic("Param `limit` cannot be more than 100");
            }
            try writer.print("{}", .{limit});
        }

        /// WARNING: Not intended for client-level use
        pub fn writeParamValueSrDetail(self: *const @This(), writer: anytype) !void {
            const sr_detail = self.sr_detail orelse return;
            try writer.writeByte((&[_]u8{ '0', '1' })[@intFromBool(sr_detail)]);
        }
    };
}

// https://www.reddit.com/dev/api/#GET_comments_{article}
pub fn ListingComments(comptime subreddit: []const u8, comptime article: []const u8) type {
    return struct {
        // article: // NOTE unimplemented
        // comment: ?[]const u8 = null, // NOTE unimplemented
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

        pub const url = domain_oauth ++ "r/" ++ subreddit ++ "/comments/" ++ article;
        pub const method = Method.GET;
        pub const Model = [2]Thing;

        pub usingnamespace api.MixinContexFetch(@This());

        /// WARNING: Not intended for client-level use
        pub fn writeParamValueContext(self: *const @This(), writer: anytype) !void {
            const val = self.context orelse return;
            if (val > 10) {
                @panic("Param `context` must be in a range from 0 to 10");
            }
            try writer.print("{}", .{val});
        }

        /// WARNING: Not intended for client-level use
        pub fn writeParamValueTruncate(self: *const @This(), writer: anytype) !void {
            const val = self.truncate orelse return;
            if (val > 50) {
                @panic("Param `truncate` must be in a range from 0 to 50");
            }
            try writer.print("{}", .{val});
        }
    };
}
