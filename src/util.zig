const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const io = std.io;
const fmt = std.fmt;
const json = std.json;
const mem = std.mem;
const net = std.net;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Thread = std.Thread;

pub fn StaticStringMap(comptime strings_tuple: anytype) type {
    const kvs_list = comptime blk: {
        const KV = struct { []const u8, void };
        var fields: [strings_tuple.len]std.builtin.Type.StructField = undefined;
        for (0..strings_tuple.len) |i| {
            const value = KV{ strings_tuple[i], {} };
            fields[i] = std.builtin.Type.StructField{
                .name = fmt.comptimePrint("{}", .{i}),
                .type = KV,
                .default_value = @ptrCast(@alignCast(&value)),
                .is_comptime = true,
                .alignment = @alignOf(KV),
            };
        }
        const info = std.builtin.Type.Struct{
            .layout = .auto,
            .backing_integer = null,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        };
        break :blk @Type(std.builtin.Type{ .Struct = info }){};
    };
    return std.ComptimeStringMap(void, kvs_list);
}

pub const BytesIterator = struct {
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

// NOTE: unused
fn isStringLiteral(value: anytype) bool {
    const info = @typeInfo(@TypeOf(value));
    if (info != .Pointer) return false;
    if (info.Pointer.size != .One) return false;
    if (!info.Pointer.is_const) return false;
    debug.assert(info.Pointer.sentinel == null);

    const child_info = @typeInfo(info.Pointer.child);
    if (child_info != .Array) return false;
    if (child_info.Array.child != u8) return false;

    if (child_info.Array.sentinel) |sen| {
        if (@as(*const u8, @ptrCast(@alignCast(sen))).* != 0) return false;
    } else return false;

    return true;
}

// NOTE: unused
pub fn maxIntLength(comptime T: type) usize {
    const info = @typeInfo(T);
    debug.assert(info == .Int);
    // debug.assert(info.Int.signedness == .unsigned);
    comptime var res: usize = 0;
    comptime var num = std.math.maxInt(T);
    inline while (num != 0) {
        num /= 10;
        res += 1;
    }
    return res + @intFromBool(info.Int.signedness == .signed);
}

// NOTE: unused
// fn uintLength(comptime T: type, number: T) usize {
//     const info = @typeInfo(T);
//     debug.assert(info == .Int);
//     debug.assert(info.Int.signedness == .unsigned);
//     const pow_tens = blk: {
//         var tens: [maxUintLength(T) - 1]T = undefined;
//         inline for (&tens, 1..) |*n, i| {
//             n.* = std.math.pow(T, 10, i);
//         }
//         break :blk tens;
//     };
//     var i: usize = 1;
//     for (pow_tens) |n| {
//         if (number < n) break;
//         i += 1;
//     }
//     return i;
// }

pub fn processOpen(allocator: Allocator, arg: []const u8) !void {
    const argv = [_][]const u8{ "open", arg };
    const proc = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
    });
    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);
}

pub const Listener = struct {
    allocator: Allocator,
    port: u16,
    buffer: []const u8 = undefined,

    fn deinit(self: @This()) void {
        self.allocator.free(self.buffer);
    }

    fn run(self: *@This()) !void {
        const address = try net.Address.parseIp("127.0.0.1", self.port);
        var server = try address.listen(.{
            .reuse_port = true,
        });
        defer server.deinit();
        var conn = try server.accept();
        defer conn.stream.close();
        self.buffer = try conn.stream.reader().readAllAlloc(self.allocator, 1024 * 1024);
    }

    fn listen(self: *@This()) !Thread {
        return Thread.spawn(.{}, run, .{self});
    }
};

// const gpa = std.testing.allocator;

pub const TestDataAlloc = struct {
    user_agent: []const u8,
    username: []const u8,
    password: []const u8,
    redirect_uri: []const u8,
    script_client_id: []const u8,
    script_client_secret: []const u8,
    web_client_id: []const u8,
    web_client_secret: []const u8,
    installed_client_id: []const u8,
    device_id: []const u8,

    allocator: Allocator,

    pub fn deinit(self: *const @This()) void {
        freeIfNeeded(self.allocator, self);
    }
};

