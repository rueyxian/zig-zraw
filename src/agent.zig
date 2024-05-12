const std = @import("std");
const builtin = @import("builtin");
const debug = std.debug;
const mem = std.mem;
const testing = std.testing;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const Headers = std.http.Headers;
const Parsed = std.json.Parsed;
// const ResponseStorage = std.http.Client.FetchOptions.ResponseStorage;

const model = @import("model.zig");

// const AccessToken = @import("endpoint/access_token.zig").AccessToken;
const ApiRequest = @import("ApiRequest.zig");
const ApiResponse = ApiRequest.ApiResponse;
const ResponseBuffer = ApiRequest.ResponseBuffer;

const api = @import("api.zig");

pub const AuthorizationOptions = struct {
    user_agent: []const u8,
    app_id: []const u8,
    app_pass: []const u8,
    user_id: []const u8,
    user_pass: []const u8,
};

pub const Authorization = struct {
    authorization: []const u8,
    default_user_agent: []const u8,

    pub const Self = @This();

    pub fn fetch(allocator: Allocator, options: AuthorizationOptions) !Self {
        var buffer: [1 << 14]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const fballoc = fba.allocator();

        var client = Client{ .allocator = allocator };
        defer client.deinit();

        const response = blk: {
            const basic_auth = bauth: {
                const Base64Encoder = std.base64.standard.Encoder;
                const src = try fmt.allocPrint(fballoc, "{s}:{s}", .{ options.app_id, options.app_pass });
                defer fballoc.free(src);
                const encoded = try fballoc.alloc(u8, Base64Encoder.calcSize(src.len));
                defer fballoc.free(encoded);
                _ = Base64Encoder.encode(encoded, src);
                break :bauth try fmt.allocPrint(fballoc, "Basic {s}", .{encoded});
            };
            defer fballoc.free(basic_auth);

            const payload = try fmt.allocPrint(fballoc, "grant_type=password&username={s}&password={s}", .{ options.user_id, options.user_pass });
            defer fballoc.free(payload);

            // const endpoint = try api.Endpoint.parse(fballoc, AccessToken{});

            const endpoint = try api.getEndpoint(fballoc, api.AccessToken{});
            defer endpoint.deinit(fballoc);

            const request = ApiRequest{
                .uri = endpoint.url.value,
                .method = endpoint.method,
                .user_agent = options.user_agent,
                .authorization = basic_auth,
                .payload = payload,
            };
            // break :blk try request.fetch(&client, .{ .static = &response_buffer });

            var response_buffer = std.ArrayList(u8).init(fballoc);
            break :blk try request.fetch(&client, .{ .dynamic = &response_buffer });
        };
        const parsed = try json.parseFromSlice(api.AccessToken.Model, fballoc, response.payload, .{});
        // const parsed = try model.parse(api.AccessToken.Model, fballoc, response.payload);
        defer parsed.deinit();
        const authorization = try fmt.allocPrint(allocator, "{s} {s}", .{ parsed.value.token_type, parsed.value.access_token });
        return Self{
            .authorization = authorization,
            .default_user_agent = options.user_agent,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.authorization);
    }

    pub fn agent(self: *const Self, allocator: Allocator, optional_user_agent: ?[]const u8, comptime buffer_type: AgentBufferType) Agent(buffer_type) {
        const user_agent = optional_user_agent orelse self.default_user_agent;
        return Agent(buffer_type).init(allocator, user_agent, self.authorization);
    }

    pub fn agent_unmanaged(self: *const Self, allocator: Allocator, optional_user_agent: ?[]const u8, comptime buffer_type: AgentBufferType) AgentUnmanaged(buffer_type) {
        const user_agent = optional_user_agent orelse self.default_user_agent;
        return AgentUnmanaged(buffer_type).init(allocator, user_agent, self.authorization);
    }
};

// pub fn ParsedResult

// TODO static and dynamic options

pub const AgentBufferType = union(enum) {
    dynamic,
    static: usize,
};

