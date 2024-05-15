const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Client = std.http.Client;
const Headers = std.http.Client.Request.Headers;
const Method = std.http.Method;
const ResponseStorage = std.http.Client.FetchOptions.ResponseStorage;
const Status = std.http.Status;

const api = @import("api.zig");

// TODO to be more specific
pub const Error = error{
    ResponseBufferOutOfMemory,
} || HttpError || Client.RequestError || std.Uri.ParseError || Client.Request.WriteError || Client.Request.WaitError || Client.Request.ReadError || Client.Request.FinishError;

pub const HttpError = error{
    Undefined,
};

pub const Response = struct {
    // status: Status,
    payload: []const u8,
    allocator: ?Allocator = null,

    pub fn deinit(self: @This()) void {
        const allocator = self.allocator orelse return;
        allocator.free(self.payload);
    }

    pub fn toOwned(self: Response, allocator: Allocator) !@This() {
        if (self.allocator) |_| @panic("Has already owned");
        const new_self = self;
        new_self.payload = try allocator.dupe(u8, self.payload);
        new_self.allocator = allocator;
        return new_self;
    }
};

const Request = @This();

url: []const u8,
method: Method,
user_agent: []const u8,
authorization: []const u8,
payload: ?[]const u8 = null,

pub const ResponseBuffer = union(enum) {
    dynamic: *std.ArrayList(u8),
    static: []u8,
};

pub fn fetch(self: *const Request, client: *Client, response_buffer: ResponseBuffer) Error!Response {
    var headers = Headers{};
    headers.authorization = .{ .override = self.authorization };
    headers.user_agent = .{ .override = self.user_agent };

    var header_buf: [1 << 12]u8 = undefined;
    const request_options = Client.RequestOptions{
        .server_header_buffer = &header_buf,
        .headers = headers,
    };
    const uri = try std.Uri.parse(self.url);

    var req = try client.open(self.method, uri, request_options);
    defer req.deinit();

    if (self.payload) |pl| req.transfer_encoding = .{ .content_length = pl.len };

    try req.send();
    if (self.payload) |pl| try req.writer().writeAll(pl);
    try req.finish();
    try req.wait();

    switch (req.response.status) {
        .ok => {},
        else => |status| {
            std.debug.print("status: {any}\n", .{status});
            return HttpError.Undefined;
        },
    }

    const payload = switch (response_buffer) {
        .dynamic => |list| blk: {
            req.reader().readAllArrayList(list, 2 * 1024 * 1024) catch return Error.ResponseBufferOutOfMemory;
            break :blk list.toOwnedSlice() catch return Error.ResponseBufferOutOfMemory;
        },
        .static => |buf| blk: {
            const read_len = try req.reader().readAll(buf);
            if (req.reader().readByte() != @TypeOf(req.reader()).Error.EndOfStream) {
                return Error.ResponseBufferOutOfMemory;
            }
            break :blk buf[0..read_len];
        },
    };

    return Response{
        .payload = payload,
    };
}

// pub fn fetch(self: *const Request, client: *Client, response_buffer: ResponseBuffer) Error!Response {
//     var headers = Headers{};
//     headers.authorization = .{ .override = self.authorization };
//     headers.user_agent = .{ .override = self.user_agent };

//     var fetch_options = std.http.Client.FetchOptions{
//         .location = .{ .url = self.url },
//         .method = self.method,
//         .payload = self.payload,
//         .headers = headers,
//     };
//     const payload = switch (response_buffer) {
//         .dynamic => |buffer| blk: {
//             fetch_options.response_storage = .{ .dynamic = buffer };
//             const result = client.fetch(fetch_options) catch return HttpError.Undefined;
//             if (result.status != .ok) {
//                 std.debug.print("status: {any}\n", .{result.status});
//                 return HttpError.Undefined;
//             }
//             break :blk buffer.items;
//         },
//         .static => |buf| blk: {
//             var fba = std.heap.FixedBufferAllocator.init(buf);
//             var buffer = std.ArrayListUnmanaged(u8).initCapacity(fba.allocator(), buf.len) catch unreachable;
//             fetch_options.response_storage = .{ .static = &buffer };
//             const result = client.fetch(fetch_options) catch return HttpError.Undefined;
//             if (result.status != .ok) {
//                 return HttpError.Undefined;
//             }
//             break :blk buffer.items;
//         },
//     };
//     return Response{ .payload = payload };
// }

test "asdfoiu" {
    if (true) return error.SkipZigTest;

    const allocator = std.heap.page_allocator;

    var client = Client{ .allocator = allocator };

    const uri = try std.Uri.parse("http://httpbin.org/anything");

    const payload =
        \\ {
        \\  "name": "zig-cookbook",
        \\  "author": "John"
        \\ }
    ;

    var buf: [1024]u8 = undefined;
    var req = try client.open(.POST, uri, .{ .server_header_buffer = &buf });
    defer req.deinit();

    req.transfer_encoding = .{ .content_length = payload.len };
    try req.send();
    var wtr = req.writer();
    try wtr.writeAll(payload);
    try req.finish();
    try req.wait();

    try std.testing.expectEqual(req.response.status, .ok);

    {

        // const body = try req.reader().readAllAlloc(allocator, 1024 * 1024 * 4);
        // defer allocator.free(body);

        // var output: [513]u8 = undefined;

        // // req.writer().write()

        // std.debug.print("{s}\n", .{output});
        // std.debug.print("{s}\n", .{body});
        // std.debug.print("{}\n", .{body.len});
    }

    {
        // var outbuf: [515]u8 = undefined;
        var outbuf: [513]u8 = undefined;

        // var body = try req.reader().read(&output);
        // try req.reader().readNoEof(&output);

        // const read_len = try req.reader().readAll(&output);

        const read_len = try req.reader().read(&outbuf);

        const eof = req.reader().readByte();
        std.debug.print("{any}\n", .{eof});

        // std.debug.print("{s}\n", .{output});
        // body = try req.reader().read(&output);
        // body = try req.reader().read(&output);

        std.debug.print("{s}\n", .{outbuf[0..read_len]});
        // std.debug.print("{s}\n", .{res});

        // if (res) |r| {
        //     std.debug.print("{s}\n", .{r});
        // }
    }
}

const DynamicBuffer = struct {
    buffer: []u8,
    pos: usize = 0,

    // fn writeFromReader(self: *@This(), allocator: Allocator, reader: anytype) void {

    // }

};
