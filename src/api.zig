const std = @import("std");
const testing = std.testing;
const debug = std.debug;
const mem = std.mem;
const Method = std.http.Method;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
// const ResponseStorage = std.http.Client.FetchOptions.ResponseStorage;

// const CowBytes = @import("cow_bytes.zig").CowBytes;
const CowString = @import("CowString.zig");

const ApiRequest = @import("ApiRequest.zig");
const ApiResponse = ApiRequest.ApiResponse;
const RequestError = ApiRequest.HttpError;
const ResponseBuffer = ApiRequest.ResponseBuffer;

pub const AccessToken = @import("api/access_token.zig").AccessToken;

const account = @import("api/account.zig");
pub const AccountMe = account.AccountMe;

const listing = @import("api/listing.zig");
pub const ListingNew = listing.ListingNew;
pub const ListingComments = listing.ListingComments;
// pub const AccessToken = listing

pub const domain_www = "https://www.reddit.com/";
pub const domain_oauth = "https://oauth.reddit.com/";

pub const FetchError = ApiRequest.HttpError || Allocator.Error;

pub const Sort = enum {
    hot,
    new,
    top,
    controversial,
};

pub const Time = enum {
    hour,
    day,
    week,
    month,
    year,
    all,
};

pub fn verifyContext(comptime Context: type) void {
    if (isContext(Context)) return;
    @panic("Invalid context type.");
}

pub fn isContext(comptime Context: type) bool {
    const info = @typeInfo(Context);
    if (info != .Struct) return false;
    if (@hasDecl(Context, "url") == false) return false;
    if (@hasDecl(Context, "method") == false) return false;
    if (@hasDecl(Context, "Model") == false) return false;
    {
        const url_info = @typeInfo(@TypeOf(@field(Context, "url")));
        if (url_info != .Pointer) return false;
        if (url_info.Pointer.size != .One) return false;
        if (url_info.Pointer.is_const == false) return false;
        debug.assert(url_info.Pointer.sentinel == null);

        const child_info = @typeInfo(url_info.Pointer.child);
        if (child_info != .Array) return false;
        if (child_info.Array.child != u8) return false;

        if (child_info.Array.sentinel) |sen| {
            if (@as(*const u8, @ptrCast(@alignCast(sen))).* != 0) return false;
        } else return false;
    }
    if (@TypeOf(@field(Context, "method")) != Method) return false;
    if (@TypeOf(@field(Context, "Model")) != type) return false;
    return true;
}

pub fn stringifyUrlFromContext(allocator: Allocator, context: anytype) !CowString {
    const Context = @TypeOf(context);
    verifyContext(Context);
    const info = @typeInfo(Context);
    debug.assert(info == .Struct);
    const fields = info.Struct.fields;
    var buf = std.ArrayList(u8).init(allocator);
    var writer = buf.writer();
    var has_param: bool = false;
    inline for (fields) |field| {
        if (@field(context, field.name)) |val| {
            if (has_param == false) {
                try writer.writeAll(Context.url);
                try writer.writeByte('?');
                has_param = true;
            } else {
                try writer.writeByte('&');
            }
            // try writer.writeByte(([_]u8{ '?', '&' })[@intFromBool(param_count != 0)]);
            try writer.writeAll(field.name);
            try writer.writeByte('=');

            const write_param_value_fn_name = getWriteParamValueFnName(field.name);

            if (@hasDecl(Context, write_param_value_fn_name)) {
                try @field(Context, write_param_value_fn_name)(&context, writer);
            } else {
                switch (@typeInfo(@TypeOf(val))) {
                    .Bool => try writer.writeAll((&[_]u8{ "false", "true" })[@intFromBool(val)]),
                    .Pointer => |ptr_info| {
                        debug.assert(ptr_info.size == .Slice);
                        debug.assert(ptr_info.is_const == true);
                        debug.assert(ptr_info.child == u8);
                        try writer.writeAll(val);
                    },
                    .Int => try writer.print("{}", .{val}),
                    else => unreachable,
                }
            }
        }
    }
    if (has_param) {
        return CowString.owned(try buf.toOwnedSlice());
    }
    return CowString.borrowed(Context.url);
}

fn writeFromSnakeToPascal(writer: anytype, s: []const u8) !void {
    if (s.len == 0) return;
    try writer.writeByte(std.ascii.toUpper(s[0]));
    if (s.len == 1) return;
    var it = BytesIterator{ .bytes = s[1..] };
    while (it.next()) |byte| {
        if (byte != '_') {
            try writer.writeByte(byte);
            continue;
        }
        const bytes2 = std.ascii.toUpper(it.next() orelse break);
        try writer.writeByte(bytes2);
    }
}

inline fn getWriteParamValueFnName(comptime field_name: []const u8) []const u8 {
    comptime {
        var buffer: ty: {
            var len = "_writeParamValue".len;
            for (field_name) |byte| {
                if (byte != '_') len += 1;
            }
            break :ty [len]u8;
        } = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        fbs.writer().writeAll("_writeParamValue") catch unreachable;
        writeFromSnakeToPascal(fbs.writer(), field_name) catch unreachable;
        return fbs.getWritten();
    }
}

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

pub const ContextFetchOptions = struct {
    client: *Client,
    response_buffer: ResponseBuffer,
    user_agent: []const u8,
    authorization: []const u8,
    payload: ?[]const u8,
};

pub fn MixinContexFetch(comptime Context: type) type {
    verifyContext(Context);
    return struct {
        pub fn fetch(ctx: Context, allocator: Allocator, options: ContextFetchOptions) FetchError!ApiResponse {
            // var request = try ApiRequest.fromContext(allocator, ctx);

            const url = try stringifyUrlFromContext(allocator, ctx);
            defer url.deinit(allocator);

            var request = ApiRequest{
                .url = url.value,
                .method = @TypeOf(ctx).method,
                .user_agent = options.user_agent,
                .authorization = options.authorization,
                .payload = options.payload,
            };

            return request.fetch(options.client, options.response_buffer);
        }
    };
}

test "asdlkfj" {
    // const allocator = std.heap.page_allocator;
    const allocator = std.testing.allocator;

    const context = ListingNew("zig"){
        // .count = 3,
        // .limit = 9,
    };

    const url = try stringifyUrlFromContext(allocator, context);
    // defer url.deinit(allocator);

    std.debug.print("url: {s}\n", .{url.value});
}
