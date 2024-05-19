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

const Request = @import("Request.zig");
const Response = Request.Response;
const ResponseBuffer = Request.ResponseBuffer;

const api = @import("api.zig");

pub const Error = AppError || api.Error || std.json.ParseError(std.json.Scanner);

pub const AppError = error{
    // NoToken,
    TokenExpired,
};

pub const AppConfig = struct {
    thread_safe: bool = !builtin.single_threaded,
    MutexType: ?type = null,

    alloc_app_id: bool = true,
    alloc_app_pass: bool = true,
    alloc_access_type: bool = true,
    alloc_user_agent: UserAgentAllocOptions = .true,

    pub const UserAgentAllocOptions = union(enum) {
        false,
        true,
        if_auto,
    };
};

pub const InitOptions = struct {
    app_id: []const u8,
    app_pass: []const u8,
    access_type: AccessType = .{ .userless = .{} },
    user_agent: ?[]const u8 = null,
    auto_refresh_token: bool = true,
};

pub const AccessType = union(enum) {
    userless: struct {
        device_id: ?[]const u8 = null,
    },
    user: struct {
        user_id: []const u8,
        user_pass: []const u8,
    },
};

pub fn App(comptime config: AppConfig) type {
    return struct {
        allocator: Allocator,
        app_id: []const u8,
        app_pass: []const u8,
        access_type: AccessType,
        user_agent: []const u8,
        token: ?Token = null,

        auto_refresh_token: bool,
        user_agent_is_owned: bool,

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

        pub fn initAuthorize(allocator: Allocator, options: InitOptions) !Self {
            const app_id = if (config.alloc_app_id) try allocator.dupe(u8, options.app_id) else options.app_id;
            const app_pass = if (config.alloc_app_pass) try allocator.dupe(u8, options.app_pass) else options.app_pass;
            const access_type = if (config.alloc_access_type) blk: {
                switch (options.access_type) {
                    .userless => |x| {
                        const device_id = if (x.device_id) |id| try allocator.dupe(u8, id) else null;
                        break :blk AccessType{ .userless = .{ .device_id = device_id } };
                    },
                    .user => |x| {
                        const user_id = try allocator.dupe(u8, x.user_id);
                        const user_pass = try allocator.dupe(u8, x.user_pass);
                        break :blk AccessType{ .user = .{ .user_id = user_id, .user_pass = user_pass } };
                    },
                }
                unreachable;
            } else options.access_type;

            var user_agent_is_owned: bool = undefined;
            const user_agent = blk: {
                if (options.user_agent) |user_agent| {
                    switch (config.alloc_user_agent) {
                        inline .false, .if_auto => {
                            user_agent_is_owned = false;
                            break :blk user_agent;
                        },
                        .true => {
                            const ua = try allocator.dupe(u8, user_agent);
                            user_agent_is_owned = true;
                            break :blk ua;
                        },
                    }
                    unreachable;
                } else {
                    switch (config.alloc_user_agent) {
                        .false => @panic("Required user agent"),
                        inline .if_auto, .true => {
                            const platform = @tagName(@import("builtin").os.tag);
                            const version = "v0.0.0";
                            const ua = switch (options.access_type) {
                                .userless => try fmt.allocPrint(allocator, "{s}:zraw:{s} (user-less)", .{ platform, version }),
                                .user => |x| try fmt.allocPrint(allocator, "{s}:zraw:{s} (by /u/{s})", .{ platform, version, x.user_id }),
                            };
                            user_agent_is_owned = true;
                            break :blk ua;
                        },
                    }
                }
                unreachable;
            };

            var self = Self{
                .allocator = allocator,
                .app_id = app_id,
                .app_pass = app_pass,
                .access_type = access_type,
                .user_agent = user_agent,
                .auto_refresh_token = options.auto_refresh_token,
                .user_agent_is_owned = user_agent_is_owned,
            };
            try self.authorize();
            return self;
        }

        pub fn deinit(self: *Self) void {
            if (self.token) |token| {
                self.allocator.free(token.access_token);
                self.allocator.free(token.token_type);
                self.allocator.free(token.scope);
                self.allocator.free(token.authorization);
            }
            if (self.user_agent_is_owned) {
                self.allocator.free(self.user_agent);
            }
        }

        pub fn refreshToken(
            self: *Self,
        ) !void {
            if (self.authorized_once == false) {
                @panic("Cannot refresh token without being authorized once.");
            }
            try self.authorize();
        }

        fn authorize(self: *Self) !void {
            if (self.token) |token| {
                self.allocator.free(token.access_token);
                self.allocator.free(token.token_type);
                self.allocator.free(token.scope);
                self.allocator.free(token.authorization);
            }

            var buffer: [1 << 14]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buffer);
            const fballoc = fba.allocator();

            var client = Client{ .allocator = self.allocator };
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
                    .userless => |ty| try fmt.allocPrint(fballoc, "grant_type=client_credentials&device_id={s}", .{ty.device_id orelse "DO_NOT_TRACK_THIS_DEVICE"}),
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

                break :blk try (api.AccessToken{}).fetch(fballoc, fetch_options);
            };
            const parsed = try json.parseFromSlice(api.AccessToken.Model, fballoc, response.payload, .{});
            defer parsed.deinit();

            const access_token = try self.allocator.dupe(u8, parsed.value.access_token);
            const token_type = try self.allocator.dupe(u8, parsed.value.token_type);
            const scope = try self.allocator.dupe(u8, parsed.value.scope);
            const authorization = try fmt.allocPrint(self.allocator, "{s} {s}", .{ parsed.value.token_type, parsed.value.access_token });

            self.token = Token{
                .expires_at = @as(u64, @intCast(std.time.timestamp())) + parsed.value.expires_in,
                .access_token = access_token,
                .token_type = token_type,
                .scope = scope,
                .authorization = authorization,
            };
        }

        pub fn agent(self: *Self, comptime optional_agent_buffer_config: ?AgentBufferConfig) Agent(Self, optional_agent_buffer_config) {
            if (self.token == null) @panic("Not yet authorize");
            return Agent(Self, optional_agent_buffer_config).init(self.allocator, self);
        }

        // pub fn agent_unmanaged(self: *Self, comptime agent_config: AgentConfig) AgentUnmanaged(Self, agent_config) {
        //     if (self.token_generation == 0) unreachable;

        //     return AgentUnmanaged(Self, agent_config).init(self.allocator, &self);
        // }

        // pub fn getAuthorization(self: *const Self) Error![]const u8 {
        //     const token = self.token orelse return Error.NoToken;
        //     return token.authorization;
        // }

        // pub fn writeAuthorization(self: *const Self) []const u8 {
        //     const token = self.token orelse return Error.NoToken;
        //     return token.authorization;
        // }
    };
}

