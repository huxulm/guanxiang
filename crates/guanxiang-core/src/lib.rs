//! 观象（Guanxiang）核心库。
//!
//! 依赖方向：`app → 桥接层 → core`，`cli → core`。本库不依赖上层，也不做网络请求（D5、D6）。
//! 公开 API 只使用本库自己的类型，不暴露 anise / hifitime / nalgebra 的类型，
//! 这样以后替换星历后端（例如自写 SPK Type 2 读取器）不影响上层。

pub mod body;
pub mod ephemeris;
pub mod error;
pub mod geometry;
pub mod search;
pub mod time;

pub use body::Body;
pub use ephemeris::{AniseEphemeris, Ephemeris};
pub use error::{Error, Result};
pub use geometry::Vec3;
pub use time::Tdb;
