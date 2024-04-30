const std = @import("std");
const testing = std.testing;
const debug = std.debug;
const Allocator = std.mem.Allocator;

pub fn CowBytes(comptime BytesType: type) type {
    const info = @typeInfo(BytesType);
    debug.assert(info == .Pointer);
    switch (info.Pointer.size) {
        .Slice => debug.assert(info.Pointer.child == u8),
        .One => {
            const child = info.Pointer.child;
            const child_info = @typeInfo(child);
            debug.assert(child_info == .Array);
            debug.assert(child_info.Array.child == u8);
            info.Pointer.size = .Slice;
            info.Pointer.child = child_info.Array.child;
        },
        else => unreachable,
    }

    return struct {
        is_owned: bool,
        bytes: Bytes,

        const Self = @This();
        const Bytes: type = BytesType;

        // const ConstCowBuffer = blk: {
        //     var _info = info;
        //     _info.Pointer.is_const = true;
        //     break :blk @Type(_info);
        // };

        pub fn borrowed(bytes: anytype) Self {
            return Self{
                .is_owned = false,
                .bytes = bytes,
            };
        }

        pub fn owned(bytes: anytype) Self {
            return Self{
                .is_owned = true,
                .bytes = bytes,
            };
        }

        pub fn alloc(allocator: Allocator, n: usize) Allocator.Error!Self {
            const bytes = try allocator.alloc(u8, n);
            return Self{
                .is_owned = true,
                .bytes = bytes,
            };
        }

        pub fn allocPrint(allocator: Allocator, comptime fmt: []const u8, args: anytype) Allocator.Error!CowBytes {
            const bytes = try std.fmt.allocPrint(allocator, fmt, args);
            return CowBytes{
                .is_owned = true,
                .bytes = bytes,
            };
        }

        pub fn deinit(self: *const Self, allocator: Allocator) void {
            if (!self.is_owned) {
                return;
            }
            allocator.free(self.bytes);
        }
    };
}

// pub fn cow_buffer(buffer: anytype) CowBuffer(Slice(@TypeOf(buffer))) {
//     return CowBuffer(Slice(@TypeOf(buffer))).from(buffer);
// }

// pub fn cow_const_buffer(buffer: anytype) CowBuffer(Slice(@TypeOf(buffer))) {
//     return CowBuffer(Slice(@TypeOf(buffer))).from(buffer);
// }

// fn Slice(comptime Buffer: type, comptime is_const: bool) type {
//     var info = @typeInfo(Buffer);
//     debug.assert(info == .Pointer);
//     switch (info.Pointer.size) {
//         .Slice => debug.assert(info.Pointer.child == u8),
//         .One => {
//             const child = info.Pointer.child;
//             const child_info = @typeInfo(child);
//             debug.assert(child_info == .Array);
//             debug.assert(child_info.Array.child == u8);
//             info.Pointer.size = .Slice;
//             info.Pointer.child = child_info.Array.child;
//         },
//         else => unreachable,
//     }
//     info.Pointer.is_const = is_const;
//     return @Type(info);
// }

// test "asdf" {
//     const allocator = std.testing.allocator;

//     const s = "hello";

//     // const T = Slice(@TypeOf(s));

//     // std.debug.print("{}\n", .{T});

//     const c = CowBuffer([]const u8).from(s);
//     defer c.deinit(allocator);
// }
