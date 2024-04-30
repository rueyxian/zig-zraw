/// - t1_ - Comment
/// - t2_ - Account
/// - t3_ - Link
/// - t4_ - Message
/// - t5_ - Subreddit
/// - t6_ - Award
/// - t8_ - PromoCampaign
pub const Kind = union(enum) {
    comment: []const u8,
    account: []const u8,
    link: []const u8,
    message: []const u8,
    subreddit: []const u8,
    award: []const u8,
    promo_campaign: []const u8,
};

pub fn BaseData(Data: type) type {
    return struct {
        kind: Kind,
        data: Data,
    };
}
