//! 日月食的本地情况。
//!
//! 日食：用站心视方向计算日月角距，求本地食甚、C1–C4 接触时刻、类型、食分和食面积比。
//! 月球半径与全球计算和 NASA 一致：C1/C4 用 k₁ = 0.2725076，C2/C3（全食和环食）用 k₂ = 0.2722810。
//! 月食：在地球上各处同时发生，本地只需判断各接触时刻月球的高度。

use super::lunar_eclipse::{EARTH_RADIUS_KM, LunarEclipse};
use super::solar_eclipse::{K_PENUMBRA, K_UMBRA, SolarEclipse};
use super::transit::SUN_RADIUS_KM;
use super::visibility::apparent_altitude;
use super::{DAY, refine_minimum, refine_root};
use crate::astrometry::{self, c2i_matrix, observer_gcrs};
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::Result;
use crate::observer::Observer;
use crate::time::Time;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalSolarKind {
    Partial,
    Annular,
    Total,
}

/// 某地看到的日食。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LocalSolarEclipse {
    pub kind: LocalSolarKind,
    /// 本地食甚（日月角距最小）
    pub maximum: Time,
    /// 食分：全食、环食时为月日视直径比，偏食时为太阳直径被遮的比例
    pub magnitude: f64,
    /// 食面积比：太阳圆面被遮的面积比例
    pub obscuration: f64,
    /// C1 初亏、C2 食既、C3 生光、C4 复圆
    pub contacts: [Option<Time>; 4],
    /// C1、食甚、C4 时太阳的视高度（含折射，度）；负值表示在地平线下
    pub sun_altitude_deg: [f64; 3],
}

impl LocalSolarEclipse {
    /// 全食或环食阶段的持续时间（秒）。
    pub fn central_duration_s(&self) -> Option<f64> {
        match (self.contacts[1], self.contacts[2]) {
            (Some(a), Some(b)) => Some(b.tt_seconds() - a.tt_seconds()),
            _ => None,
        }
    }

    /// 食的某个阶段太阳在地平线上。
    pub fn is_visible(&self) -> bool {
        self.sun_altitude_deg.iter().any(|&h| h > 0.0)
    }
}

#[derive(Debug, Clone, Copy)]
struct Disks {
    separation: f64,
    sun: f64,
    moon_penumbral: f64,
    moon_umbral: f64,
}

