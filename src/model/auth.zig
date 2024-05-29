const std = @import("std");
const mem = std.mem;
const json = std.json;
const Allocator = std.mem.Allocator;
const ParseOptions = std.json.ParseOptions;
const ParseError = std.json.ParseError;

const kvs = @import("../kvs.zig");

const fillDefaultStructValues = @import("../model.zig").fillDefaultStructValues;

pub const Scope = enum {
    @"*",
    identity,
    edit,
    flair,
    history,
    modconfig,
    modflair,
    modlog,
    modposts,
    modwiki,
    mysubreddits,
    privatemessages,
    read,
    report,
    save,
    submit,
    subscribe,
    vote,
    wikiedit,
    wikiread,
};

pub const Token = struct {
    access_token: []const u8,
    token_type: []const u8,
    expires_in: u64,
    scope: []const u8,
    refresh_token: ?[]const u8 = null,
    state: ?[]const u8 = null,

    // pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !@This() {
    //     const Error = ParseError(@TypeOf(source.*));

    //     if (try source.next() != .object_begin) {
    //         return Error.UnexpectedToken;
    //     }

    //     var ret: @This() = undefined;

    //     const info = @typeInfo(@This()).Struct;
    //     var fields_seen = [_]bool{false} ** info.fields.len;

    //     while (true) {
    //         const field_name = switch (try source.next()) {
    //             .object_end => break,
    //             .string => |s| s,
    //             else => return Error.UnexpectedToken,
    //         };

    //         inline for (info.fields, 0..) |field, i| {
    //             if (mem.eql(u8, field_name, field.name)) {
    //                 if (field.type == []const Scope) {

    //                     // @field(ret, field.name) = try ImplJsonParseEmptyObjectAsNullFn(MediaEmbeded).jsonParse(allocator, source, options);
    //                 } else {
    //                     @field(ret, field.name) = try json.innerParse(field.type, allocator, source, options);
    //                 }
    //                 fields_seen[i] = true;
    //                 break;
    //             }
    //         } else {
    //             if (options.ignore_unknown_fields) {
    //                 try source.skipValue();
    //             } else {
    //                 return error.UnknownField;
    //             }
    //         }
    //     }
    //     try fillDefaultStructValues(@This(), &ret, &fields_seen);
    //     return ret;
    // }
};

pub const AuthorizationCode = struct {
    state: []const u8,
    code: []const u8,

    const Error = error{ParseError} || Allocator.Error;

    fn allocParse(allocator: Allocator, bytes: []const u8) Error!@This() {
        const start = "GET/?".len + 1;
        const end = mem.indexOf(u8, bytes, " HTTP/1.1") orelse return Error.ParseError;
        if (start > end or end > bytes.len) return Error.ParseError;
        const payload = bytes[start..end];

        const state, const code = blk: {
            var it = mem.splitScalar(u8, payload, '&');
            var a = it.next() orelse return Error.ParseError;
            var b = it.next() orelse return Error.ParseError;
            if (a.len < "state=".len) return Error.ParseError;
            if (b.len < "code=".len) return Error.ParseError;
            break :blk .{ a["state=".len..], b["code=".len..] };
        };

        // kvs.

        return @This(){
            .state = try allocator.dupe(u8, state),
            .code = try allocator.dupe(u8, code),
        };
    }
};
