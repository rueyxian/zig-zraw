const std = @import("std");
const testing = std.testing;
const debug = std.debug;
const Method = std.http.Method;
const Allocator = std.mem.Allocator;

const CowBytes = @import("cow_bytes.zig").CowBytes;

pub const domain_www = "https://www.reddit.com/";
pub const domain_oauth = "https://oauth.reddit.com/";

pub fn getEndpoint(allocator: Allocator, api_context: anytype) !Endpoint(@TypeOf(api_context).Model) {
    const Context = @TypeOf(api_context);
    const info = @typeInfo(Context);
    debug.assert(info == .Struct);
    const fields = info.Struct.fields;
    if (fields.len == 0) {
        const url = CowBytes([]const u8).borrowed(Context.endpoint);
        return Endpoint(Context.Model){
            .url = url,
            .method = Context.method,
        };
    }
    const buf = try allocator.alloc(u8, fullEndpointLength(api_context));
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    try w.writeAll(Context.url);

    var i: usize = 0;
    inline for (fields) |field| {
        if (@field(api_context, field.name)) |val| {
            try w.writeByte(([_]u8{ '?', '&' })[@intFromBool(i != 0)]);
            try w.writeAll(field.name);
            try w.writeByte('=');
            switch (@TypeOf(val)) {
                []const u8 => try w.writeAll(val),
                u64 => {
                    var _buf: [maxUintLength(u4)]u8 = undefined;
                    const s = try std.fmt.bufPrint(&_buf, "{}", .{val});
                    try w.writeAll(s);
                },
                else => unreachable,
            }
            i += 1;
        }
    }
    debug.assert(try fbs.getPos() == buf.len);
    const url = CowBytes([]const u8).owned(fbs.getWritten());
    return Endpoint(Context.Model){
        .url = url,
        .method = Context.method,
    };
}

pub fn Endpoint(comptime ModelType: type) type {
    return struct {
        url: CowBytes([]const u8),
        method: Method,

        pub const Self = @This();
        pub const Model = ModelType;

        pub fn deinit(self: Self, allocator: Allocator) void {
            self.url.deinit(allocator);
        }
    };
}

fn fullEndpointLength(context: anytype) usize {
    const Context = @TypeOf(context);
    const info = @typeInfo(Context);
    debug.assert(info == .Struct);
    var res = Context.url.len;
    const fields = info.Struct.fields;

    inline for (fields) |field| {
        if (@field(context, field.name)) |val| {
            res += 2; // ('?' or '&') + '='
            res += field.name.len;
            switch (@TypeOf(val)) {
                []const u8 => res += val.len,
                u64 => res += uintLength(u64, val),
                else => unreachable,
            }
        }
    }
    return res;
}

fn maxUintLength(comptime T: type) usize {
    const info = @typeInfo(T);
    debug.assert(info == .Int);
    debug.assert(info.Int.signedness == .unsigned);
    comptime var res: usize = 0;
    comptime var num = std.math.maxInt(T);
    inline while (num != 0) {
        num /= 10;
        res += 1;
    }
    return res;
}

fn uintLength(comptime T: type, number: T) usize {
    const info = @typeInfo(T);
    debug.assert(info == .Int);
    debug.assert(info.Int.signedness == .unsigned);
    const pow_tens = blk: {
        var tens: [maxUintLength(T) - 1]T = undefined;
        inline for (&tens, 1..) |*n, i| {
            n.* = std.math.pow(T, 10, i);
        }
        break :blk tens;
    };
    var i: usize = 1;
    for (pow_tens) |n| {
        if (number < n) break;
        i += 1;
    }
    return i;
}
