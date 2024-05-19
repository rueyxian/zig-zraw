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

pub const Features = struct {

    //         "modmail_harassment_filter": true,
    //         "mod_service_mute_writes": true,
    //         "promoted_trend_blanks": true,
    //         "show_amp_link": true,
    //         "chat": true,
    //         "mweb_link_tab": {
    //             "owner": "growth",
    //             "variant": "control_2",
    //             "experiment_id": 404
    //         },
    //         "is_email_permission_required": false,
    //         "mod_awards": true,
    //         "mweb_xpromo_revamp_v3": {
    //             "owner": "growth",
    //             "variant": "treatment_3",
    //             "experiment_id": 480
    //         },
    //         "mweb_xpromo_revamp_v2": {
    //             "owner": "growth",
    //             "variant": "control_1",
    //             "experiment_id": 457
    //         },
    //         "awards_on_streams": true,
    //         "mweb_xpromo_modal_listing_click_daily_dismissible_ios": true,
    //         "chat_subreddit": true,
    //         "cookie_consent_banner": true,
    //         "modlog_copyright_removal": true,
    //         "show_nps_survey": true,
    //         "do_not_track": true,
    //         "images_in_comments": true,
    //         "mod_service_mute_reads": true,
    //         "chat_user_settings": true,
    //         "use_pref_account_deployment": true,
    //         "mweb_xpromo_interstitial_comments_ios": true,
    //         "mweb_xpromo_modal_listing_click_daily_dismissible_android": true,
    //         "premium_subscriptions_table": true,
    //         "mweb_xpromo_interstitial_comments_android": true,
    //         "crowd_control_for_post": true,
    //         "mweb_sharing_web_share_api": {
    //             "owner": "growth",
    //             "variant": "control_1",
    //             "experiment_id": 314
    //         },
    //         "chat_group_rollout": true,
    //         "resized_styles_images": true,
    //         "noreferrer_to_noopener": true,
    //         "expensive_coins_package": true

};

