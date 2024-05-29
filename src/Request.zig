const std = @import("std");
const json = std.json;
const http = std.http;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Client = std.http.Client;
const Headers = std.http.Client.Request.Headers;
const Method = std.http.Method;
const Status = std.http.Status;

const Request = @This();

// TODO to be more specific
// pub const Error = error{
//     ResponseBufferOutOfMemory,
// } || HttpError || Client.RequestError || std.Uri.ParseError || Client.Request.WriteError || Client.Request.WaitError || Client.Request.ReadError || Client.Request.FinishError;

pub const Error = OpenRequestError || SendError || ReadError;

pub const OpenRequestError = Client.RequestError || std.Uri.ParseError;
pub const SendError = Client.Request.SendError || Client.Request.WriteError || Client.Request.FinishError || Client.Request.WaitError || HttpError;
pub const ReadError = error{StreamTooLong} || Client.Request.ReadError || Allocator.Error;

pub const HttpError = error{
    Undefined,
};

pub const Options = struct {
    client: *Client,
    header_buffer: []u8,
    url: []const u8,
    method: Method,
    user_agent: []const u8,
    authorization: ?[]const u8 = null,
    payload: ?[]const u8 = null,
};

request: Client.Request,
payload: ?[]const u8,

pub fn open(options: Options) OpenRequestError!@This() {
    var headers = Headers{};
    if (options.authorization) |authorization| headers.authorization = .{ .override = authorization };
    headers.user_agent = .{ .override = options.user_agent };

    const request_options = Client.RequestOptions{
        .server_header_buffer = options.header_buffer,
        .headers = headers,
    };
    const uri = try std.Uri.parse(options.url);

    var request = try options.client.open(options.method, uri, request_options);
    if (options.payload) |pl| request.transfer_encoding = .{ .content_length = pl.len };

    return @This(){
        .request = request,
        .payload = options.payload,
    };
}

pub fn send(self: *@This()) !void {
    try self.request.send();
    if (self.payload) |pl| try self.request.writer().writeAll(pl);
    try self.request.finish();
    try self.request.wait();
}

pub fn status(self: *const @This()) http.Status {
    return self.request.response.status;
}

pub fn deinit(self: *@This()) void {
    self.request.deinit();
}

pub fn reader(self: *@This()) Client.Request.Reader {
    return self.request.reader();
}

pub fn headerIterators(self: *@This()) http.HeaderIterator {
    return self.request.response.iterateHeaders();
}
