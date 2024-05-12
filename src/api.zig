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

// pub const EndpointError = error{
//     InvalidEndpointContext,
// };

pub const EndpointError = Allocator.Error || std.io.FixedBufferStream([]u8).WriteError;

pub const FetchError = EndpointError || ApiRequest.HttpError;

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

// pub const IdentifiedType = enum {
//     endpoint,
//     context,
//     invalid,
// };

// pub fn identifyType(comptime T: type) IdentifiedType {
//     // const info = @typeInfo(T);
//     // _ = info; // autofix
//     // debug.assert(info == .Struct);
//     if (isEndpoint(T)) {
//         return .endpoint;
//     } else if (isContext(T)) {
//         return .endpoint;
//     }
//     return .invalid;
// }

pub fn verifyEndpointOrContext(comptime EndpointOrContext: type) void {
    if (isEndpoint(EndpointOrContext)) return;
    if (isContext(EndpointOrContext)) return;
    @panic("Invalid endpoint or context type.");

    // const msg = "Invalid endpoint or context type. " ++ "Cannot use " ++ @typeName(EndpointOrContext);
    // if (@inComptime()) {
    //     @compileError(msg);
    // } else {
    //     @panic(msg);
    // }

}

pub fn verifyEndpoint(comptime EndpointType: type) void {
    if (isEndpoint(EndpointType)) return;
    @panic("Invalid endpoint type.");

    // const msg = "Invalid endpoint type. " ++ "Cannot use " ++ @typeName(EndpointType);
    // if (@inComptime()) {
    //     @compileError(msg);
    // } else {
    //     @panic(msg);
    // }
}

pub fn verifyContext(comptime Context: type) void {
    if (isContext(Context)) return;
    @panic("Invalid context type.");

    // @panic("Invalid context type. " ++ "Cannot use " ++ @typeName(Context));
    // @compileError();

    // const msg = "Invalid context type. " ++ "Cannot use " ++ @typeName(Context);
    // if (@inComptime()) {
    //     @compileError(msg);
    // } else {
    //     @panic(msg);
    // }
}

