const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

const domain_www = @import("../api.zig").domain_www;

pub const AccessToken = struct {
    pub const endpoint = domain_www ++ "api/v1/access_token";
    pub const method: Method = .POST;
    pub const Payload = struct {
        access_token: []const u8,
        token_type: []const u8,
        expires_in: u64,
        scope: []const u8,
    };
};

// fn MixinPayload(comptime Payload: type) type {
//     return struct {
//         var owned: bool = false;
//         pub fn deinit(self: *Payload, allocator: Allocator) void {
//             _ = self;
//             _ = allocator;

//             //
//         }
//     };
// }

// test "asdf" {
//     const payload = AccessToken.Payload{
//         .access_token = "asdf",
//         .token_type = "haha",
//         .expires_in = 42,
//         .scope = "*",
//     };
//     _ = payload;

//     // AccessToken.Payload.

//     // payload.deinit()

//     // std.debug.print("{any}\n", .{payload});
// }