pub fn testDataAlloc(allocator: Allocator) error{SkipZigTest}!TestDataAlloc {
    const data = try testData();
    // var ret = fromStructAllocIfNeeded(TestDataAlloc, allocator, data) catch @panic("test data error");
    var ret: TestDataAlloc = undefined;
    fieldsCopyDeepPartial(allocator, &ret, &data) catch @panic("test data error");
    ret.allocator = allocator;
    return ret;
}

pub const TestData = struct {
    user_agent: []const u8,
    username: []const u8,
    password: []const u8,
    redirect_uri: []const u8,
    script_client_id: []const u8,
    script_client_secret: []const u8,
    web_client_id: []const u8,
    web_client_secret: []const u8,
    installed_client_id: []const u8,
    device_id: []const u8,
};

pub fn testData() error{SkipZigTest}!TestData {
    const Static = struct {
        var data: ?TestData = null;
        var done: bool = false;
        var mutex: Thread.Mutex = .{};
    };
    if (@atomicLoad(bool, &Static.done, .acquire) == false) {
        testDataSlow(&Static.data, &Static.done, &Static.mutex);
    }
    return Static.data orelse error.SkipZigTest;
}

fn testDataSlow(data: *?TestData, done: *bool, mutex: *Thread.Mutex) void {
    @setCold(true);
    mutex.lock();
    defer mutex.unlock();
    if (done.* == true) return;
    defer @atomicStore(bool, done, true, .release);
    data.* = testDataInit() catch return;
}

