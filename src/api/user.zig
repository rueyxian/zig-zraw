const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

const model = @import("../model.zig");
const api = @import("../api.zig");

const domain_oauth = api.domain_oauth;
const Thing = model.Thing;

pub fn UserComments(comptime username: []const u8) type {
    return struct {
        context: ?std.math.IntFittingRange(2, 10) = null,
        // show: // NOTE unimplemented
        sort: ?Sort = null,
        t: ?T = null,
        type: ?Type = null,
        // username: []const u8, // NOTE unimplemented
        after: ?[]const u8 = null,
        before: ?[]const u8 = null,
        count: ?u64 = null,
        limit: ?u64 = null,
        sr_detail: ?bool = null,

        pub const url = domain_oauth ++ "user/" ++ username ++ "/comments";
        pub const method = Method.GET;
        pub const Model = Thing;
        pub usingnamespace api.MixinContexFetch(@This());

        pub const Sort = enum {
            hot,
            new,
            top,
            controversial,
        };
        pub const T = enum {
            hour,
            day,
            week,
            month,
            year,
            all,
        };
        pub const Type = enum {
            link,
            comments,
        };

        /// WARNING: Not intended for use at the client level.
        pub fn _writeParamValueContext(self: *const @This(), writer: anytype) !void {
            const context = self.context orelse return;
            if (context < 2 or context > 10) {
                @panic("Param `context` must be in a range from 2 to 10");
            }
            try writer.print("{}", .{context});
        }
    };
}
