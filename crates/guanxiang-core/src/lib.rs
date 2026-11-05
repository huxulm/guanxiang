//! 观象（Guanxiang）核心库。
//!
//! 依赖方向：`app → 桥接层 → core`，`cli → core`。本库不依赖上层，也不做网络请求（D5、D6）。
//! 公开 API 只使用本库自己的类型，不暴露 anise / hifitime / nalgebra 的类型，
//! 这样以后替换星历后端（例如自写 SPK Type 2 读取器）不影响上层。

pub mod astrometry;
pub mod body;
pub mod delta_t;
#[allow(clippy::approx_constant)] // 表中的 6.28 等是 ΔT 数据，不是 τ
mod delta_t_table;
pub mod ephemeris;
pub mod error;
pub mod geometry;
pub mod observer;
pub mod search;
pub mod time;

pub use astrometry::{Equatorial, Horizontal, Place, TopocentricPlace};
pub use body::Body;
pub use ephemeris::{AniseEphemeris, Ephemeris};
pub use error::{Error, Result};
pub use geometry::Vec3;
pub use observer::Observer;
pub use time::{DateTime, Tdb, Time};
