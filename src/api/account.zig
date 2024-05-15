const std = @import("std");
const debug = std.debug;
const Method = std.http.Method;

const model = @import("../model/account.zig");
const api = @import("../api.zig");
const domain_oauth = api.domain_oauth;
const Thing = model.Thing;

pub const AccountMe = struct {
    pub const url = domain_oauth ++ "api/v1/me";
    pub const method = Method.GET;
    pub const Model = model.AccountMe;
    pub usingnamespace api.MixinContexFetch(@This());
};
