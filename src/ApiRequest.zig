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

    pub fn parse(self: *const ApiResponse, comptime Model: type, allocator: Allocator) !Parsed(Model) {
        // const parsed = try json.parseFromSlice(PayloadType, allocator, self.body, .{});
        // defer parsed.deinit();
        // var response: PayloadType = undefined;
        // const info = @typeInfo(PayloadType);
        // const fields = info.Struct.fields;
        // inline for (fields) |field| {
        //     @field(&response, field.name) = switch (field.type) {
        //         []const u8 => try allocator.dupe(u8, @field(parsed.value, field.name)),
        //         Number => @field(parsed.value, field.name),
        //         else => unreachable,
        //     };
        // }
        // return response;

        return try json.parseFromSlice(Model, allocator, self.payload, .{});
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
