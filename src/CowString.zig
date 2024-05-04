const std = @import("std");
const Allocator = std.mem.Allocator;

const CowString = @This();

is_owned: bool,
value: []const u8,

pub fn borrowed(string: []const u8) CowString {
    return CowString{
        .is_owned = false,
        .value = string,
    };
}

pub fn owned(string: []const u8) CowString {
    return CowString{
        .is_owned = true,
        .value = string,
    };
}

pub fn deinit(self: CowString, allocator: Allocator) void {
    if (!self.is_owned) {
        return;
    }
    allocator.free(self.value);
}
