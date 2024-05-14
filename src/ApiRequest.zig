const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Client = std.http.Client;
const Headers = std.http.Client.Request.Headers;
const Method = std.http.Method;
const ResponseStorage = std.http.Client.FetchOptions.ResponseStorage;
// const Parsed = std.json.Parsed;

// const CowString = @import("CowString.zig");
const api = @import("api.zig");

// TODO to be more specific
pub const HttpError = error{
    ToBeDefined,
    InvalidStatus,
};

const ApiRequest = @This();

url: []const u8,
method: Method,
user_agent: ?[]const u8 = null,
authorization: ?[]const u8 = null,
// headers: Headers = Headers{},
payload: ?[]const u8 = null,

pub const ApiResponse = struct {
    payload: []const u8,
    allocator: ?Allocator = null,

    pub fn deinit(self: *const ApiResponse) void {
        if (self.allocator) |allocator| {
            allocator.free(self.payload);
        }
        @constCast(self).* = undefined;
    }

    pub fn setOwned(self: *ApiResponse, allocator: Allocator) !void {
        if (self.allocator) |_| @panic("Has already owned");
        self.payload = try allocator.dupe(u8, self.payload);
        self.allocator = allocator;
    }
};

pub const ResponseBuffer = union(enum) {
    dynamic: *std.ArrayList(u8),
    static: []u8,
};

pub fn fetch(self: *const ApiRequest, client: *Client, response_buffer: ResponseBuffer) HttpError!ApiResponse {
    var headers = Headers{};
    if (self.authorization) |authorization| headers.authorization = .{ .override = authorization };
    if (self.user_agent) |user_agent| headers.user_agent = .{ .override = user_agent };

    var fetch_options = std.http.Client.FetchOptions{
        .location = .{ .url = self.url },
        .method = self.method,
        .payload = self.payload,
        .headers = headers,
    };
    const payload = switch (response_buffer) {
        .dynamic => |buffer| blk: {
            fetch_options.response_storage = .{ .dynamic = buffer };
            const result = client.fetch(fetch_options) catch return HttpError.ToBeDefined;
            if (result.status != .ok) {
                return HttpError.InvalidStatus;
            }
            break :blk buffer.items;
        },
        .static => |buf| blk: {
            var fba = std.heap.FixedBufferAllocator.init(buf);
            var buffer = std.ArrayListUnmanaged(u8).initCapacity(fba.allocator(), buf.len) catch unreachable;
            fetch_options.response_storage = .{ .static = &buffer };
            const result = client.fetch(fetch_options) catch return HttpError.ToBeDefined;
            if (result.status != .ok) {
                return HttpError.InvalidStatus;
            }
            break :blk buffer.items;
        },
    };
    return ApiResponse{ .payload = payload };
}
