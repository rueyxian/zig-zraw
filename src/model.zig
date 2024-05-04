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

pub const SrDetail = struct {
    default_set: bool,
    banner_img: String,
    // allowed_media_in_comments: ,
    user_is_banned: Bool,
    free_form_reports: Bool,
    community_icon: String,
    show_media: Bool,
    description: String,
    // user_is_muted: ,
    display_name: String,
    // // header_img:
    title: String,
    // previous_names:
    user_is_moderator: bool,
    over_18: bool,
    icon_size: []const Uint,
    primary_color: String,
    icon_img: String,
    icon_color: String,
    submit_link_label: String,
    header_size: ?Uint,
    restrict_posting: bool,
    restrict_commenting: bool,
    subscribers: Uint,
    submit_text_label: String,
    link_flair_position: String,
    display_name_prefixed: String,
    key_color: String,
    name: String,
    created: Uint,
    url: String,
    quarantine: Bool,
    created_utc: Uint,
    // banner_size: ?
    user_is_contributor: Bool,
    accept_followers: Bool,
    public_description: String,
    link_flair_enabled: Bool,
    disable_contributor_requests: Bool,
    subreddit_type: String,
    user_is_subscriber: Bool,
};

pub const Listing = struct {
    before: ?String,
    after: ?String,
    dist: ?Uint,
    modhash: ?String,
    geo_filter: String,
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

    // sr_detail: ?SrDetail,
};

pub const Comment = struct {
    id: String,
};
