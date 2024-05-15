const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const io = std.io;
const fmt = std.fmt;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

pub const TestOptions = struct {
    app_id: []const u8,
    app_pass: []const u8,
    user_id: []const u8,
    user_pass: []const u8,
    user_agent: []const u8,
};

pub fn testOptions() ?TestOptions {
    const Static = struct {
        var data: ?TestOptions = null;
        var done: bool = false;
        var mutex: Thread.Mutex = .{};
    };
    if (@atomicLoad(bool, &Static.done, .acquire) == false) {
        testOptionsSlow(&Static.data, &Static.done, &Static.mutex);
    }
    return Static.data;
}

fn testOptionsSlow(data: *?TestOptions, done: *bool, mutex: *Thread.Mutex) void {
    @setCold(true);
    mutex.lock();
    defer mutex.unlock();
    if (done.* == true) return;
    defer @atomicStore(bool, done, true, .release);
    data.* = testOpitonsInit() catch return;
}

fn testOpitonsInit() !TestOptions {
    @setCold(true);
    var cwd_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    const cwd = std.process.getCwd(&cwd_buf) catch unreachable;

    var path_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path_fbs = io.fixedBufferStream(&path_buf);
    try path_fbs.writer().writeAll(cwd);
    try path_fbs.writer().writeByte(fs.path.sep);
    try path_fbs.writer().writeAll(".authpath");

    const file_authpath = try fs.openFileAbsolute(path_fbs.getWritten(), .{});
    defer file_authpath.close();

    var content_path_buf: [fs.MAX_PATH_BYTES * 2 + 128]u8 = undefined;
    const content_path = content_path_buf[0..try file_authpath.reader().readAll(&content_path_buf)];
    var it_path = mem.tokenizeScalar(u8, std.mem.trim(u8, content_path, ""), '\n');

    var env_map = try std.process.getEnvMap(std.heap.page_allocator);
    defer env_map.deinit();
    const home = env_map.get("HOME").?;

    var path_auth_app_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path_auth_user_buf: [fs.MAX_PATH_BYTES]u8 = undefined;

    const path_auth_app = blk: {
        const path = it_path.next().?;
        var fbs = io.fixedBufferStream(&path_auth_app_buf);
        if (path[0] == '~') {
            try fbs.writer().writeAll(home);
            try fbs.writer().writeAll(path[1..]);
        } else {
            try fbs.writer().writeAll(path);
        }
        break :blk fbs.getWritten();
    };
    const path_auth_user = blk: {
        const path = it_path.next().?;
        var fbs = io.fixedBufferStream(&path_auth_user_buf);
        if (path[0] == '~') {
            try fbs.writer().writeAll(home);
            try fbs.writer().writeAll(path[1..]);
        } else {
            try fbs.writer().writeAll(path);
        }
        break :blk fbs.getWritten();
    };

    var opts: TestOptions = undefined;

    const allocator = std.heap.page_allocator;
    var buf: [128]u8 = undefined;
    {
        const file = try std.fs.openFileAbsolute(path_auth_app, .{});
        defer file.close();
        const content = buf[0..try file.read(&buf)];
        var it = std.mem.tokenizeScalar(u8, mem.trim(u8, content, " "), '\n');
        opts.app_id = try allocator.dupe(u8, it.next().?);
        opts.app_pass = try allocator.dupe(u8, it.next().?);
    }
    {
        const file = try std.fs.openFileAbsolute(path_auth_user, .{});
        defer file.close();
        const content = buf[0..try file.read(&buf)];
        var it = std.mem.tokenizeScalar(u8, mem.trim(u8, content, " "), '\n');
        opts.user_id = try allocator.dupe(u8, it.next().?);
        opts.user_pass = try allocator.dupe(u8, it.next().?);
    }

    const platform = @tagName(@import("builtin").os.tag);
    const version = "0.0.0";
    opts.user_agent = try fmt.allocPrint(allocator, "{s}:zig-zraw:{s} (by /u/<{s}>)", .{ platform, version, opts.user_id });
    return opts;
}