/// 计算某地看到的日食；看不到（即使太阳在地平线上也不会被遮）时返回 None。
///
/// `delta_t` 为 None 时用内置 ΔT 模型。
pub fn local_solar(
    eph: &dyn Ephemeris,
    eclipse: &SolarEclipse,
    obs: &Observer,
    delta_t: Option<f64>,
) -> Result<Option<LocalSolarEclipse>> {
    let time_at = |tt: f64| {
        let t = Time::from_tt_seconds(tt);
        delta_t.map_or(t, |dt| t.with_delta_t(dt))
    };
    let tg = eclipse.greatest.tt_seconds();
    let rc2i = c2i_matrix(&eclipse.greatest);

    let disks = |tt: f64| -> Result<Disks> {
        let t = time_at(tt);
        let (pos, vel) = observer_gcrs(&t, obs, &rc2i);
        let (sun, moon) =
            astrometry::direction_pair_from(eph, Body::Sun, Body::Moon, &t, pos, vel)?;
        Ok(Disks {
            separation: sun.apparent.angle_to(moon.apparent),
            sun: (SUN_RADIUS_KM / sun.distance_km).asin(),
            moon_penumbral: (K_PENUMBRA * EARTH_RADIUS_KM / moon.distance_km).asin(),
            moon_umbral: (K_UMBRA * EARTH_RADIUS_KM / moon.distance_km).asin(),
        })
    };

    // 本地食甚在全球食甚前后几小时内
    let (tm, _) = refine_minimum(
        |t| Ok(disks(t)?.separation),
        tg - 0.25 * DAY,
        tg + 0.25 * DAY,
        1e-2,
    )?;
    let m = disks(tm)?;
    if m.separation >= m.sun + m.moon_penumbral {
        return Ok(None);
    }

    let kind = if m.separation < m.moon_umbral - m.sun {
        LocalSolarKind::Total
    } else if m.separation < m.sun - m.moon_umbral {
        LocalSolarKind::Annular
    } else {
        LocalSolarKind::Partial
    };
    let magnitude = match kind {
        LocalSolarKind::Total => m.moon_umbral / m.sun,
        LocalSolarKind::Annular => m.moon_umbral / m.sun,
        LocalSolarKind::Partial => (m.sun + m.moon_penumbral - m.separation) / (2.0 * m.sun),
    };
    let obscuration = overlap_fraction(m.sun, m.moon_penumbral, m.separation);

    let contact = |inner: bool, before: bool| -> Result<Option<Time>> {
        let limit = |d: &Disks| match (inner, kind) {
            (false, _) => d.sun + d.moon_penumbral,
            (true, LocalSolarKind::Total) => d.moon_umbral - d.sun,
            (true, LocalSolarKind::Annular) => d.sun - d.moon_umbral,
            (true, LocalSolarKind::Partial) => f64::NAN,
        };
        if inner && kind == LocalSolarKind::Partial {
            return Ok(None);
        }
        let f = |t: f64| -> Result<f64> {
            let d = disks(t)?;
            Ok(d.separation - limit(&d))
        };
        // 外切到食甚最多约 2.5 小时；内切到食甚最多约 7 分钟（全食）或 6.5 分钟（环食）
        let half = if inner { 0.01 * DAY } else { 0.125 * DAY };
        let center = if before { tm - half } else { tm + half };
        let t = refine_root(f, center, half, half, 1e-2)?;
        Ok(Some(time_at(t)))
    };
    let contacts = [
        contact(false, true)?,
        contact(true, true)?,
        contact(true, false)?,
        contact(false, false)?,
    ];

    let alt = |t: Option<Time>| -> Result<f64> {
        match t {
            Some(t) => Ok(apparent_altitude(eph, Body::Sun, &t, obs)?.to_degrees()),
            None => Ok(f64::NAN),
        }
    };
    let maximum = time_at(tm);
    Ok(Some(LocalSolarEclipse {
        kind,
        maximum,
        magnitude,
        obscuration,
        contacts,
        sun_altitude_deg: [alt(contacts[0])?, alt(Some(maximum))?, alt(contacts[3])?],
    }))
}

/// 某地某时刻看到的日月圆面（日食模拟用）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SolarDiskView {
    pub time: Time,
    /// 月心相对日心的偏移（弧度，天球切平面）：x 向东、y 向北（真赤道）。抬头看时东在左
    pub x: f64,
    pub y: f64,
    /// 太阳和月球的视半径（弧度；月球用 k₁，与 C1、C4 一致）
    pub sun_radius: f64,
    pub moon_radius: f64,
    /// 太阳圆面被遮的面积比例
    pub obscuration: f64,
    /// 太阳视高度（含折射，度）
    pub sun_altitude_deg: f64,
    /// 太阳处天顶方向的位置角（弧度，从北向东量）：把画面转成“天顶朝上”时用
    pub zenith_angle: f64,
}

