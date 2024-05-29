const std = @import("std");
const builtin = @import("builtin");
const debug = std.debug;
const fmt = std.fmt;
const mem = std.mem;
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Client = std.http.Client;

const model = @import("model.zig");

const Scope = @import("model/auth.zig").Scope;
const Token = @import("model/auth.zig").Token;
const Request = @import("Request.zig");

const Authorizer = @import("authorizer.zig").Authorizer;
const Flow = @import("authorizer.zig").Flow;
const Unregistered = @import("authorizer.zig").Unregistered;
const PasswordCredentials = @import("authorizer.zig").PasswordCredentials;

const Error = Request.Error || Authorizer.Error || JsonParseError || HttpError;
const HttpError = error{Undefined};
const JsonParseError = json.ParseError(json.Scanner);

pub const AppConfig = struct {
    thread_safe: bool = !builtin.single_threaded,
    MutexType: ?type = null,
    preemptive_token_request: usize = 0,
    header_buffer_size: usize = 1 << 13,
    response_buffer_type: BufferType = .dynnamic,

    pub const BufferType = union(enum) {
        static: usize,
        dynnamic,
    };
};

pub fn App(config: AppConfig) type {
    return struct {
        allocator: Allocator,
        user_agent: []const u8,
        authorizer: Authorizer,

        session: Session,
        mutex: Mutex = .{},

        pub const Self = @This();

        const SessionStatus = union(enum) {
            unauthorized,
            expired,
            expires_in: u64,
        };

        const Session = struct {
            token: Token,
            expires_at: u64,
            authorization: []const u8, // NOTE bearer,
            arena: ArenaAllocator,

            fn init(allocator: Allocator) Session {
                return Session{
                    .token = undefined,
                    .expires_at = 0,
                    .authorization = undefined,
                    .arena = ArenaAllocator.init(allocator),
                };
            }
        };

        const Mutex = if (config.MutexType) |T|
            T
        else if (config.thread_safe)
            std.Thread.Mutex
        else
            struct {
                fn lock(_: *@This()) void {}
                fn unlock(_: *@This()) void {}
            };

        pub fn init(allocator: Allocator, authorizer: Authorizer, user_agent: []const u8) Error!Self {
            const _user_agent = try allocator.dupe(u8, user_agent);
            return Self{
                .allocator = allocator,
                .user_agent = _user_agent,
                .authorizer = authorizer,
                .session = Session.init(allocator),
            };
        }

        pub fn lock(self: *Self) void {
            self.mutex.lock();
        }

        pub fn unlock(self: *Self) void {
            self.mutex.unlock();
        }

        fn sessionStatus(self: *const Self) SessionStatus {
            if (self.session.expires_at == 0) return SessionStatus.unauthorized;
            const expires_in = self.session.expires_at -| @as(u64, @intCast(std.time.timestamp()));
            if (expires_in == 0) return SessionStatus.expired;
            return SessionStatus{ .expires_in = expires_in };
        }

        fn flow(self: *const Self) Flow {
            self.authorizer.flow();
        }

        fn requestToken(self: *Self) Authorizer.Error!void {
            const start: u64 = @intCast(std.time.timestamp());
            var client = Client{ .allocator = self.allocator };

            var header_buffer: [1 << 13]u8 = undefined;

            errdefer self.session.expires_at = 0;
            _ = self.session.arena.reset(.retain_capacity);
            const aa = self.session.arena.allocator();
            // const aa = self.allocator;

            const token = try self.authorizer.accessTokenLeaky(aa, &client, &header_buffer, self.user_agent);
            self.session.token = token;
            self.session.authorization = try fmt.allocPrint(aa, "{s} {s}", .{ token.token_type, token.access_token });
            self.session.expires_at = start + token.expires_in;
        }

        fn requestTokenIfNeeded(self: *Self) Authorizer.Error!void {
            switch (self.sessionStatus()) {
                .unauthorized, .expired => {},
                .expires_in => |t| {
                    if (t -| config.preemptive_token_request != 0) return;
                },
            }
            try self.requestToken();
        }

        pub fn getAuthorization(self: *Self) Authorizer.Error![]const u8 {
            try self.requestTokenIfNeeded();
            return self.session.authorization;
        }

        pub fn getAgent(self: *Self) Allocator.Error!Agent(Self) {
            const user_agent = try self.allocator.dupe(u8, self.user_agent);
            return Agent(Self){
                .allocator = self.allocator,
                .app = self,
                .user_agent = user_agent,
                .client = Client{ .allocator = self.allocator },
            };
        }
    };
}

