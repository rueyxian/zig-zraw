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

    const allocator = std.testing.allocator;

    const T = struct {
        int: i64,
        float: f64,
        @"with\\escape": bool,
        @"withąunicode😂": bool,
        language: []const u8,
        optional: ?bool,
        default_field: i32 = 42,
        static_array: [3]f64,
        dynamic_array: []f64,

        complex: struct {
            nested: []const u8,
        },

        veryComplex: []struct {
            foo: []const u8,
        },

        a_union: Union,
        const Union = union(enum) {
            x: u8,
            float: f64,
            string: []const u8,
        };
    };

    const doc =
        \\{
        \\  "int": 420,
        \\  "float": 3.14,
        \\  "with\\escape": true,
        \\  "with\u0105unicode\ud83d\ude02": false,
        \\  "language": "zig",
        \\  "optional": null,
        \\  "static_array": [66.6, 420.420, 69.69],
        \\  "dynamic_array": [66.6, 420.420, 69.69],
        \\  "complex": {
        \\    "nested": "zig"
        \\  },
        \\  "veryComplex": [
        \\    {
        \\      "foo": "zig"
        \\    }, {
        \\      "foo": "rocks"
        \\    }
        \\  ],
        \\  "a_union": {
        \\    "float": 100000
        \\  }
        \\}
    ;

    const parsed_dynamic = try json.parseFromSlice(json.Value, allocator, doc, .{});
    defer parsed_dynamic.deinit();

    print("{any}\n", .{parsed_dynamic.value});

    {
        const parsed = try json.parseFromValue(T, allocator, parsed_dynamic.value, .{});
        defer parsed.deinit();
        // try testing.expectEqualDeep(expected, parsed.value);
    }

    // test_zon.hello("corgi");
    // try testing.expect(false);

}
