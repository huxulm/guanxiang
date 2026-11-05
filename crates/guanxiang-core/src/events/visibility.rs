//! 本地可见性。
//!
//! 事件本身按地心计算；这里判断某地在某一时刻能否看到：目标高于给定高度，且（可选）太阳低于给定高度。
//! 高度角用站心视位置加大气折射（标准大气 1010 hPa、10 °C）。

use crate::astrometry::{self, refraction};
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::Result;
use crate::observer::Observer;
use crate::time::Time;

/// 可见性条件。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct VisibilityFilter {
    pub observer: Observer,
    /// 目标的最低视高度角（弧度）
    pub min_altitude: f64,
    /// 太阳的最高视高度角（弧度）。None 表示不限制（例如白天的凌日）
    pub max_sun_altitude: Option<f64>,
}

/// 视高度角（含折射，弧度）。
pub fn apparent_altitude(eph: &dyn Ephemeris, body: Body, t: &Time, obs: &Observer) -> Result<f64> {
    let h = astrometry::topocentric(eph, body, t, obs)?
        .horizontal
        .altitude;
    Ok(h + refraction(h, 1010.0, 10.0))
}

impl VisibilityFilter {
    /// 所有 `bodies` 都高于最低高度，且满足太阳高度限制时返回 true。
    /// 目标是太阳时不检查太阳高度限制。
    pub fn is_visible(&self, eph: &dyn Ephemeris, bodies: &[Body], t: &Time) -> Result<bool> {
        for &b in bodies {
            if apparent_altitude(eph, b, t, &self.observer)? < self.min_altitude {
                return Ok(false);
            }
        }
        if let Some(max_sun) = self.max_sun_altitude
            && !bodies.contains(&Body::Sun)
            && apparent_altitude(eph, Body::Sun, t, &self.observer)? > max_sun
        {
            return Ok(false);
        }
        Ok(true)
    }
}
