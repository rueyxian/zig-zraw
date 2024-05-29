const std = @import("std");
const testing = std.testing;
const debug = std.debug;
const mem = std.mem;
const fmt = std.fmt;
const meta = std.meta;
const Method = std.http.Method;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
// const Comp = std.ComptimeStringMap;
// const ResponseStorage = std.http.Client.FetchOptions.ResponseStorage;

// const CowBytes = @import("cow_bytes.zig").CowBytes;
const kvs = @import("kvs.zig");
const util = @import("util.zig");
const CowString = @import("CowString.zig");
// const StaticStringMap = @import("util.zig").StaticStringMap;
const BytesIterator = @import("util.zig").BytesIterator;

const Request = @import("Request.zig");
// const Response = Request.Response;
// const ResponseBuffer = Request.ResponseBuffer;

pub const Scope = @import("api/auth.zig").Scope;

pub const Authorize = @import("api/auth.zig").Authorize;
pub const AccessToken = @import("api/auth.zig").AccessToken;
pub const RevokeToken = @import("api/auth.zig").RevokeToken;

pub const AccountMe = @import("api/account.zig").AccountMe;

pub const LinksNew = @import("api/listing.zig").LinksNew;
pub const LinkComments = @import("api/listing.zig").LinkComments;

pub const UserComments = @import("api/user.zig").UserComments;

pub const SubmitLink = @import("api/submission.zig").SubmitLink;

pub const url_domain = "https://www.reddit.com";
pub const url_doman_oauth = "https://oauth.reddit.com";

pub const Error = ApiError;

pub const ApiError = error{ OutOfMemory, NoSpaceLeft };

// ==============================

pub fn sendRequestFromContext(allocator: Allocator, client: *Client, header_buffer: []u8, user_agent: []const u8, context: anytype) !Request {
    const Context = @TypeOf(context);

    const url = try context.cowFullUrl(allocator);
    defer url.deinit(allocator);

    const basic_auth: ?[]const u8 = if (@hasDecl(Context, "allocBasicAuth")) try context.allocBasicAuth(allocator) else null;
    defer if (basic_auth) |s| allocator.free(s);

    const payload: ?[]const u8 = if (@hasDecl(Context, "allocPayload")) try context.allocPayload(allocator) else null;
    defer if (payload) |s| allocator.free(s);

    var request = try Request.open(.{
        .client = client,
        .header_buffer = header_buffer,
        .url = url.value,
        .method = Context.method,
        .user_agent = user_agent,
        .authorization = basic_auth,
        .payload = payload,
    });
    try request.send();
    return request;
}

// ==============================

pub fn verifyContext(comptime Context: type) void {
    if (isContext(Context)) return;
    @panic("Invalid context type.");
}

pub fn isContext(comptime Context: type) bool {
    const info = @typeInfo(Context);
    if (info != .Struct) return false;
    // if (!@hasDecl(Context, "path")) return false; // TODO
    // if (!isStringLiteral(@field(Context, "path"))) return false;

    // if (!@hasDecl(Context, "www_url") or !@hasDecl(Context, "oauth_url")) return false; // TODO
    // if (!@hasDecl(Context, "url")) return false;
    if (!@hasDecl(Context, "method")) return false;
    if (@TypeOf(@field(Context, "method")) != Method) return false;

    if (!@hasDecl(Context, "Model")) return false;
    if (@TypeOf(@field(Context, "Model")) != type) return false;

    // {
    //     const url_info = @typeInfo(@TypeOf(@field(Context, "url")));
    //     if (url_info != .Pointer) return false;
    //     if (url_info.Pointer.size != .One) return false;
    //     if (!url_info.Pointer.is_const) return false;
    //     debug.assert(url_info.Pointer.sentinel == null);

    //     const child_info = @typeInfo(url_info.Pointer.child);
    //     if (child_info != .Array) return false;
    //     if (child_info.Array.child != u8) return false;

    //     if (child_info.Array.sentinel) |sen| {
    //         if (@as(*const u8, @ptrCast(@alignCast(sen))).* != 0) return false;
    //     } else return false;
    // }
    return true;
}