pub fn isEndpoint(comptime EndpointType: type) bool {
    const info = @typeInfo(EndpointType);
    if (info != .Struct) return false;
    if (@hasDecl(EndpointType, "Model") == false) return false;
    return Endpoint(EndpointType.Model) == EndpointType;
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

// pub fn verifyEndpoint(comptime EndpointType: type) void {
//     if (isEndpoint(EndpointType)) return;
//     @compileError("Invalid endpoint type");
// }

// pub fn verifyContext(comptime Context: type) void {
//     if (isContext(Context)) return;
//     @compileError("Invalid context type");
// }

pub fn endpointFromContext(allocator: Allocator, context: anytype) EndpointError!Endpoint(@TypeOf(context).Model) {
    const Context = @TypeOf(context);
    verifyContext(Context);
    const info = @typeInfo(Context);
    debug.assert(info == .Struct);
    const fields = info.Struct.fields;
    if (fields.len == 0) {
        const url = CowString.borrowed(Context.url);
        return Endpoint(Context.Model){
            .url = url,
            .method = Context.method,
        };
    }
    const buf = try allocator.alloc(u8, fullEndpointLength(context));
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    try w.writeAll(Context.url);

    var param_count: usize = 0;
    inline for (fields) |field| {
        if (@field(context, field.name)) |val| {
            try w.writeByte(([_]u8{ '?', '&' })[@intFromBool(param_count != 0)]);
            try w.writeAll(field.name);
            try w.writeByte('=');

            // const fn_name = blk: {
            //     const field_name = field.name;
            //   break :blk;
            // };

            const write_param_value_fn_name = getWriteParamValueFnName(field.name);

            if (@hasDecl(Context, write_param_value_fn_name)) {
                @field(Context, write_param_value_fn_name)(w);
                continue;
            }

            // TODO CONTINUE HERE

            switch (@TypeOf(val)) {
                bool => try w.writeByte((&[_]u8{ '0', '1' })[@intFromBool(val)]),
                []const u8 => try w.writeAll(val),
                u64 => {
                    var _buf: [maxUintLength(u64)]u8 = undefined;
                    const s = try std.fmt.bufPrint(&_buf, "{}", .{val});
                    try w.writeAll(s);
                },
                else => unreachable,
            }
            param_count += 1;
        }
    }
    debug.assert(try fbs.getPos() == buf.len);
    const url = CowString.owned(fbs.getWritten());
    return Endpoint(Context.Model){
        .url = url,
        .method = Context.method,
    };
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
            var len = "writeParamValue".len;
            for (field_name) |byte| {
                if (byte != '_') len += 1;
            }
            break :ty [len]u8;
        } = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        fbs.writer().writeAll("writeParamValue") catch unreachable;
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

pub fn getEndpoint(allocator: Allocator, context: anytype) EndpointError!Endpoint(@TypeOf(context).Model) {
    const Context = @TypeOf(context);
    // if (isContext(Context) == false) {
    //     @panic("Invalid context type");
    // }
    verifyContext(Context);
    const info = @typeInfo(Context);
    debug.assert(info == .Struct);
    const fields = info.Struct.fields;
    if (fields.len == 0) {
        const url = CowString.borrowed(Context.url);
        return Endpoint(Context.Model){
            .url = url,
            .method = Context.method,
        };
    }
    const buf = try allocator.alloc(u8, fullEndpointLength(context));
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    try w.writeAll(Context.url);

    var i: usize = 0;
    inline for (fields) |field| {
        if (@field(context, field.name)) |val| {
            try w.writeByte(([_]u8{ '?', '&' })[@intFromBool(i != 0)]);
            try w.writeAll(field.name);
            try w.writeByte('=');
            switch (@TypeOf(val)) {
                bool => try w.writeByte((&[_]u8{ '0', '1' })[@intFromBool(val)]),
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
    const url = CowString.owned(fbs.getWritten());
    return Endpoint(Context.Model){
        .url = url,
        .method = Context.method,
    };
}

pub const FetchOptions = struct {
    client: *Client,
    response_buffer: ResponseBuffer,
    // response_storage: ResponseStorage,
    user_agent: []const u8,
    authorization: []const u8,
    payload: ?[]const u8,
};

pub fn Endpoint(comptime ModelType: type) type {
    return struct {
        url: CowString,
        method: Method,

        pub const Self = @This();
        pub const Model = ModelType;

        pub fn deinit(self: Self, allocator: Allocator) void {
            self.url.deinit(allocator);
        }

        /// WARNING: Not intended for use at the client level.
        pub fn fetchAdaptor(self: *const Self, _: Allocator, options: FetchOptions) FetchError!ApiResponse {
            const request = ApiRequest{
                .uri = self.url.value,
                .method = self.method,
                .user_agent = options.user_agent,
                .authorization = options.authorization,
                .payload = options.payload,
            };
            return request.fetch(options.client, options.response_buffer);
        }
    };
}

// pub fn Endpoint(comptime ModelType: type) type {
//     return struct {
//         url: CowString,
//         method: Method,

//         pub const Self = @This();
//         pub const Model = ModelType;

//         pub fn deinit(self: Self, allocator: Allocator) void {
//             self.url.deinit(allocator);
//         }

//         pub fn fetchAdaptor(self: *const Self, _: Allocator, options: FetchOptions) ApiRequest.Error!ApiResponse {
//             const request = ApiRequest{
//                 .uri = self.url.value,
//                 .method = self.method,
//                 .user_agent = options.user_agent,
//                 .authorization = options.authorization,
//                 .payload = options.payload,
//             };
//             return request.fetch(options.client, options.response_buffer);
//         }
//     };
// }

pub fn MixinContextFetchAdaptor(comptime Context: type) type {
    return struct {
        /// WARNING: Not intended for use at the client level.
        pub fn fetchAdapter(ctx: *const Context, allocator: Allocator, options: FetchOptions) FetchError!ApiResponse {
            const endpoint = try getEndpoint(allocator, ctx.*);
            defer endpoint.deinit(allocator);
            return endpoint.fetchAdaptor(undefined, options);
        }
    };
}

// pub fn getContextFetchAdaptorFn(comptime Context: type) fn (*const Context, Allocator, FetchOptions) (FetchError!ApiResponse) {
//     return struct {
//         /// WARNING: Not intended for use at the client level.
//         fn f(ctx: *const Context, allocator: Allocator, options: FetchOptions) FetchError!ApiResponse {
//             const endpoint = try getEndpoint(allocator, ctx.*);
//             defer endpoint.deinit(allocator);
//             return endpoint.fetchAdaptor(undefined, options);
//         }
//     }.f;
// }

// pub fn contextFetchAdaptor(context: *const @This(), allocator: Allocator, options: FetchOptions) ApiRequest.HttpError!ApiResponse {
//     const endpoint = try getEndpoint(allocator, context);
//     endpoint.fetchAdaptor(undefined, options);
// }

// pub fn ImplFetchAdaptorFn(comptime Context: type) type {
//     return struct {
//         pub fn fetchAdaptor(context: *const Context, allocator: Allocator, options: FetchOptions) !ApiResponse {
//             const endpoint = try getEndpoint(allocator, context.*);
//             defer endpoint.deinit(allocator);
//             const request = ApiRequest{
//                 .uri = endpoint.url.value,
//                 .method = endpoint.method,
//                 .user_agent = options.user_agent,
//                 .authorization = options.authorization,
//                 .payload = options.payload,
//             };
//             return request.fetch(options.client, options.response_buffer);
//         }
//     };
// }

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
                bool => res += 1, // bool will convert to '0' or '1',
                []const u8 => res += val.len,
                u64 => res += uintLength(u64, val),
                else => unreachable,
            }
        }
    }
    return res;
}

pub fn maxUintLength(comptime T: type) usize {
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

// test "asdlkfj" {
//     const allocator = std.heap.page_allocator;

//     // const x =

//     const context = ListingNew("zig"){
//         .count = 3,
//     };

//     const endpoint = try getEndpoint(allocator, context);

//     std.debug.print("{s}\n", .{endpoint.url.value});
// }
