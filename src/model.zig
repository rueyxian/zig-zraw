pub const Bool = bool;
pub const Int = i64;
pub const Uint = u64;
pub const Float = f64;
pub const String = []const u8;

pub fn Thing(comptime T: type) type {
    return struct {
        kind: String,
        data: T,
    };
}

pub const Listing = struct {
    after: ?String,
    dist: ?Uint,
    modhash: ?String,
    children: []const Thing(Link),
};

pub const Link = struct {
    id: String,
    name: String,
    url: String,
    permalink: String,
    over_18: Bool,

    created: Uint,
    created_utc: Uint,

    approved_at_utc: ?Uint,
    approved_by: ?String,

    subreddit: String,
    subreddit_id: String,
    domain: String,

    num_comments: Uint,
    num_crossposts: Uint,
    ups: Uint,
    downs: Uint,
    score: Uint,
    upvote_ratio: Float,

    title: String,
    selftext: ?String,
    selftext_html: ?String,

    author: String,
    author_fullname: String,

    suggested_sort: ?String,
};