fn testDataInit() !TestData {
    @setCold(true);

    var buffer: [1024 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fballoc = fba.allocator();

    const authpath = blk: {
        const cwd = try std.process.getCwdAlloc(fballoc);
        const path = try fmt.allocPrint(fballoc, "{s}{c}.authpath", .{ cwd, fs.path.sep });

        const file = try fs.openFileAbsolute(path, .{});
        defer file.close();
        const ss = try file.reader().readAllAlloc(fballoc, 1024 * 1024);
        const s = mem.trim(u8, ss, " \n");
        if (s[0] == '~') {
            var env_map = try std.process.getEnvMap(fballoc);
            const home = env_map.get("HOME").?;
            break :blk try fmt.allocPrint(fballoc, "{s}{s}", .{ home, s[1..] });
        }
        break :blk s;
    };

    const Data = struct {
        username: []const u8,
        password: []const u8,
        redirect_uri: []const u8,
        script_client_id: []const u8,
        script_client_secret: []const u8,
        web_client_id: []const u8,
        web_client_secret: []const u8,
        installed_client_id: []const u8,
        device_id: []const u8,
    };

    const data = blk: {
        const file = try fs.openFileAbsolute(authpath, .{});
        defer file.close();
        const s = try file.reader().readAllAlloc(fballoc, 1024 * 1024);
        const parsed = try json.parseFromSlice(Data, fballoc, s, .{});
        break :blk parsed.value;
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var td: TestData = undefined;
    try fieldsCopyDeepPartial(allocator, &td, &data);

    // const username = try allocator.dupe(u8, data.username);
    // const password = try allocator.dupe(u8, data.password);
    // const redirect_uri = try allocator.dupe(u8, data.redirect_uri);
    // const script_client_id = try allocator.dupe(u8, data.script_client_id);
    // const script_client_secret = try allocator.dupe(u8, data.script_client_secret);
    // const web_client_id = try allocator.dupe(u8, data.web_client_id);
    // const web_client_secret = try allocator.dupe(u8, data.web_client_secret);
    // const installed_client_id = try allocator.dupe(u8, data.installed_client_id);
    // const device_id = try allocator.dupe(u8, data.device_id);

    const platform = @tagName(@import("builtin").os.tag);
    const version = "0.0.0";
    // const user_agent = try fmt.allocPrint(allocator, "{s}:zig-zraw:{s} (by /u/<{s}>)", .{ platform, version, username });
    td.user_agent = try fmt.allocPrint(allocator, "{s}:zig-zraw:{s} (by /u/<{s}>)", .{ platform, version, td.username });

    // debug.print("{any}\n", .{td});
    return td;

    // return TestData{
    //     .user_agent = user_agent,
    //     .username = username,
    //     .password = password,
    //     .redirect_uri = redirect_uri,
    //     .script_client_id = script_client_id,
    //     .script_client_secret = script_client_secret,
    //     .web_client_id = web_client_id,
    //     .web_client_secret = web_client_secret,
    //     .installed_client_id = installed_client_id,
    //     .device_id = device_id,
    // };
}

// fn fromStruct(comptime T: type, src: anytype) T {
//     return fromStructExtra(T, undefined, src, false) catch unreachable;
// }

// fn fromStructAllocIfNeeded(comptime T: type, allocator: Allocator, src: anytype) !T {
//     return fromStructExtra(T, allocator, src, true);
// }

// fn fromStructExtra(comptime T: type, allocator: Allocator, src: anytype, is_alloc: bool) !T {
//     const Src = switch (@typeInfo(@TypeOf(src))) {
//         .Pointer => |info| blk: {
//             debug.assert(info.size == .One);
//             break :blk info.child;
//         },
//         .Struct => @TypeOf(src),
//         else => unreachable,
//     };
//     const tar_info = @typeInfo(T);
//     var tar: T = undefined;
//     inline for (tar_info.Struct.fields) |field| {
//         blk: {
//             if (field.is_comptime) break :blk;
//             if (!@hasField(Src, field.name)) break :blk;

//             const tar_ptr = &@field(tar, field.name);
//             const src_val = @field(src, field.name);
//             try innerFromStructExtra(allocator, field.type, tar_ptr, src_val, is_alloc);
//         }
//     }
//     return tar;
// }

// fn innerFromStructExtra(allocator: Allocator, comptime TarValue: type, tar_ptr: *TarValue, src_val: anytype, is_alloc: bool) !void {
//     switch (@typeInfo(@TypeOf(src_val))) {
//         .Optional => |_| {
//             if (src_val) |val| {
//                 try innerFromStructExtra(allocator, TarValue, tar_ptr, val, is_alloc);
//             } else if (@typeInfo(TarValue) == .Optional) {
//                 tar_ptr.* = null;
//             }
//         },
//         .Pointer => |info| {
//             debug.assert(info.size == .Slice);
//             tar_ptr.* = if (is_alloc) try allocator.dupe(info.child, src_val) else src_val;
//         },
//         else => tar_ptr.* = src_val,
//     }
// }

pub fn fieldsCopyShallowPartial(tar: anytype, src: anytype) void {
    fieldsCopyWithOptions(undefined, tar, src, .{ .is_partial = true, .is_deep = false }) catch unreachable;
}

pub fn fieldsCopyDeepPartial(allocator: Allocator, tar: anytype, src: anytype) Allocator.Error!void {
    try fieldsCopyWithOptions(allocator, tar, src, .{ .is_partial = true, .is_deep = true });
}

// NOTE: unused
// pub fn fieldsCopyShallow(tar: anytype, src: anytype) void {
//     fieldsCopyWithOptions(undefined, tar, src, .{ .is_partial = false, .is_deep = false }) catch unreachable;
// }

// NOTE: unused
// pub fn fieldsCopyDeep(allocator: Allocator, tar: anytype, src: anytype) Allocator.Error!void {
//     try fieldsCopyWithOptions(allocator, tar, src, .{ .is_partial = false, .is_deep = true });
// }

const FieldsCopyOptions = struct {
    is_partial: bool,
    is_deep: bool,
};

fn fieldsCopyWithOptions(allocator: Allocator, tar: anytype, src: anytype, comptime options: FieldsCopyOptions) Allocator.Error!void {
    const Tar = blk: {
        const info = @typeInfo(@TypeOf(tar));
        debug.assert(info == .Pointer);
        debug.assert(info.Pointer.size == .One);
        debug.assert(info.Pointer.is_const == false);
        const child_info = @typeInfo(info.Pointer.child);
        debug.assert(child_info == .Struct);
        debug.assert(!child_info.Struct.is_tuple);
        break :blk info.Pointer.child;
    };
    const Src = blk: {
        const info = @typeInfo(@TypeOf(src));
        debug.assert(info == .Pointer);
        debug.assert(info.Pointer.size == .One);
        const child_info = @typeInfo(info.Pointer.child);
        debug.assert(child_info == .Struct);
        debug.assert(!child_info.Struct.is_tuple);
        break :blk info.Pointer.child;
    };
    inline for (@typeInfo(Tar).Struct.fields) |tar_field| {
        blk: {
            if (!@hasField(Src, tar_field.name)) {
                if (!options.is_partial) {
                    @compileError(@typeName(Src) ++ "  missing field " ++ tar_field.name);
                }
                break :blk;
            }
            const tar_field_ptr = &@field(tar, tar_field.name);
            const src_field_val = @field(src, tar_field.name);
            try innerFieldsCopyWithOptions(tar_field.type, allocator, tar_field_ptr, src_field_val, options);
        }
    }
}

fn innerFieldsCopyWithOptions(comptime Tar: type, allocator: Allocator, tar_ptr: *Tar, src_val: anytype, comptime options: FieldsCopyOptions) Allocator.Error!void {
    switch (@typeInfo(@TypeOf(src_val))) {
        .Type, .Void, .Bool, .NoReturn, .Int, .Float, .ComptimeFloat, .ComptimeInt, .Enum => {
            tar_ptr.* = src_val;
        },
        .Optional => |_| {
            if (src_val) |val| {
                try innerFieldsCopyWithOptions(Tar, allocator, tar_ptr, val, options);
            } else if (@typeInfo(Tar) == .Optional) {
                tar_ptr.* = null;
            }
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .Slice => {
                    if (!options.is_deep) {
                        tar_ptr.* = src_val;
                        return;
                    }
                    var tar_val = try allocator.alloc(ptr_info.child, src_val.len);
                    for (0..src_val.len) |i| {
                        try innerFieldsCopyWithOptions(ptr_info.child, allocator, &tar_val[i], src_val[i], options);
                    }
                    tar_ptr.* = tar_val;
                },
                // .One => {
                //     var ret = try allocator.create(ptr_info.child);
                //     ret = try clone(allocator, src_val.*);
                //     return ret;
                // },
                else => @panic("unimplemented"),
            }
        },
        else => @panic("unimplemented"),
    }
}

pub fn freeIfNeeded(allocator: Allocator, ptr: anytype) void {
    const ptr_info = @typeInfo(@TypeOf(ptr));
    debug.assert(ptr_info == .Pointer);
    debug.assert(ptr_info.Pointer.size == .One);
    const T = ptr_info.Pointer.child;

    const struct_info = @typeInfo(T);
    debug.assert(struct_info == .Struct);
    debug.assert(struct_info.Struct.is_tuple == false);

    inline for (struct_info.Struct.fields) |field| {
        blk: {
            const maybe_optional = @field(ptr, field.name);
            const value = switch (@typeInfo(field.type)) {
                .Optional => val: {
                    if (maybe_optional) |value| break :val value;
                    break :blk;
                },
                else => maybe_optional,
            };
            switch (@typeInfo(@TypeOf(value))) {
                .Pointer => |info| {
                    switch (info.size) {
                        .Slice => allocator.free(value),
                        else => @panic("unimplemented"),
                    }
                },
                else => {},
            }
        }
    }
}

// NOTE: ununsed
// pub fn clone(allocator: Allocator, value: anytype) Allocator.Error!@TypeOf(value) {
//     switch (@typeInfo(@TypeOf(value))) {
//         .Type, .Void, .Bool, .NoReturn, .Int, .Float, .ComptimeFloat, .ComptimeInt => {
//             return value;
//         },
//         .Optional => |_| {
//             if (value) |val| {
//                 return try clone(allocator, val);
//             }
//             return null;
//         },
//         .Array => |_| @panic("unimplemented"),
//         .Pointer => |ptr_info| {
//             switch (ptr_info.size) {
//                 .Slice => {
//                     var ret = try allocator.alloc(ptr_info.child, value.len);
//                     for (0..value.len) |i| {
//                         ret[i] = try clone(allocator, value[i]);
//                     }
//                     return ret;
//                 },
//                 .One => {
//                     var ret = try allocator.create(ptr_info.child);
//                     ret = try clone(allocator, value.*);
//                     return ret;
//                 },
//                 else => @panic("unimplemented"),
//             }
//         },
//         .Struct => |struct_info| {
//             var ret: @TypeOf(value) = undefined;
//             inline for (struct_info.fields) |field| {
//                 @field(ret, field.name) = try clone(allocator, @field(value, field.name));
//             }
//             return ret;
//         },
//         .Enum => @panic("unimplemented"),
//         .Union => @panic("unimplemented"),
//         else => @panic("unimplemented"),
//     }
//     unreachable;
// }
