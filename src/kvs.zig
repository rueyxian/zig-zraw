const std = @import("std");
const debug = std.debug;
const meta = std.meta;
const fmt = std.fmt;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const StaticStringMap = @import("util.zig").StaticStringMap;

// pub const Error = ParseError ||

pub const ParseError = error{UnexpectedToken};

pub const StringifyError = error{ OutOfMemory, NoSpaceLeft };

// pub fn StringifyError(comptime Stream: type) type {
//     return Stream.Error || std.ArrayList(u8).Writer.Error || error;
// }

// pub fn Parsed(comptime T: type) type {
//     return struct {
//         arena: *ArenaAllocator,
//         value: T,

//         pub fn deinit(self: @This()) void {
//             const allocator = self.arena.child_allocator;
//             self.arena.deinit();
//             allocator.destroy(self.arena);
//         }
//     };
// }

// pub fn parseFromSlice(comptime T: type, allocator: Allocator, slice: []u8) Parsed(T) {
//     _ = allocator;
//     _ = slice;

//     // const arena = allocator.create();
//     // _ = allocator;
//     // _ = slice;
//     //
//     return undefined;
// }

pub fn stringify(comptime Structure: type, out_stream: anytype, structure: Structure, field_names_tuple: anytype) StringifyError!void {
    var kvp_stream = WriteStream(Structure, @TypeOf(out_stream)){
        .stream = out_stream,
    };
    try kvp_stream.write(structure, field_names_tuple);
}

pub fn stringifyAlloc(comptime Structure: type, allocator: Allocator, structure: Structure, field_names_tuple: anytype) StringifyError![]const u8 {
    var list = std.ArrayList(u8).init(allocator);
    try stringify(Structure, list.writer(), structure, field_names_tuple);
    return try list.toOwnedSlice();
}

pub fn WriteStream(comptime StructureType: type, comptime OutStream: type) type {
    return struct {
        stream: Stream,
        has_written: bool = false,

        pub const Self = @This();
        pub const Structure = StructureType;
        pub const Stream = OutStream;

        fn writeValue(self: *Self, comptime T: type, value: T) StringifyError!void {
            switch (@typeInfo(@TypeOf(value))) {
                .Bool => try self.stream.writeAll((&[_][]const u8{ "false", "true" })[@intFromBool(value)]),
                .Pointer => |ptr_info| {
                    debug.assert(ptr_info.size == .Slice);
                    debug.assert(ptr_info.is_const == true);
                    debug.assert(ptr_info.child == u8);
                    try self.stream.writeAll(value);
                },
                .Int => try self.stream.print("{}", .{value}),
                .Enum => |_| try self.stream.writeAll(@tagName(value)),
                else => unreachable,
            }
        }

        fn write(self: *Self, structure: Structure, field_names_tuple: anytype) StringifyError!void {
            // const Structure = @TypeOf(structure);
            const info = @typeInfo(Structure);
            debug.assert(info == .Struct);
            debug.assert(info.Struct.layout == .auto);
            debug.assert(info.Struct.backing_integer == null);
            debug.assert(info.Struct.is_tuple == false);

            const Map: type = blk: {
                const tup_info = @typeInfo(@TypeOf(field_names_tuple));
                debug.assert(tup_info == .Struct);
                debug.assert(tup_info.Struct.is_tuple);
                inline for (field_names_tuple) |field_name| {
                    debug.assert(@hasField(Structure, field_name));
                }
                break :blk StaticStringMap(field_names_tuple);
            };

            inline for (info.Struct.fields) |field| {
                blk: {
                    if (!Map.has(field.name)) {
                        break :blk;
                    }

                    const maybe_opt_value = @field(structure, field.name);
                    const value = switch ((@typeInfo(field.type))) {
                        .Optional => |_| val: {
                            if (maybe_opt_value) |value| break :val value;
                            break :blk;
                        },
                        else => maybe_opt_value,
                    };

                    if (self.has_written) {
                        try self.stream.writeByte('&');
                    }

                    const write_key_fn_name = getwriteParamFnName("writeParamKey", field.name);
                    if (meta.hasFn(Structure, write_key_fn_name)) {
                        try @field(Structure, write_key_fn_name)(&structure, self.stream);
                    } else {
                        try self.stream.writeAll(field.name);
                    }

                    try self.stream.writeByte('=');

                    const write_value_fn_name = getwriteParamFnName("writeParamValue", field.name);
                    if (meta.hasFn(Structure, write_value_fn_name)) {
                        try @field(Structure, write_value_fn_name)(&structure, self.stream);
                    } else {
                        try self.writeValue(@TypeOf(value), value);
                    }

                    self.has_written = true;
                }
            }
        }
    };
}

inline fn getwriteParamFnName(comptime base_name: [:0]const u8, comptime field_name: [:0]const u8) [:0]const u8 {
    @setEvalBranchQuota(5000);
    const writeFromSnakeToPascal = struct {
        fn f(writer: anytype, s: []const u8) !void {
            const BytesIterator = struct {
                bytes: []const u8,
                pos: usize = 0,
                pub fn next(self: *@This()) ?u8 {
                    std.debug.assert(self.pos <= self.bytes.len);
                    if (self.pos == self.bytes.len) return null;
                    defer self.pos += 1;
                    return self.bytes[self.pos];
                }
                pub fn peek(self: *const @This()) ?u8 {
                    std.debug.assert(self.pos <= self.bytes.len);
                    if (self.pos + 1 == self.bytes.len) return null;
                    return self.bytes[self.pos + 1];
                }
            };

            if (s.len == 0) return;
            try writer.writeByte(std.ascii.toUpper(s[0]));
            if (s.len == 1) return;
            var it = BytesIterator{ .bytes = s[1..] };
            while (it.next()) |byte| {
                if (byte != '_') {
                    try writer.writeByte(byte);
                    continue;
                }
                const bytes2 = std.ascii.toUpper(it.next() orelse break);
                try writer.writeByte(bytes2);
            }
        }
    }.f;

    comptime {
        var buffer: ty: {
            var len = base_name.len;
            for (field_name) |byte| {
                if (byte != '_') len += 1;
            }
            break :ty [len:0]u8;
        } = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        fbs.writer().writeAll(base_name) catch unreachable;
        writeFromSnakeToPascal(fbs.writer(), field_name) catch unreachable;
        debug.assert(fbs.getWritten().len == buffer.len);
        return buffer[0.. :0];
    }
}
