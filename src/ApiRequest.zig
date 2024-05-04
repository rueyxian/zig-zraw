const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Client = std.http.Client;
const Method = std.http.Method;
const ResponseStorage = std.http.Client.FetchOptions.ResponseStorage;
const Parsed = std.json.Parsed;

pub const Error = error{
    HttpResponse,
};

const ApiRequest = @This();

uri: []const u8,
method: Method,
user_agent: []const u8,
authorization: []const u8,
payload: ?[]const u8,

pub const ApiResponse = struct {
    payload: []const u8,
    owned: bool,

    pub const ParseError = std.json.ParseError(json.Scanner);

    // pub const parseFn = fn (type, Allocator, []const u8) ParseError!Parsed()

    pub fn deinit(self: *const ApiResponse, allocator: Allocator) void {
        if (self.owned == false) {
            return;
        }
        allocator.free(self.payload);
    }

    pub fn setOwned(self: *ApiResponse, allocator: Allocator) !void {
        self.payload = try allocator.dupe(u8, self.payload);
        self.owned = true;
    }

    // pub fn ParseFn(comptime T: type) ParseError!Parsed(T) {
    //     return fn (type, Allocator, []const u8) ParseError!Parsed(T);
    // }

    // pub fn parse(self: *const ApiResponse, comptime T: type, allocator: Allocator, optional_parse_fn: ?ParseFn(T)) ParseError!Parsed(T) {
    //     if (optional_parse_fn) |parse_fn| {
    //         return try parse_fn(T, allocator, self.payload);
    //     }
    //     return try json.parseFromSlice(T, allocator, self.payload, .{
    //         .ignore_unknown_fields = true,
    //     });
    // }

    pub fn parse(self: *const ApiResponse, comptime T: type, allocator: Allocator) ParseError!Parsed(T) {
        const _parse = @import("parser.zig").parse;
        return _parse(T, allocator, self.payload);
        // if (optional_parse_fn) |parse_fn| {
        //     return try parse_fn(T, allocator, self.payload);
        // }
        // return try json.parseFromSlice(T, allocator, self.payload, .{
        //     .ignore_unknown_fields = true,
        // });
    }
};

pub const ResponseBuffer = union(enum) {
    dynamic: *std.ArrayList(u8),
    static: []u8,
};

pub fn fetch(request: *const ApiRequest, client: *Client, response_buffer: ResponseBuffer) !ApiResponse {
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
            const result = try client.fetch(fetch_options);
            if (result.status != .ok) {
                return Error.HttpResponse;
            }
            break :blk buffer.items;
        },
        .static => |buf| blk: {
            var fba = std.heap.FixedBufferAllocator.init(buf);
            var buffer = std.ArrayListUnmanaged(u8).initCapacity(fba.allocator(), buf.len) catch unreachable;
            fetch_options.response_storage = .{ .static = &buffer };
            const result = try client.fetch(fetch_options);
            if (result.status != .ok) {
                return Error.HttpResponse;
            }
            break :blk buffer.items;
        },
    };
    return ApiResponse{
        .payload = payload,
        .owned = false,
    };
}