// pub const AgentConfig = struct {
//     token_options: BufferOptions = BufferOptions.dynamic,
//     response_buffer_options: BufferOptions = BufferOptions.dynamic,

//     pub const BufferOptions = union(enum) {
//         static: usize,
//         dynamic,
//     };
// };

pub const AgentBufferConfig = union(enum) {
    static: usize,
    dynamic,
};

pub fn Agent(comptime AppType: type, comptime optional_config: ?AgentBufferConfig) type {
    const config = optional_config orelse AgentBufferConfig.dynamic;
    return struct {
        allocator: Allocator,
        app: *AppType,
        client: Client,
        response_inner_buffer: ResponseInnerBuffer,
        // token_buffer: TokenBuffer,
        // token_generation: u32,

        const Self = @This();

        // const TokenBuffer = switch (config.token_options) {
        //     .static => |size| StaticAllocBuffer(size),
        //     .dynamic => DynamicAllocBuffer,
        // };

        const ResponseInnerBuffer = switch (config) {
            .static => |size| struct {
                buffer: [size]u8 = undefined,
                fn init(_: Allocator) @This() {
                    return @This(){};
                }
                fn deinit(_: @This()) void {}
                fn responseBuffer(self: *@This()) ResponseBuffer {
                    return .{ .static = &self.buffer };
                }
            },
            .dynamic => struct {
                buffer: std.ArrayList(u8),
                fn init(allocator: Allocator) @This() {
                    return @This(){ .buffer = std.ArrayList(u8).init(allocator) };
                }
                fn deinit(self: @This()) void {
                    self.buffer.deinit();
                }
                fn responseBuffer(self: *@This()) ResponseBuffer {
                    self.buffer.clearRetainingCapacity();
                    return .{ .dynamic = &self.buffer };
                }
            },
        };

        fn init(allocator: Allocator, app: *AppType) Self {
            const client = Client{ .allocator = allocator };
            // const token_buffer = TokenBuffer{};
            const response_inner_buffer = ResponseInnerBuffer.init(allocator);
            return Self{
                .allocator = allocator,
                .app = app,
                .client = client,
                // .token_buffer = token_buffer,
                .response_inner_buffer = response_inner_buffer,
            };
        }

        pub fn deinit(self: *Self) void {
            self.response_inner_buffer.deinit();
            self.client.deinit();
        }

        // fn refreshToken(self: *Self) !void {
        //     if (self.app.token_generation == 0) unreachable;
        //     if (self.token_generation == self.app.token_generation) return;
        //     self.token_buffer.reset();
        //     self.token_buffer.alloc(self.allocator, self.app.token.authorization);
        // }

        fn getAuthorization(self: *Self) []const u8 {
            const token = self.app.token orelse @panic("not yet authorize");
            return token.authorization;
        }

        pub fn fetch(self: *Self, context: anytype) Error!Parsed(@TypeOf(context).Model) {
            api.verifyContext(@TypeOf(context));
            const response = try self.fetchBytes(context);
            defer response.deinit();
            return json.parseFromSlice(@TypeOf(context).Model, self.allocator, response.payload, .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
                // .allocate = .alloc_if_needed,
                // pub const AllocWhen = enum { alloc_if_needed, alloc_always };
            });
        }

        pub fn fetchBytes(self: *Self, context: anytype) api.Error!Response {
            api.verifyContext(@TypeOf(context));

            // const authorization = (self.app.token orelse return error.NotAuthorized).authorization;
            // const authorization = self.app.;

            const authorization = self.getAuthorization();

            const options = api.ContextFetchOptions{
                .client = &self.client,
                .response_buffer = self.response_inner_buffer.responseBuffer(),
                .user_agent = self.app.user_agent,
                .authorization = authorization,
                .payload = null,
            };
            return context.fetch(self.allocator, options);
        }
    };
}

