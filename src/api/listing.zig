const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

// const BytesIterator = @import("../util.zig").BytesIterator;
const model = @import("../model.zig");
const api = @import("../api.zig");
const domain_oauth = api.domain_oauth;
const Thing = model.Thing;
// const api = @import("../api.zig");

const ApiRequest = @import("../ApiRequest.zig");
const ApiResponse = ApiRequest.ApiResponse;

const BytesIterator = struct {
    bytes: []const u8,
    pos: usize = 0,

    pub fn next(self: *@This()) ?u8 {
        std.debug.assert(self.pos <= self.bytes.len);
        if (self.pos == self.bytes.len) return null;
        defer self.pos += 1;
        return self.bytes[self.pos];
    }

    pub fn peek(self: *const @This()) ?u8 {
        std.debug.assert(self.pos <= self.bytes.len);
        if (self.pos + 1 == self.bytes.len) return null;
        return self.bytes[self.pos + 1];
    }
};

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

        pub usingnamespace api.MixinContextFetchAdaptor(@This());
        // pub const fetchAdaptor = api.getContextFetchAdaptorFn(@This());

        /// WARNING: Not intended for use at the client level.
        pub fn writeParamValueLimit(self: *@This(), writer: anytype) void {
            if (self.limit > 100) {
                @panic("Param `limit` cannot be more than 100");
            }
            var _buf: [api.maxUintLength(@TypeOf(self.limit))]u8 = undefined;
            const s = try std.fmt.bufPrint(&_buf, "{}", .{self.limit});
            try writer.writeAll(s);
        }

        /// WARNING: Not intended for use at the client level.
        pub fn writeParamValueSrDetail(self: *@This(), writer: anytype) void {
            try writer.writeByte((&[_]u8{ '0', '1' })[@intFromBool(self.sr_detail)]);
        }
    };
}

// https://www.reddit.com/dev/api/#GET_comments_{article}
pub fn ListingComments(comptime subreddit: []const u8, comptime article: []const u8) type {
    return struct {
        comment: ?[]const u8 = null,
        context: ?std.math.IntFittingRange(0, 8) = null,
        depth: ?u64 = null,
        limit: ?u64 = null,
        showedits: bool,

        pub const url = domain_oauth ++ "r/" ++ subreddit ++ "/comments/" ++ article;
        pub const method = Method.GET;
        pub const Model = [2]Thing;
        pub usingnamespace api.MixinContextFetchAdaptor(@This());
    };
}

// fn writeFromSnakeToPascal(writer: anytype, s: []const u8) !void {
//     if (s.len == 0) return;
//     try writer.writeByte(std.ascii.toUpper(s[0]));
//     if (s.len == 1) return;
//     var it = BytesIterator{ .bytes = s[1..] };
//     while (it.next()) |byte| {
//         if (byte != '_') {
//             try writer.writeByte(byte);
//             continue;
//         }
//         const bytes2 = std.ascii.toUpper(it.next() orelse break);
//         try writer.writeByte(bytes2);
//     }
// }

// inline fn getWriteParamValueFnName(comptime field_name: []const u8) []const u8 {
//     comptime {
//         var buffer: ty: {
//             var len = "writeParamValue".len;
//             for (field_name) |byte| {
//                 if (byte != '_') len += 1;
//             }
//             break :ty [len]u8;
//         } = undefined;
//         var fba = std.io.fixedBufferStream(&buffer);
//         fba.writer().writeAll("writeParamValue") catch unreachable;
//         writeFromSnakeToPascal(fba.writer(), field_name) catch unreachable;
//         return fba.getWritten();
//     }
// }

// test "aslieru" {
//     const Context = ListingNew("zig");

//     const info = @typeInfo(Context).Struct;

//     inline for (info.fields) |field| {
//         //

//         const fn_name = getWriteParamValueFnName(field.name);

//         // const fn_name: []const u8 = comptime blk: {
//         //     var buffer: ty: {
//         //         var len = "writeParam".len;
//         //         for (field.name) |byte| {
//         //             if (byte != '_') len += 1;
//         //         }
//         //         break :ty [len]u8;
//         //     } = undefined;
//         //     var fba = std.io.fixedBufferStream(&buffer);
//         //     try fba.writer().writeAll("writeParam");
//         //     try writeFromSnakeToPascal(fba.writer(), field.name);

//         //     break :blk fba.getWritten();
//         //     // break :blk;
//         // };

//         @compileLog(fn_name);

//         // std.debug.print("{s}\n", .{fn_name});
//     }

//     // =====================

//     // const x = "hello_world";
//     // var buffer: [1024]u8 = undefined;

//     // var fba = std.io.fixedBufferStream(&buffer);

//     // try writeFromSnakeToPascal(fba.writer(), x);

//     // std.debug.print("{s}\n", .{fba.getWritten()});

//     // const fn_name = blk: {

//     // };
// }
