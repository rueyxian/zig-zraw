const std = @import("std");
const builtin = @import("builtin");
const debug = std.debug;
const mem = std.mem;
const testing = std.testing;
const fmt = std.fmt;
const math = std.math;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const Headers = std.http.Headers;
const Parsed = std.json.Parsed;

const model = @import("model.zig");

const ApiRequest = @import("ApiRequest.zig");
const ApiResponse = ApiRequest.ApiResponse;
const ResponseBuffer = ApiRequest.ResponseBuffer;

const api = @import("api.zig");

pub const AppConfig = struct {
    thread_safe: bool = !builtin.single_threaded,
    MutexType: ?type = null,
    app_info_alloc_options: AllocOptions = .alloc_dynamic,
    access_type_alloc_options: AllocOptions = .alloc_dynamic,
    user_agent_alloc_options: UserAgentAllocOptions = .{ .alloc_static_if_auto = 128 },
    token_alloc_options: TokenAllocOptions = .{ .alloc_static = 1556 },

    pub const AllocOptions = union(enum) {
        never,
        alloc_static: usize,
        alloc_dynamic,
    };
    pub const UserAgentAllocOptions = union(enum) {
        never,
        alloc_static_if_auto: usize,
        alloc_dynamic_if_auto,
        alloc_static: usize,
        alloc_dynamic,
    };
    pub const TokenAllocOptions = union(enum) {
        alloc_static: usize,
        alloc_dynamic,
    };
};

pub fn App(comptime config: AppConfig) type {
    return struct {
        allocator: Allocator,
        unmanaged: Unmanaged = Unmanaged{},

        pub const Self = @This();
        pub const Unmanaged = AppUnmanaged(config);

        pub const AuthorizeOptions = Unmanaged.AuthorizeOptions;

        pub fn deinit(self: *Self) void {
            self.unmanaged.deinit(self.allocator);
        }

        pub fn initAuthorize(allocator: Allocator, options: AuthorizeOptions) !Self {
            var self = Self{ .allocator = allocator };
            try self.authorize(options);
            return self;
        }

        pub fn authorize(self: *Self, options: AuthorizeOptions) !void {
            try self.unmanaged.authorize(self.allocator, options);
        }

        pub fn refreshToken(self: *Self) !void {
            try self.unmanaged.refreshToken(self.allocator);
        }

        pub fn agent(self: *Self, comptime buffer_type: AgentBufferType) Agent(Self, buffer_type) {
            return self.unmanaged.agent(self.allocator, buffer_type);
        }
    };
}

