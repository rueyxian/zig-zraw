const std = @import("std");
const json = std.json;
const mem = std.mem;
const debug = std.debug;
const Allocator = std.mem.Allocator;
const ParseOptions = std.json.ParseOptions;
const ParseError = std.json.ParseError;

const model = @import("../model.zig");
const Int = model.Int;
const Uint = model.Uint;
const Float = model.Float;
const String = model.String;

const Subreddit = model.Subreddit;

pub const Mweb = struct {
    owner: String,
    variant: String,
    experiment_id: Uint,
};

pub const Features = struct {
    modmail_harassment_filter: bool,
    mod_service_mute_writes: bool,
    promoted_trend_blanks: bool,
    show_amp_link: bool,
    chat: bool,
    mweb_link_tab: Mweb,
    is_email_permission_required: bool,
    mod_awards: bool,
    mweb_xpromo_revamp_v3: Mweb,
    mweb_xpromo_revamp_v2: Mweb,
    awards_on_streams: bool,
    mweb_xpromo_modal_listing_click_daily_dismissible_ios: bool,
    chat_subreddit: bool,
    cookie_consent_banner: bool,
    modlog_copyright_removal: bool,
    show_nps_survey: bool,
    do_not_track: bool,
    images_in_comments: bool,
    mod_service_mute_reads: bool,
    chat_user_settings: bool,
    use_pref_account_deployment: bool,
    mweb_xpromo_interstitial_comments_ios: bool,
    mweb_xpromo_modal_listing_click_daily_dismissible_android: bool,
    premium_subscriptions_table: bool,
    mweb_xpromo_interstitial_comments_android: bool,
    crowd_control_for_post: bool,
    mweb_sharing_web_share_api: Mweb,
    chat_group_rollout: bool,
    resized_styles_images: bool,
    noreferrer_to_noopener: bool,
    expensive_coins_package: bool,
};

pub const AccountMe = struct {
    is_employee: bool,
    seen_layout_switch: bool,
    has_visited_new_profile: bool,
    pref_no_profanity: bool,
    has_external_account: bool,
    pref_geopopular: String,
    seen_redesign_modal: bool,
    pref_show_trending: bool,
    subreddit: Subreddit,
    pref_show_presence: bool,
    snoovatar_img: String,
    // snoovatar_size: null,  // NOTE: unimplemented
    // gold_expiration: null,  // NOTE: unimplemented
    has_gold_subscription: bool,
    is_sponsor: bool,
    num_friends: Uint,
    features: Features,
    can_edit_name: bool,
    verified: bool,
    // new_modmail_exists: null,  // NOTE: unimplemented
    pref_autoplay: bool,
    coins: Uint,
    has_paypal_subscription: bool,
    has_subscribed_to_premium: bool,
    id: String,
    has_stripe_subscription: bool,
    oauth_client_id: String,
    can_create_subreddit: bool,
    over_18: bool,
    is_gold: bool,
    is_mod: bool,
    awarder_karma: Uint,
    // // suspension_expiration_utc: null,  // NOTE: unimplemented
    has_verified_email: bool,
    is_suspended: bool,
    pref_video_autoplay: bool,
    in_chat: bool,
    has_android_subscription: bool,
    in_redesign_beta: bool,
    icon_img: String,
    has_mod_mail: bool,
    pref_nightmode: bool,
    awardee_karma: Uint,
    hide_from_robots: bool,
    password_set: bool,
    link_karma: Uint,
    force_password_reset: bool,
    total_karma: Uint,
    seen_give_award_tooltip: bool,
    inbox_count: Uint,
    seen_premium_adblock_modal: bool,
    pref_top_karma_subreddits: bool,
    has_mail: bool,
    pref_show_snoovatar: bool,
    name: String,
    pref_clickgadget: Uint,
    created: Uint,
    gold_creddits: Uint,
    created_utc: Uint,
    has_ios_subscription: bool,
    pref_show_twitter: bool,
    in_beta: bool,
    comment_karma: Uint,
    accept_followers: bool,
    has_subscribed: bool,
    // // linked_identities: [],  // NOTE: unimplemented
    seen_subreddit_chat_ftux: bool,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !@This() {
        const Error = ParseError(@TypeOf(source.*));

        if (try source.next() != .object_begin) {
            return Error.UnexpectedToken;
        }

        var ret: @This() = undefined;

        const info = @typeInfo(@This()).Struct;
        var fields_seen = [_]bool{false} ** info.fields.len;

        while (true) {
            const field_name = switch (try source.next()) {
                .object_end => break,
                .string => |s| s,
                else => return Error.UnexpectedToken,
            };

            inline for (info.fields, 0..) |field, i| {
                if (mem.eql(u8, field_name, field.name)) {
                    debug.assert(field.type != []u8);

                    if (field.type == []const u8) {
                        @field(ret, field.name) = try model.jsonParseAllocString(allocator, source, options);
                    } else {
                        @field(ret, field.name) = try json.innerParse(field.type, allocator, source, options);
                    }

                    // @field(ret, field.name) = try json.innerParse(field.type, allocator, source, options);

                    fields_seen[i] = true;
                    break;
                }
            } else {
                if (options.ignore_unknown_fields) {
                    try source.skipValue();
                } else {
                    return error.UnknownField;
                }
            }
        }
        try model.fillDefaultStructValues(@This(), &ret, &fields_seen);
        return ret;
    }
};
