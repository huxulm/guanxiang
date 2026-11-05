use crate::body::Body;

pub type Result<T, E = Error> = std::result::Result<T, E>;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("无法加载星历：{0}")]
    EphemerisLoad(String),

    #[error("星历查询失败（{target} 相对 {center}）：{message}")]
    EphemerisQuery {
        target: Body,
        center: Body,
        message: String,
    },

    #[error("未知天体：{0}")]
    UnknownBody(String),

    #[error("搜索区间无效：{0}")]
    InvalidBracket(&'static str),
}
