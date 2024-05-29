const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;

// const CowString = @import("CowString");

const model = @import("../model.zig");
const api = @import("../api.zig");

const domain_oauth = api.domain_oauth;

pub const SubmitLink = struct {
    title: []const u8,
    kind: []const u8,
    sr: []const u8,
    resubmit: bool = true,
    sendreplies: bool = true,
    nsfw: ?bool = null,
    spoiler: ?bool = null,

    pub const path = "/api/submit";
    pub const url_oauth = api.domain_oauth ++ path;

    pub const method = Method.POST;
    pub const Model: type = struct {
        // TODO
    };

    pub const allocFullUrlOauth = api.getAllocFullUrlFn(
        @This(),
        domain_oauth ++ "/api/submit",
        .{},
        .{},
    );
    pub const allocPayload = api.getAllocPayloadFn(
        @This(),
        api.fieldNames(@This(), .{}),
    );
};
