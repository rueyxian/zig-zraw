const std = @import("std");
const debug = std.debug;

const zraw = @import("root.zig");

pub fn main() !void {
    //
    const ctx = zraw.api.ListingNew("zig");
    _ = ctx; // autofix
    // ctx.writeParamValueSrDetail(, )

    const auth = zraw.ConfidentialAuthenticator{
        .client_id = "asdf",
        .client_secret = "oiurq",
    };

    debug.print("{}\n", .{auth.authenticator().getClientType()});
    debug.print("{s}\n", .{try auth.authenticator().allocBasicAuth(std.heap.page_allocator)});
}