pub fn getCowFullUrlFn(comptime Context: type, fmt_url: []const u8, field_names_tuple: anytype) fn (*const Context, Allocator) ApiError!CowString {
    const fragments = comptime frg: {
        std.debug.assert(fmt_url.len > 0 and fmt_url[0] != '{' and fmt_url[0] != '}');
        var frags: blk: {
            var len: usize = 0;
            var it = std.mem.tokenizeAny(u8, fmt_url, "{}");
            while (it.next()) |_| len += 1;
            break :blk [len][]const u8;
        } = undefined;
        var i: usize = 0;
        var it = std.mem.tokenizeAny(u8, fmt_url, "{}");
        while (it.next()) |s| : (i += 1) frags[i] = s;
        debug.assert(frags.len != 0);
        break :frg frags;
    };

    return struct {
        pub fn func(context: *const Context, allocator: Allocator) ApiError!CowString {
            var params_buf: [1 << 11]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&params_buf);
            try kvs.stringify(Context, fbs.writer(), context.*, field_names_tuple);

            if (fragments.len == 1 and try fbs.getPos() == 0) {
                return CowString.borrowed(fragments[0]);
            }

            var list = std.ArrayList(u8).init(allocator);
            const writer = list.writer();
            inline for (fragments, 0..) |s, i| {
                if (i % 2 == 0) {
                    try writer.writeAll(s);
                    continue;
                }
                try writer.writeAll(@field(context, s));
            }

            if (try fbs.getPos() != 0) {
                try writer.writeByte('?');
                try writer.writeAll(fbs.getWritten());
            }

            return CowString.owned(try list.toOwnedSlice());
        }
    }.func;
}

pub fn getAllocPayloadFn(comptime Context: type, field_names_tuple: anytype) fn (*const Context, Allocator) ApiError![]const u8 {
    // verifyContext(Context);
    return struct {
        pub fn func(context: *const Context, allocator: Allocator) ApiError![]const u8 {
            // const s = try kvs.stringifyAlloc(allocator, context, field_names_tuple);
            const s = try kvs.stringifyAlloc(Context, allocator, context.*, field_names_tuple);
            debug.assert(s.len != 0);
            return s;
        }
    }.func;
}

pub fn fieldNamesTuple(comptime Context: type) FieldNamesTupleExceptFor(Context, .{}) {
    return .{};
}

pub fn fieldNamesTupleExceptFor(comptime Context: type, comptime field_names_tuple: anytype) FieldNamesTupleExceptFor(Context, field_names_tuple) {
    return .{};
}

fn FieldNamesTupleExceptFor(comptime Context: type, comptime field_names_tuple: anytype) type {
    const Excludes: ?type = blk: {
        inline for (field_names_tuple) |field_name| {
            debug.assert(@hasField(Context, field_name));
        }
        break :blk if (field_names_tuple.len == 0) null else util.StaticStringMap(field_names_tuple);
    };
    const ctx_fields = @typeInfo(Context).Struct.fields;
    var fields: [ctx_fields.len - field_names_tuple.len]std.builtin.Type.StructField = undefined;
    var i: usize = 0;
    inline for (ctx_fields) |ctx_field| {
        const value: []const u8 = ctx_field.name;
        blk: {
            if (Excludes) |Map| {
                if (Map.has(value)) break :blk;
            }
            fields[i] = std.builtin.Type.StructField{
                .name = fmt.comptimePrint("{}", .{i}),
                .type = @TypeOf(value),
                .default_value = @ptrCast(@alignCast(&value)),
                .is_comptime = true,
                .alignment = @alignOf(@TypeOf(value)),
            };
            i += 1;
        }
    }
    const info = std.builtin.Type.Struct{
        .layout = .auto,
        .backing_integer = null,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = true,
    };
    return @Type(std.builtin.Type{ .Struct = info });
}

const print = std.debug.print;