/// 各时刻在观测地看到的日月圆面（站心视方向，转到 CIRS 定方位）。
pub fn solar_disk_views(
    eph: &dyn Ephemeris,
    obs: &Observer,
    times: &[Time],
) -> Result<Vec<SolarDiskView>> {
    let Some(first) = times.first() else {
        return Ok(Vec::new());
    };
    // GCRS → CIRS 矩阵在几小时内变化可以忽略
    let rc2i = c2i_matrix(first);
    let to_cirs = |v: crate::geometry::Vec3| {
        let mut out = [0.0; 3];
        sofars::vm::rxp(&rc2i, &v.into(), &mut out);
        crate::geometry::Vec3::from(out)
    };
    times
        .iter()
        .map(|t| {
            let (pos, vel) = observer_gcrs(t, obs, &rc2i);
            let (sun, moon) =
                astrometry::direction_pair_from(eph, Body::Sun, Body::Moon, t, pos, vel)?;
            let s = to_cirs(sun.apparent);
            let m = to_cirs(moon.apparent);
            // 太阳处的切平面基：东 = 极 × 太阳方向，北 = 太阳方向 × 东
            let pole = crate::geometry::Vec3::new(0.0, 0.0, 1.0);
            let east = pole.cross(s).unit();
            let north = s.cross(east);
            let w = m.dot(s);
            let (x, y) = (m.dot(east) / w, m.dot(north) / w);
            let sun_r = (SUN_RADIUS_KM / sun.distance_km).asin();
            let moon_r = (K_PENUMBRA * EARTH_RADIUS_KM / moon.distance_km).asin();
            // 天顶位置角（视差角）：tan q = sin H / (tan φ cos δ − sin δ cos H)
            let (uta, utb) = t.ut1_jd_parts();
            let ra = s.y.atan2(s.x);
            let dec = s.z.clamp(-1.0, 1.0).asin();
            let h = sofars::erst::era00(uta, utb) + obs.longitude - ra;
            let q = h
                .sin()
                .atan2(obs.latitude.tan() * dec.cos() - dec.sin() * h.cos());
            Ok(SolarDiskView {
                time: *t,
                x: x.atan(),
                y: y.atan(),
                sun_radius: sun_r,
                moon_radius: moon_r,
                obscuration: overlap_fraction(sun_r, moon_r, sun.apparent.angle_to(moon.apparent)),
                sun_altitude_deg: apparent_altitude(eph, Body::Sun, t, obs)?.to_degrees(),
                zenith_angle: q,
            })
        })
        .collect()
}

/// 两个圆（半径 r1 为太阳、r2 为月球，圆心距 d）的重叠面积占太阳面积的比例。
pub fn overlap_fraction(r1: f64, r2: f64, d: f64) -> f64 {
    use std::f64::consts::PI;
    if d >= r1 + r2 {
        return 0.0;
    }
    if d <= (r1 - r2).abs() {
        let small = r1.min(r2);
        return (small * small) / (r1 * r1);
    }
    let a1 = ((d * d + r1 * r1 - r2 * r2) / (2.0 * d * r1))
        .clamp(-1.0, 1.0)
        .acos();
    let a2 = ((d * d + r2 * r2 - r1 * r1) / (2.0 * d * r2))
        .clamp(-1.0, 1.0)
        .acos();
    let area = r1 * r1 * (a1 - a1.sin() * a1.cos()) + r2 * r2 * (a2 - a2.sin() * a2.cos());
    area / (PI * r1 * r1)
}

/// 月食各接触时刻（P1、U1、U2、U3、U4、P4）及食甚时月球的视高度（含折射，度）。
/// 返回 `[P1, U1, U2, 食甚, U3, U4, P4]`，没有的接触为 NaN。
pub fn lunar_altitudes(
    eph: &dyn Ephemeris,
    eclipse: &LunarEclipse,
    obs: &Observer,
) -> Result<[f64; 7]> {
    let c = &eclipse.contacts;
    let moments = [c[0], c[1], c[2], Some(eclipse.greatest), c[3], c[4], c[5]];
    let mut out = [f64::NAN; 7];
    for (slot, t) in out.iter_mut().zip(moments) {
        if let Some(t) = t {
            *slot = apparent_altitude(eph, Body::Moon, &t, obs)?.to_degrees();
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overlap() {
        assert_eq!(overlap_fraction(1.0, 1.0, 3.0), 0.0);
        assert!((overlap_fraction(1.0, 1.1, 0.0) - 1.0).abs() < 1e-12);
        assert!((overlap_fraction(1.0, 0.5, 0.1) - 0.25).abs() < 1e-12);
        // 两个等大的圆，圆心距等于半径：重叠约 39.1%
        assert!((overlap_fraction(1.0, 1.0, 1.0) - 0.391).abs() < 1e-3);
    }
}
