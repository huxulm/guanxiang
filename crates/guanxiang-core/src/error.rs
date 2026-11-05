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

    #[error("时间无效：{0}")]
    InvalidTime(String),

    #[error("观测者位置无效：{0}")]
    InvalidObserver(String),

    #[error("无法计算：{0}")]
    Unsupported(&'static str),

    #[error("星表格式错误：{0}")]
    Catalog(String),

    #[error("搜索区间无效：{0}")]
    InvalidBracket(&'static str),
}