pub fn AppUnmanaged(comptime config: AppConfig) type {
    return struct {
        app_id: []const u8 = undefined,
        app_pass: []const u8 = undefined,
        access_type: AccessType = undefined,
        user_agent: []const u8 = undefined,
        auto_refresh_token: bool = undefined,
        authorized_once: bool = false,
        token: ?Token = null,

        app_info_buffer: AppInfoBuffer = .{},
        access_type_buffer: AccessTypeBuffer = .{},
        user_agent_buffer: UserAgentBuffer = .{},
        token_buffer: TokenBuffer = .{},
        mutex: Mutex = .{},

        pub const Self = @This();

        const Mutex = if (config.MutexType) |T|
            T
        else if (config.thread_safe)
            std.Thread.Mutex
        else
            struct {
                fn lock(_: *@This()) void {}
                fn unlock(_: *@This()) void {}
            };

        const Token = struct {
            expires_at: u64,
            access_token: []const u8,
            token_type: []const u8,
            scope: []const u8,
            authorization: []const u8,
        };

        pub const AccessType = union(enum) {
            userless: struct {
                device_id: []const u8 = "DO_NOT_TRACK_THIS_DEVICE",
            },
            user: struct {
                user_id: []const u8,
                user_pass: []const u8,
            },
        };

        const AppInfoBuffer = switch (config.app_info_alloc_options) {
            .never => DummyBuffer,
            .alloc_static => |size| StaticBuffer(size),
            .alloc_dynamic => DynamicBuffer,
        };

        const AccessTypeBuffer = switch (config.access_type_alloc_options) {
            .never => DummyBuffer,
            .alloc_static => |size| StaticBuffer(size),
            .alloc_dynamic => DynamicBuffer,
        };

        const UserAgentBuffer = switch (config.user_agent_alloc_options) {
            .never => DummyBuffer,
            inline .alloc_static_if_auto, .alloc_static => |size| StaticBuffer(size),
            inline .alloc_dynamic_if_auto, .alloc_dynamic => DynamicBuffer,
        };

        const TokenBuffer = switch (config.token_alloc_options) {
            .alloc_static => |size| StaticBuffer(size),
            .alloc_dynamic => DynamicBuffer,
        };

        const DummyBuffer = struct {
            fn ensureTotalCapacity(_: *@This(), _: Allocator, _: usize) Allocator.Error!void {}
            fn allocAssumeCapacity(_: *@This(), source: []const u8) []u8 {
                return source;
            }
            fn alloc(_: *@This(), _: Allocator, source: []const u8) Allocator.Error![]u8 {
                return source;
            }
            fn allocPrintAssumeCapacity(_: *@This(), comptime _: []const u8, _: anytype) []u8 {
                unreachable;
            }
            fn allocPrint(_: *@This(), _: Allocator, comptime _: []const u8, _: anytype) Allocator.Error![]u8 {
                unreachable;
            }
            fn reset(_: *@This()) void {}
            fn deinit(_: *@This(), _: Allocator) void {}
        };

        fn StaticBuffer(comptime size: usize) type {
            return struct {
                buffer: [size]u8 = undefined,
                pos: usize = 0,
                fn ensureTotalCapacity(self: *@This(), _: Allocator, n: usize) Allocator.Error!void {
                    if (n <= self.buffer.len) return;
                    return Allocator.Error.OutOfMemory;
                }
                fn allocAssumeCapacity(self: *@This(), source: []const u8) []u8 {
                    defer self.pos += source.len;
                    const target = self.buffer[self.pos..][0..source.len];
                    @memcpy(target, source);
                    return target;
                }
                fn alloc(self: *@This(), _: Allocator, source: []const u8) Allocator.Error![]u8 {
                    self.ensureTotalCapacity(undefined, self.pos.source.len);
                    return self.allocAssumeCapacity(source);
                }
                fn allocPrintAssumeCapacity(self: *@This(), comptime format: []const u8, args: anytype) []u8 {
                    const buf = self.buffer[self.pos..];
                    const res = fmt.bufPrint(buf, format, args) catch @panic("out of memory");
                    defer self.pos += res.len;
                    return res;
                }
                fn allocPrint(self: *@This(), _: Allocator, comptime format: []const u8, args: anytype) Allocator.Error![]u8 {
                    const source_len = math.cast(usize, fmt.count(format, args)) orelse return Allocator.Error.OutOfMemory;
                    try self.ensureTotalCapacity(undefined, source_len);
                    return self.allocPrintAssumeCapacity(format, args);
                }
                fn reset(self: *@This()) void {
                    self.pos = 0;
                }
                fn deinit(_: *@This(), _: Allocator) void {}
            };
        }

        const DynamicBuffer = struct {
            buffer: []u8 = undefined,
            pos: usize = 0,
            fn ensureTotalCapacity(self: *@This(), allocator: Allocator, n: usize) Allocator.Error!void {
                if (n <= self.buffer.len) return;
                self.buffer = try allocator.realloc(self.buffer, n);
            }
            fn allocAssumeCapacity(self: *@This(), source: []const u8) []u8 {
                defer self.pos += source.len;
                const target = self.buffer[self.pos..][0..source.len];
                @memcpy(target, source);
                return target;
            }
            fn alloc(self: *@This(), allocator: Allocator, source: []const u8) Allocator.Error![]u8 {
                try self.ensureTotalCapacity(allocator, self.pos + source.len);
                return self.allocAssumeCapacity(source);
            }
            fn allocPrintAssumeCapacity(self: *@This(), comptime format: []const u8, args: anytype) []u8 {
                const buf = self.buffer[self.pos..];
                const res = fmt.bufPrint(buf, format, args) catch @panic("out of memory");
                defer self.pos += res.len;
                return res;
            }
            fn allocPrint(self: *@This(), allocator: Allocator, comptime format: []const u8, args: anytype) Allocator.Error![]u8 {
                const source_len = math.cast(usize, fmt.count(format, args)) orelse return Allocator.Error.OutOfMemory;
                try self.ensureTotalCapacity(allocator, self.pos + source_len);
                return self.allocPrintAssumeCapacity(format, args);
            }
            fn reset(self: *@This()) void {
                self.pos = 0;
            }
            fn deinit(self: *@This(), allocator: Allocator) void {
                allocator.free(self.buffer);
            }
        };

        pub const TokenExpiration = union(enum) {
            unauthorized,
            expires_in: u64,
            expired,
        };

        pub fn tokenExpiration(self: *const @This()) TokenExpiration {
            const token = self.token orelse return TokenExpiration.unauthorized;
            const expires_in = std.time.Instant.now() -| token.expires_at;
            if (expires_in == 0) return TokenExpiration.expired;
            return TokenExpiration{ .expires_in = expires_in };
        }

        pub const AuthorizeOptions = struct {
            app_id: []const u8,
            app_pass: []const u8,
            access_type: AccessType = .{ .userless = .{} },
            user_agent: ?[]const u8 = null,
            auto_refresh_token: bool = true,
        };

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.app_info_buffer.deinit(allocator);
            self.access_type_buffer.deinit(allocator);
            self.user_agent_buffer.deinit(allocator);
            self.token_buffer.deinit(allocator);
        }

        pub fn initAuthorize(allocator: Allocator, options: AuthorizeOptions) !Self {
            var self = Self{};
            try self.authorize(allocator, options);
            return Self;
        }

        pub fn authorize(self: *Self, allocator: Allocator, options: AuthorizeOptions) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.token = null;

            self.app_info_buffer.reset();
            try self.app_info_buffer.ensureTotalCapacity(allocator, options.app_id.len + options.app_pass.len);
            self.app_id = self.app_info_buffer.allocAssumeCapacity(options.app_id);
            self.app_pass = self.app_info_buffer.allocAssumeCapacity(options.app_pass);

            self.access_type_buffer.reset();
            switch (options.access_type) {
                .userless => |x| {
                    const device_id = try self.access_type_buffer.alloc(allocator, x.device_id);
                    self.access_type = .{ .userless = .{ .device_id = device_id } };
                },
                .user => |x| {
                    try self.access_type_buffer.ensureTotalCapacity(allocator, x.user_id.len + x.user_pass.len);
                    const user_id = self.access_type_buffer.allocAssumeCapacity(x.user_id);
                    const user_pass = self.access_type_buffer.allocAssumeCapacity(x.user_pass);
                    self.access_type = .{ .user = .{ .user_id = user_id, .user_pass = user_pass } };
                },
            }

            self.user_agent_buffer.reset();
            self.user_agent = blk: {
                if (options.user_agent) |user_options| {
                    break :blk switch (config.user_agent_alloc_options) {
                        inline .never, .alloc_static, .alloc_dynamic => self.user_agent_buffer.alloc(user_options),
                        inline .alloc_static_if_auto, .alloc_dynamic_if_auto => user_options,
                    };
                }
                switch (config.user_agent_alloc_options) {
                    .never => @panic("Providing user agent is required"),
                    else => {
                        const platform = @tagName(@import("builtin").os.tag);
                        const version = "v0.0.0";
                        break :blk switch (options.access_type) {
                            .userless => try self.user_agent_buffer.allocPrint(allocator, "{s}:zraw:{s} (user-less)", .{ platform, version }),
                            .user => |x| try self.user_agent_buffer.allocPrint(allocator, "{s}:zraw:{s} (by /u/{s})", .{ platform, version, x.user_id }),
                        };
                    },
                }
                unreachable;
            };

            self.auto_refresh_token = options.auto_refresh_token;
            try self._authorize(allocator);
        }

        pub fn refreshToken(self: *Self, allocator: Allocator) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (!self.authorized_once) {
                @panic("Cannot refresh token without being authorized once.");
            }
            try self._authorize(allocator);
        }

        fn _authorize(self: *Self, allocator: Allocator) !void {
            self.token_buffer.reset();

            var buffer: [1 << 14]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buffer);
            const fballoc = fba.allocator();

            var client = Client{ .allocator = allocator };
            defer client.deinit();

            const response = blk: {
                const basic_auth = bauth: {
                    const Base64Encoder = std.base64.standard.Encoder;
                    const src = try fmt.allocPrint(fballoc, "{s}:{s}", .{ self.app_id, self.app_pass });
                    defer fballoc.free(src);
                    const encoded = try fballoc.alloc(u8, Base64Encoder.calcSize(src.len));
                    defer fballoc.free(encoded);
                    _ = Base64Encoder.encode(encoded, src);
                    break :bauth try fmt.allocPrint(fballoc, "Basic {s}", .{encoded});
                };
                defer fballoc.free(basic_auth);

                const payload = switch (self.access_type) {
                    .userless => |ty| try fmt.allocPrint(fballoc, "grant_type=client_credentials&device_id={s}", .{ty.device_id}),
                    .user => |ty| try fmt.allocPrint(fballoc, "grant_type=password&username={s}&password={s}", .{ ty.user_id, ty.user_pass }),
                };
                defer fballoc.free(payload);

                var response_buffer = std.ArrayList(u8).init(fballoc);
                const fetch_options = api.ContextFetchOptions{
                    .client = &client,
                    .response_buffer = .{ .dynamic = &response_buffer },
                    .user_agent = self.user_agent,
                    .authorization = basic_auth,
                    .payload = payload,
                };

                break :blk try (api.AccessToken{}).fetch(allocator, fetch_options);
            };
            const parsed = try json.parseFromSlice(api.AccessToken.Model, fballoc, response.payload, .{});
            defer parsed.deinit();

            try self.token_buffer.ensureTotalCapacity(allocator, ((parsed.value.access_token.len + parsed.value.token_type.len) * 2) + parsed.value.scope.len + 1);
            const access_token = self.token_buffer.allocAssumeCapacity(parsed.value.access_token);
            const token_type = self.token_buffer.allocAssumeCapacity(parsed.value.token_type);
            const scope = self.token_buffer.allocAssumeCapacity(parsed.value.scope);
            const authorization = self.token_buffer.allocPrintAssumeCapacity("{s} {s}", .{ parsed.value.token_type, parsed.value.access_token });

            self.token = Token{
                .expires_at = @as(u64, @intCast(std.time.timestamp())) + parsed.value.expires_in,
                .access_token = access_token,
                .token_type = token_type,
                .scope = scope,
                .authorization = authorization,
            };

            self.authorized_once = true;
        }

        pub fn agent(self: *Self, allocator: Allocator, comptime buffer_type: AgentBufferType) Agent(Self, buffer_type) {
            return Agent(Self, buffer_type).init(allocator, self);
        }

        pub fn agent_unmanaged(self: *Self, allocator: Allocator, comptime buffer_type: AgentBufferType) AgentUnmanaged(Self, buffer_type) {
            return AgentUnmanaged(Self, buffer_type).init(allocator, &self);
        }
    };
}

