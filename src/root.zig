const std = @import("std");
const testing = std.testing;
const debug = std.debug;
const json = std.json;
const fmt = std.fmt;
const fs = std.fs;
const http = std.http;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const Field = std.http.Field;
const Method = std.http.Method;

// const test_zon = @import("test_zon");

const zraw = @import("zraw");
const cow = @import("cow");
// const api = @import("api.zig");

const uri_access_token = "https://www.reddit.com/api/v1/access_token";
const uri_oauth_base = "https://oauth.reddit.com/";

pub const Error = error{
    HttpResponse,
};

const Number = u64;

// ==================================

const print = std.debug.print;

const testOptions = @import("util.zig").testOptions;
const TestOptions = @import("util.zig").TestOptions;

test "poiquer" {
    // if (true) return error.SkipZigTest;

    // test_zon.hello("corgi");
    // try testing.expect(false);

    const c = cow.borrowedCow("hello");
    _ = c; // autofix
}