pub fn Agent(comptime AppType: type) type {
    return struct {
        allocator: Allocator,
        app: *AppType,
        user_agent: []const u8,
        client: Client,
        authorization: ?[]const u8 = null,

        fn getAuthorization(self: *@This()) Error![]const u8 {
            self.app.lock();
            defer self.app.unlock();
            const authorization = try self.app.getAuthorization();
            if (self.authorization) |auth| {
                if (mem.eql(u8, auth, authorization)) return auth;
                self.allocator.free(auth);
            }
            self.authorization = try self.allocator.dupe(u8, authorization);
            return self.authorization.?;
        }

        pub fn requestAlloc(self: *@This(), context: anytype) Error!json.Parsed(@TypeOf(context).Model) {
            const Context = @TypeOf(context);
            var req = try self.sendRequest(context);
            const payload = try req.reader().readAllAlloc(self.allocator, 1024 * 1024 * 2);
            defer self.allocator.free(payload);
            return json.parseFromSlice(Context.Model, self.allocator, payload, .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            });
        }

        pub fn requestRawAlloc(self: *@This(), context: anytype) Error![]u8 {
            var req = try self.sendRequest(context);
            errdefer req.deinit();
            return try req.reader().readAllAlloc(self.allocator);
        }

        fn sendRequest(self: *@This(), context: anytype) Error!Request {
            {
                var req = try self.innerSendRequest(context);
                if (req.status() == .ok) {
                    return req;
                }
                req.deinit();
            }

            {
                var req = try self.innerSendRequest(context);
                if (req.status() != .ok) {
                    defer req.deinit();
                    return HttpError.Undefined;
                }
                return req;
            }
        }

        fn innerSendRequest(self: *@This(), context: anytype) Error!Request {
            const Context = @TypeOf(context);
            var header_buffer: [1 << 13]u8 = undefined;

            const url = switch (self.app.authorizer.flow()) {
                .unregistered => try context.cowFullUrl(self.allocator),
                else => try context.cowFullUrlOauth(self.allocator),
            };
            defer url.deinit(self.allocator);

            const authorization = try self.getAuthorization();

            const payload: ?[]const u8 = if (@hasDecl(Context, "allocPayload")) try context.allocPayload(self.allocator) else null;
            defer if (payload) |s| self.allocator.free(s);

            var req = try Request.open(.{
                .client = &self.client,
                .header_buffer = &header_buffer,
                .url = url.value,
                .method = Context.method,
                .user_agent = self.user_agent,
                .authorization = authorization,
                .payload = payload,
            });
            errdefer req.deinit();
            try req.send();
            return req;
        }
    };
}

const print = std.debug.print;
const Headers = std.http.Client.Request.Headers;

const testDataAlloc = @import("util.zig").testDataAlloc;
const testData = @import("util.zig").testData;

const api = @import("api.zig");

test "password grant" {
    const allocator = std.heap.page_allocator;
    const td = try testData();

    //========================================

    var auth = try PasswordCredentials.init(allocator, .{
        .client_id = td.script_client_id,
        .client_secret = td.script_client_secret,
        .username = td.username,
        .password = td.password,
    });

    var app = try App(.{}).init(allocator, auth.authorizer(), td.user_agent);

    var agent = try app.getAgent();

    const res = try agent.requestAlloc(api.LinksNew{
        .subreddit = "zig",
        .limit = 4,
    });

    print("{s}\n", .{try model.allocPrettyPrint(allocator, res.value)});
}