pub fn Agent(comptime buffer_type: AgentBufferType) type {
    return struct {
        unmanaged: Unmanaged,
        allocator: Allocator,

        const Self = @This();
        const Unmanaged = AgentUnmanaged(buffer_type);

        pub fn init(allocator: Allocator, user_agent: []const u8, authorization: []const u8) Self {
            return Self{
                .unmanaged = Unmanaged.init(allocator, user_agent, authorization),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.unmanaged.deinit();
        }

        pub fn fetch(self: *Self, endpoint_or_context: anytype) !Parsed(@TypeOf(endpoint_or_context).Model) {
            return self.unmanaged.fetch(self.allocator, endpoint_or_context);
        }

        pub fn fetchBytes(self: *Self, endpoint_or_context: anytype) !ApiResponse {
            return self.unmanaged.fetchBytes(self.allocator, endpoint_or_context);
        }
    };
}

pub fn AgentUnmanaged(comptime buffer_type: AgentBufferType) type {
    return struct {
        user_agent: []const u8,
        authorization: []const u8,
        client: Client,
        buffer: Buffer,

        const Self = @This();

        const Buffer = switch (buffer_type) {
            .dynamic => struct {
                inner_buf: std.ArrayList(u8),
                fn init(allocator: Allocator) @This() {
                    return @This(){ .inner_buf = std.ArrayList(u8).init(allocator) };
                }
                fn deinit(self: @This()) void {
                    self.inner_buf.deinit();
                }
                fn responseBuffer(self: *@This()) ResponseBuffer {
                    self.inner_buf.clearRetainingCapacity();
                    return .{ .dynamic = &self.inner_buf };
                }
            },
            .static => |len| struct {
                inner_buf: [len]u8 = undefined,
                fn init(_: Allocator) @This() {
                    return @This(){};
                }
                fn deinit(_: @This()) void {}
                fn responseBuffer(self: *@This()) ResponseBuffer {
                    return .{ .static = &self.inner_buf };
                }
            },
        };

        pub fn init(allocator: Allocator, user_agent: []const u8, authorization: []const u8) Self {
            const client = Client{ .allocator = allocator };
            const buffer = Buffer.init(allocator);
            return Self{
                .user_agent = user_agent,
                .authorization = authorization,
                .client = client,
                .buffer = buffer,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
            self.client.deinit();
        }

        pub fn fetch(self: *Self, allocator: Allocator, endpoint_or_context: anytype) !Parsed(@TypeOf(endpoint_or_context).Model) {
            const T = @TypeOf(endpoint_or_context);
            api.verifyEndpointOrContext(T);
            if (api.isEndpoint(T)) {
                return self.fetchWithEndpoint(allocator, endpoint_or_context);
            } else if (api.isContext(T)) {
                return self.fetchWithContext(allocator, endpoint_or_context);
            } else {}
            unreachable;
            // @panic("Invalid endpoint type or endpoint context type");
        }

        pub fn fetchBytes(self: *Self, allocator: Allocator, endpoint_or_context: anytype) !ApiResponse {
            const T = @TypeOf(endpoint_or_context);
            api.verifyEndpointOrContext(T);
            if (api.isEndpoint(T)) {
                return self.fetchBytesWithEndpoint(endpoint_or_context);
            } else if (api.isContext(T)) {
                return self.fetchBytesWithContext(allocator, endpoint_or_context);
            } else {}
            unreachable;
            // @panic("Invalid endpoint type or endpoint context type");
        }

        pub fn fetchWithEndpoint(self: *Self, allocator: Allocator, endpoint: anytype) !Parsed(@TypeOf(endpoint).Model) {
            api.verifyEndpoint(@TypeOf(endpoint));
            const response = try self.fetchBytesWithEndpoint(endpoint);
            defer response.deinit();
            // return model.parse(@TypeOf(endpoint).Model, allocator, response.payload);
            return json.parseFromSlice(@TypeOf(endpoint).Model, allocator, response.payload, .{
                .ignore_unknown_fields = true,
            });
        }

        pub fn fetchBytesWithEndpoint(self: *Self, endpoint: anytype) !ApiResponse {
            api.verifyEndpoint(@TypeOf(endpoint));
            const options = api.FetchOptions{
                .client = &self.client,
                .response_buffer = self.buffer.responseBuffer(),
                // .response_buffer = self.inner_buffer.responseStorage(),
                // .response_storage = self.buffer.responseBuffer(),
                .user_agent = self.user_agent,
                .authorization = self.authorization,
                .payload = null,
            };
            return endpoint.fetchAdaptor(undefined, options);
        }

        pub fn fetchWithContext(self: *Self, allocator: Allocator, context: anytype) !Parsed(@TypeOf(context).Model) {
            api.verifyContext(@TypeOf(context));
            const response = try self.fetchBytesWithContext(allocator, context);
            defer response.deinit();
            return json.parseFromSlice(@TypeOf(context).Model, allocator, response.payload, .{
                .ignore_unknown_fields = true,
            });
        }

        pub fn fetchBytesWithContext(self: *Self, allocator: Allocator, context: anytype) !ApiResponse {
            api.verifyContext(@TypeOf(context));
            const options = api.FetchOptions{
                .client = &self.client,
                .response_buffer = self.buffer.responseBuffer(),
                // .response_storage = self.buffer.responseBuffer(),
                .user_agent = self.user_agent,
                .authorization = self.authorization,
                .payload = null,
            };
            return context.fetchAdaptor(allocator, options);
        }
    };
}

const print = std.debug.print;

const testOptions = @import("util.zig").testOptions;
const TestOptions = @import("util.zig").TestOptions;
// const parser = @import("parser.zig");

test "xoiuer" {
    if (true) return error.SkipZigTest;
    const allocator = std.heap.page_allocator;

    // verifyEndpoint();
    const Context = api.ListingNew("zig");

    // const Context = api.ListingNew("dota2");

    // const parsed = try agent.fetchModelWithContext(Context, allocator, Context{
    //     .count = 3,
    // });
    // defer parsed.deinit();

    // const endpoint = api.Endpoint.parsed(Context{
    //     .count = 3,
    // });

    const endpoint = try api.getEndpoint(allocator, Context{
        .count = 3,
    });
    defer endpoint.deinit(allocator);

    const T = @TypeOf(endpoint);

    print("{any}\n", .{api.isEndpoint(T)});

    const Model = T.Model;

    const info = @typeInfo(Model);
    _ = info; // autofix

    // @compileLog(info);

    // debug.assert(info == .Struct);

    // print("{any}\n", .{info == .Struct});
}

test "auth" {
    // if (true) return error.SkipZigTest;

    const testopts: TestOptions = testOptions() orelse return error.SkipZigTest;

    // const allocator = std.testing.allocator;
    const allocator = std.heap.page_allocator;

    const user_agent = testopts.user_agent;

    // var client = Client{ .allocator = allocator };
    // defer client.deinit();

    var auth = try Authorization.fetch(allocator, .{
        .user_agent = user_agent,
        .app_id = testopts.app_id,
        .app_pass = testopts.app_pass,
        .user_id = testopts.user_id,
        .user_pass = testopts.user_pass,
    });
    defer auth.deinit(allocator);

    // const config = AgentBufferType{
    //     .buffer_type = .dynamic,
    //     // .buffer_type = .{ .static = 1024 * 1024 * 4 },
    // };

    // var agent = auth.agent(allocator, null, .dynamic);
    // const buffer_type: AgentBufferType ;
    // var agent = auth.agent_unmanaged(allocator, null, .{ .static = 1024 * 1024 });
    // var agent = auth.agent(allocator, null, .{ .static = 1024 * 1024 });
    var agent = auth.agent(allocator, null, .dynamic);
    defer agent.deinit();

    {
        {
            // const Context = api.ListingNew("zig");
            // const endpoint = try api.getEndpoint(allocator, Context{
            //     .count = 3,
            // });
            // defer endpoint.deinit(allocator);

            // const response = try agent.fetchBytes(allocator, endpoint);
            // defer response.deinit();
            // // print("{s}\n", .{response.payload});
        }

        {
            // const Context = api.ListingNew("zig");
            // const response = try agent.fetchBytes(allocator, Context{
            //     .count = 3,
            // });
            // defer response.deinit();
            // const parsed = try model.parse(Thing, allocator, response.payload);
            // defer parsed.deinit();
        }

        {
            // const Context = api.ListingNew("zig");
            // const parsed = try agent.fetchWithContext(allocator, Context{
            //     .count = 3,
            // });
            // defer parsed.deinit();
            // print("{any}\n", .{parsed.value});
        }

        {
            // const Context = api.ListingNew("zig");
            // const endpoint = try api.getEndpoint(allocator, Context{
            //     .count = 3,
            // });
            // const parsed = try agent.fetchWithEndpoint(allocator, endpoint);
            // defer parsed.deinit();

            // print("{any}\n", .{parsed.value});
        }

        {
            const Context = api.ListingNew("zig");
            const parsed = try agent.fetch(Context{
                .count = 3,
            });
            defer parsed.deinit();

            print("{any}\n", .{parsed.value});
        }
    }
}

const json = std.json;

const Thing = model.Thing;
const Listing = model.Listing;
const Link = model.Link;
const Comment = model.Comment;

test "test json" {
    if (true) return error.SkipZigTest;

    print("\n", .{});
    const allocator = std.heap.page_allocator;

    const s = @embedFile("testjson/listing_new.json");

    const Value = std.json.Value;
    const parsed = try json.parseFromSlice(Value, allocator, s, .{
        .ignore_unknown_fields = true,
    });

    const root = parsed.value;

    const kind = root.object.get("kind").?.string;
    print("kind: {s}\n", .{kind});

    const data = root.object.get("data").?.object;
    print("data: {any}\n", .{data});

    print("type: {}", .{@TypeOf(data)});

    // const
    // var scanner = JsonScanner.initCompleteInput(testing.allocator, "123");

    // const selftext = root.object.get("selftext").?;
}

test "test json static" {
    if (true) return error.SkipZigTest;

    print("\n", .{});
    const allocator = std.heap.page_allocator;

    const s = @embedFile("testjson/listing_new.json");

    const parsed = try json.parseFromSlice(Thing(Listing), allocator, s, .{
        .ignore_unknown_fields = true,
    });
    // print("{any}\n", .{parsed.value});

    const listing = parsed.value;

    const children = listing.data.children;

    const c0 = children[0].data;
    _ = c0; // autofix

    // print("{s}\n", .{c0.url});
    // print("{s}\n", .{c0.url.?});
    // print("{s}\n", .{c0.author.?});
    // print("{s}\n", .{c0.selftext.?});

    // const
    // var scanner = JsonScanner.initCompleteInput(testing.allocator, "123");

    // const selftext = root.object.get("selftext").?;
}

test "test json static comment" {
    if (true) return error.SkipZigTest;

    print("\n", .{});
    const allocator = std.heap.page_allocator;

    const s = @embedFile("testjson/comments2.json");

    // const Model = struct {
    //     Thing(Listing),
    //     Thing(Comment),
    // };

    const Model = [2]Thing;

    const parsed = try json.parseFromSlice(Model, allocator, s, .{
        .ignore_unknown_fields = true,
    });
    // print("{any}\n", .{parsed.value});

    const comments = parsed.value;
    _ = comments; // autofix

    // const children = listing.data.children;

    // const c0 = children[0].data;

    // print("{s}\n", .{c0.url});
    // print("{s}\n", .{c0.url.?});
    // print("{s}\n", .{c0.author.?});
    // print("{s}\n", .{c0.selftext.?});

    // const
    // var scanner = JsonScanner.initCompleteInput(testing.allocator, "123");

    // const selftext = root.object.get("selftext").?;
}

fn testparse(comptime T: type, allocator: Allocator, s: []const u8) !T {
    //
    // json.parseFromTokenSource(, , , )
    const parsed = try json.parseFromSlice(T, allocator, s, .{
        .ignore_unknown_fields = true,
    });
    _ = parsed; // autofix
}