pub const SubReddit = struct {

    //         "default_set": false,
    //         "user_is_contributor": false,
    //         "banner_img": "",
    //         "restrict_posting": true,
    //         "user_is_banned": false,
    //         "free_form_reports": true,
    //         "community_icon": null,
    //         "show_media": true,
    //         "icon_color": "#94B3FF",
    //         "user_is_muted": null,
    //         "display_name": "u_babywhisky",
    //         "header_img": null,
    //         "title": "",
    //         "coins": 0,
    //         "previous_names": [],
    //         "over_18": false,
    //         "icon_size": [
    //             256,
    //             256
    //         ],
    //         "primary_color": "",
    //         "icon_img": "https://www.redditstatic.com/avatars/defaults/v2/avatar_default_6.png",
    //         "description": "",
    //         "allowed_media_in_comments": [],
    //         "submit_link_label": "",
    //         "header_size": null,
    //         "restrict_commenting": false,
    //         "subscribers": 0,
    //         "submit_text_label": "",
    //         "is_default_icon": true,
    //         "link_flair_position": "",
    //         "display_name_prefixed": "u/babywhisky",
    //         "key_color": "",
    //         "name": "t5_bbweft",
    //         "is_default_banner": true,
    //         "url": "/user/babywhisky/",
    //         "quarantine": false,
    //         "banner_size": null,
    //         "user_is_moderator": true,
    //         "accept_followers": false,
    //         "public_description": "",
    //         "link_flair_enabled": false,
    //         "disable_contributor_requests": false,
    //         "subreddit_type": "user",
    //         "user_is_subscriber": false
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
    subreddit: SubReddit,
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

// {
//     "is_employee": false,
//     "seen_layout_switch": false,
//     "has_visited_new_profile": false,
//     "pref_no_profanity": true,
//     "has_external_account": false,
//     "pref_geopopular": "",
//     "seen_redesign_modal": false,
//     "pref_show_trending": true,
//     "subreddit": {
//         "default_set": false,
//         "user_is_contributor": false,
//         "banner_img": "",
//         "restrict_posting": true,
//         "user_is_banned": false,
//         "free_form_reports": true,
//         "community_icon": null,
//         "show_media": true,
//         "icon_color": "#94B3FF",
//         "user_is_muted": null,
//         "display_name": "u_babywhisky",
//         "header_img": null,
//         "title": "",
//         "coins": 0,
//         "previous_names": [],
//         "over_18": false,
//         "icon_size": [
//             256,
//             256
//         ],
//         "primary_color": "",
//         "icon_img": "https://www.redditstatic.com/avatars/defaults/v2/avatar_default_6.png",
//         "description": "",
//         "allowed_media_in_comments": [],
//         "submit_link_label": "",
//         "header_size": null,
//         "restrict_commenting": false,
//         "subscribers": 0,
//         "submit_text_label": "",
//         "is_default_icon": true,
//         "link_flair_position": "",
//         "display_name_prefixed": "u/babywhisky",
//         "key_color": "",
//         "name": "t5_bbweft",
//         "is_default_banner": true,
//         "url": "/user/babywhisky/",
//         "quarantine": false,
//         "banner_size": null,
//         "user_is_moderator": true,
//         "accept_followers": false,
//         "public_description": "",
//         "link_flair_enabled": false,
//         "disable_contributor_requests": false,
//         "subreddit_type": "user",
//         "user_is_subscriber": false
//     },
//     "pref_show_presence": true,
//     "snoovatar_img": "",
//     "snoovatar_size": null,
//     "gold_expiration": null,
//     "has_gold_subscription": false,
//     "is_sponsor": false,
//     "num_friends": 0,
//     "features": {
//         "modmail_harassment_filter": true,
//         "mod_service_mute_writes": true,
//         "promoted_trend_blanks": true,
//         "show_amp_link": true,
//         "chat": true,
//         "mweb_link_tab": {
//             "owner": "growth",
//             "variant": "control_2",
//             "experiment_id": 404
//         },
//         "is_email_permission_required": false,
//         "mod_awards": true,
//         "mweb_xpromo_revamp_v3": {
//             "owner": "growth",
//             "variant": "treatment_3",
//             "experiment_id": 480
//         },
//         "mweb_xpromo_revamp_v2": {
//             "owner": "growth",
//             "variant": "control_1",
//             "experiment_id": 457
//         },
//         "awards_on_streams": true,
//         "mweb_xpromo_modal_listing_click_daily_dismissible_ios": true,
//         "chat_subreddit": true,
//         "cookie_consent_banner": true,
//         "modlog_copyright_removal": true,
//         "show_nps_survey": true,
//         "do_not_track": true,
//         "images_in_comments": true,
//         "mod_service_mute_reads": true,
//         "chat_user_settings": true,
//         "use_pref_account_deployment": true,
//         "mweb_xpromo_interstitial_comments_ios": true,
//         "mweb_xpromo_modal_listing_click_daily_dismissible_android": true,
//         "premium_subscriptions_table": true,
//         "mweb_xpromo_interstitial_comments_android": true,
//         "crowd_control_for_post": true,
//         "mweb_sharing_web_share_api": {
//             "owner": "growth",
//             "variant": "control_1",
//             "experiment_id": 314
//         },
//         "chat_group_rollout": true,
//         "resized_styles_images": true,
//         "noreferrer_to_noopener": true,
//         "expensive_coins_package": true
//     },
//     "can_edit_name": false,
//     "verified": true,
//     "new_modmail_exists": null,
//     "pref_autoplay": false,
//     "coins": 0,
//     "has_paypal_subscription": false,
//     "has_subscribed_to_premium": false,
//     "id": "yj8fveo1a",
//     "has_stripe_subscription": false,
//     "oauth_client_id": "Qb_qUNyGmn25WLAJ552QLQ",
//     "can_create_subreddit": true,
//     "over_18": false,
//     "is_gold": false,
//     "is_mod": false,
//     "awarder_karma": 0,
//     "suspension_expiration_utc": null,
//     "has_verified_email": true,
//     "is_suspended": false,
//     "pref_video_autoplay": false,
//     "in_chat": true,
//     "has_android_subscription": false,
//     "in_redesign_beta": true,
//     "icon_img": "https://www.redditstatic.com/avatars/defaults/v2/avatar_default_6.png",
//     "has_mod_mail": false,
//     "pref_nightmode": false,
//     "awardee_karma": 0,
//     "hide_from_robots": true,
//     "password_set": true,
//     "link_karma": 1,
//     "force_password_reset": false,
//     "total_karma": 1,
//     "seen_give_award_tooltip": false,
//     "inbox_count": 0,
//     "seen_premium_adblock_modal": false,
//     "pref_top_karma_subreddits": false,
//     "has_mail": false,
//     "pref_show_snoovatar": false,
//     "name": "babywhisky",
//     "pref_clickgadget": 5,
//     "created": 1713405194.0,
//     "gold_creddits": 0,
//     "created_utc": 1713405194.0,
//     "has_ios_subscription": false,
//     "pref_show_twitter": false,
//     "in_beta": false,
//     "comment_karma": 0,
//     "accept_followers": false,
//     "has_subscribed": true,
//     "linked_identities": [],
//     "seen_subreddit_chat_ftux": false
// }