pub const AgentBufferType = union(enum) {
    static: usize,
    dynamic,
};

pub fn Agent(comptime AppType: type, comptime buffer_type: AgentBufferType) type {
    return struct {
        unmanaged: Unmanaged,
        allocator: Allocator,

        const Self = @This();
        const Unmanaged = AgentUnmanaged(AppType, buffer_type);

        pub fn init(allocator: Allocator, app: *AppType) Self {
            return Self{
                .unmanaged = Unmanaged.init(allocator, app),
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

pub fn AgentUnmanaged(comptime AppType: type, comptime buffer_type: AgentBufferType) type {
    return struct {
        app: *AppType,
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

        pub fn init(allocator: Allocator, app: *AppType) Self {
            const client = Client{ .allocator = allocator };
            const buffer = Buffer.init(allocator);
            return Self{
                .app = app,
                .client = client,
                .buffer = buffer,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
            self.client.deinit();
        }

        pub fn fetch(self: *Self, allocator: Allocator, context: anytype) !Parsed(@TypeOf(context).Model) {
            api.verifyContext(@TypeOf(context));
            const response = try self.fetchBytes(allocator, context);
            defer response.deinit();
            return json.parseFromSlice(@TypeOf(context).Model, allocator, response.payload, .{
                .ignore_unknown_fields = true,
            });
        }

        pub fn fetchBytes(self: *Self, allocator: Allocator, context: anytype) !ApiResponse {
            api.verifyContext(@TypeOf(context));
            const authorization = (self.app.token orelse return error.NotAuthorized).authorization;
            const options = api.ContextFetchOptions{
                .client = &self.client,
                .response_buffer = self.buffer.responseBuffer(),
                .user_agent = self.app.user_agent,
                .authorization = authorization,
                .payload = null,
            };
            return context.fetch(allocator, options);
        }
    };
}

const print = std.debug.print;

const testOptions = @import("util.zig").testOptions;
const TestOptions = @import("util.zig").TestOptions;
// const parser = @import("parser.zig");

fn AppBuffer() type {
    return struct {
        buffer: []u8 = undefined,
        backing_allocator: Allocator,
    };
}

test "xoiuer" {
    if (true) return error.SkipZigTest;
    print("\n", .{});

    const allocator = std.heap.page_allocator;
    _ = allocator; // autofix

    var buf: [12]u8 = undefined;

    const res = try fmt.bufPrint(&buf, "hello {s}", .{"kitty"});

    print("{c}\n", .{buf});
    print("{any}\n", .{res.len});
    print("{s}\n", .{res});

    // ===============

}

test "auth" {
    // if (true) return error.SkipZigTest;

    const testopts: TestOptions = testOptions() orelse return error.SkipZigTest;

    // const allocator = std.testing.allocator;
    const allocator = std.heap.page_allocator;

    const app_config = AppConfig{
        //
    };

    // var app = App(app_config){
    //     .allocator = allocator,
    // };

    // try app.authorize(.{
    //     .app_id = testopts.app_id,
    //     .app_pass = testopts.app_pass,
    //     .access_type = .{ .user = .{ .user_id = testopts.user_id, .user_pass = testopts.user_pass } },
    //     .user_agent = null,
    //     .auto_refresh_token = true,
    // });

    // ======================

    var app = try App(app_config).initAuthorize(allocator, .{
        .app_id = testopts.app_id,
        .app_pass = testopts.app_pass,
        .access_type = .{ .user = .{ .user_id = testopts.user_id, .user_pass = testopts.user_pass } },
        .user_agent = null,
        .auto_refresh_token = true,
    });
    defer app.deinit();

    print("user-agent: {s}\n", .{app.unmanaged.user_agent});

    // defer app.deinit(allocator);

    // const config = AgentBufferType{
    //     .buffer_type = .dynamic,
    //     // .buffer_type = .{ .static = 1024 * 1024 * 4 },
    // };

    // var agent = auth.agent(allocator, null, .{ .static = 1024 * 1024 });
    // var agent = app.agent(allocator, .dynamic);
    // defer agent.deinit();

    {
        {
            // const Context = api.ListingNew("zig");
            // const parsed = try agent.fetch(Context{
            //     .limit = 9,
            //     .sr_detail = true,
            // });
            // parsed.deinit();

            // // const response = try agent.fetchBytes(allocator, endpoint);
            // // defer response.deinit();
            // print("{any}\n", .{parsed.value});
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
