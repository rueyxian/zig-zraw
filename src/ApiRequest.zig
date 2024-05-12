const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Client = std.http.Client;
const Method = std.http.Method;
const ResponseStorage = std.http.Client.FetchOptions.ResponseStorage;
const Parsed = std.json.Parsed;

// TODO to be more specific
pub const HttpError = error{
    ToBeDefined,
    InvalidStatus,
};

const ApiRequest = @This();

uri: []const u8,
method: Method,
user_agent: []const u8,
authorization: []const u8,
payload: ?[]const u8,

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

pub fn fetch(request: *const ApiRequest, client: *Client, response_buffer: ResponseBuffer) HttpError!ApiResponse {
    const headers = std.http.Client.Request.Headers{
        .authorization = .{ .override = request.authorization },
        .user_agent = .{ .override = request.user_agent },
    };
    var fetch_options = std.http.Client.FetchOptions{
        .location = .{ .url = request.uri },
        .method = request.method,
        .payload = request.payload,
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

// pub fn fetch(request: *const ApiRequest, client: *Client, response_storage: ResponseStorage) HttpError!ApiResponse {
//     const headers = std.http.Client.Request.Headers{
//         .authorization = .{ .override = request.authorization },
//         .user_agent = .{ .override = request.user_agent },
//     };
//     const fetch_options = std.http.Client.FetchOptions{
//         .location = .{ .url = request.uri },
//         .method = request.method,
//         .payload = request.payload,
//         .headers = headers,
//         .response_storage = response_storage,
//     };
//     const result = client.fetch(fetch_options) catch return HttpError.ToBeDefined;
//     if (result.status != .ok) {
//         return HttpError.InvalidStatus;
//     }
//     const payload = switch (response_storage) {
//         inline .static, .dynamic => |buffer| buffer.items,
//         else => unreachable,
//     };

//     // const payload = switch (response_buffer) {
//     //     .dynamic => |buffer| blk: {
//     //         fetch_options.response_storage = .{ .dynamic = buffer };
//     //         const result = client.fetch(fetch_options) catch return HttpError.ToBeDefined;
//     //         if (result.status != .ok) {
//     //             return HttpError.InvalidStatus;
//     //         }
//     //         break :blk buffer.items;
//     //     },
//     //     .static => |buf| blk: {
//     //         var fba = std.heap.FixedBufferAllocator.init(buf);
//     //         var buffer = std.ArrayListUnmanaged(u8).initCapacity(fba.allocator(), buf.len) catch unreachable;
//     //         fetch_options.response_storage = .{ .static = &buffer };
//     //         const result = client.fetch(fetch_options) catch return HttpError.ToBeDefined;
//     //         if (result.status != .ok) {
//     //             return HttpError.InvalidStatus;
//     //         }
//     //         break :blk buffer.items;
//     //     },
//     // };
//     return ApiResponse{ .payload = payload };
// }
