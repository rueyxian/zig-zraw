const std = @import("std");
const debug = std.debug;
const json = std.json;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ParseOptions = std.json.ParseOptions;

const model = @import("../model.zig");
