pub const domain = "https://www.reddit.com";
pub const doman_oauth = "https://oauth.reddit.com";

pub const authorize = struct {
    pub const path = "/api/v1/authorize";
    pub const url = domain ++ path;
};

pub const access_token = struct {
    pub const path = "/api/v1/access_token";
    pub const url = domain ++ path;
};

pub const list_links = struct {
    // pub
};
