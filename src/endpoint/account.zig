const std = @import("std");
const debug = std.debug;
const Method = std.http.Method;

const domain_oauth = @import("../api.zig").domain_oauth;

pub const Me = struct {
    pub const endpoint = domain_oauth ++ "api/v1/me";
    pub const method = Method.GET;
    pub const Model = struct {
        //
    };
};