const print = std.debug.print;
const json = std.json;

const testOptions = @import("util.zig").testOptions;
const TestOptions = @import("util.zig").TestOptions;
// const parser = @import("parser.zig");

const Thing = model.Thing;
const Listing = model.Listing;
const Link = model.Link;
const Comment = model.Comment;
const AccountMe = model.AccountMe;

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
}

test "auth" {
    // if (true) return error.SkipZigTest;

    const testopts: TestOptions = testOptions() orelse return error.SkipZigTest;

    // const allocator = std.testing.allocator;
    const allocator = std.heap.page_allocator;

    // ======================

    const app_config = AppConfig{
        //
    };

    const init_options = InitOptions{
        .app_id = testopts.app_id,
        .app_pass = testopts.app_pass,
        .access_type = .{ .user = .{ .user_id = testopts.user_id, .user_pass = testopts.user_pass } },
        .user_agent = null,
        .auto_refresh_token = true,
    };

    var app = try App(app_config).initAuthorize(allocator, init_options);

    // var app = App(app_config){
    //     .allocator = allocator,
    //     .app_id = testopts.app_id,
    //     .app_pass = testopts.app_pass,
    //     .access_type = .{ .user = .{ .user_id = testopts.user_id, .user_pass = testopts.user_pass } },
    //     .user_agent = null,
    //     .auto_refresh_token = true,
    // };
    defer app.deinit();
    try app.authorize();

    print("#######################3\n", .{});

    // print("user-agent: {s}\n", .{app.user_agent});
    // print("authorization {s}\n", .{app.token.authorization});

    // defer app.deinit(allocator);

    // const config = AgentBufferType{
    //     .buffer_type = .dynamic,
    //     // .buffer_type = .{ .static = 1024 * 1024 * 4 },
    // };

    // var agent = auth.agent(allocator, null, .{ .static = 1024 * 1024 });
    var agent = app.agent(null);
    defer agent.deinit();

    {
        // const Context = api.AccountMe;
        // const parsed = try agent.fetch(Context{
        //     // .limit = 9,
        //     // .sr_detail = true,
        // });
        // defer parsed.deinit();

        // const root = parsed.value;

        // const pretty = try model.allocPrettyPrint(allocator, root);
        // print("{s}\n", .{pretty});
    }

    {
        // const parsed = blk: {
        //     const Context = api.AccountMe;
        //     const response = try agent.fetchBytes(Context{
        //         // .limit = 9,
        //         // .sr_detail = true,
        //     });
        //     defer response.deinit();

        //     const parsed = try json.parseFromSlice(Context.Model, allocator, response.payload, .{
        //         .ignore_unknown_fields = true,
        //         // .allocate = .alloc_always,
        //     });

        //     break :blk parsed;
        // };
        // defer parsed.deinit();

        // const pretty = try model.allocPrettyPrint(allocator, parsed.value);
        // print("{s}\n", .{pretty});
    }

    {
        const Context = api.ListingNew("zig");

        const parsed = try agent.fetch(Context{
            .limit = 9,
            .sr_detail = true,
        });
        defer parsed.deinit();

        const pretty = try model.allocPrettyPrint(allocator, parsed.value);
        print("{s}\n", .{pretty});

        // const children = parsed.value.listing.children;
        // for (children) |child_thing| {
        //     const link = child_thing.link;
        //     _ = link; // autofix
        //     // print("{s}\n", .{link.selftext});

        //     // print("{any}\n", .{@TypeOf(child_thing)});
        // }

        // print("{any}\n", .{root});
    }

    {
        // const Context = api.ListingNew("zig");

        // const response = try agent.fetchBytes(Context{
        //     .limit = 9,
        //     .sr_detail = true,
        // });
        // defer response.deinit();

        // const parsed = try json.parseFromSlice(Thing, allocator, response.payload, .{
        //     .ignore_unknown_fields = true,
        //     // .allocate = .alloc_always,
        // });

        // const pretty = try model.allocPrettyPrint(allocator, parsed.value);
        // print("{s}\n", .{pretty});

    }

    {
        // const Context = api.UserComments("spez");

        // // const response = try agent.fetchBytes(Context{
        // //     //
        // // });
        // // _ = response; // autofix

        // // print("{s}\n", .{response.payload});

        // const parsed = try agent.fetch(Context{
        //     // .sort = .top,
        //     // .t = .month,
        // });
        // parsed.deinit();

        // // const parsed = try json.parseFromSlice(Thing, allocator, response.payload, .{
        // //     .ignore_unknown_fields = true,
        // // });

        // const children = parsed.value.listing.children;
        // // print("{any}\n", .{children});

        // for (children) |child_thing| {
        //     const comment = child_thing.comment;
        //     print("{s}\n", .{comment.body});

        //     // print("{any}\n", .{@TypeOf(child_thing)});
        // }
    }
}
