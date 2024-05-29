const std = @import("std");

const Authorizer = @import("auth.zig").Authorizer;

const Token = struct {
    authorizer: Authorizer,
};
