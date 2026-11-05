//! 月食（地心）。
//!
//! 几何：以地心为观测点，月球和太阳都取**视方向**，影轴为视太阳方向的反方向（与《天文年历补编》
//! 和 NASA 星表一致）。
//!
//! 理由：在随地球运动的参考系里，经过地球的太阳光线方向是加了光行差的视太阳方向，所以地影轴
//! 应取视太阳的反向；月球的天体测量方向含 BCRS 光行时修正（约 20″），只有和光行差一起用（即视方向）
//! 才等于月球真实的地心方向。两项各约 20″，若都不加，食甚时刻会晚约 80 秒。
//!
//! 地影半径（角度，地心看）：
//!
//! - Chauvenet：ρ = 1.02 × (π☾ + π☉ ± s☉)，天文年历长期使用的 2% 放大；
//! - Danjon（默认）：ρ = 0.99834 × (1 + 1/85) × π☾ + π☉ ± s☉，只放大地球半径（NASA 五千年星表、法国年历使用）。
//!
//! 食分：半影食分 = (ρp + s☾ − γ) / (2 s☾)，本影食分 = (ρu + s☾ − γ) / (2 s☾)，γ 为月心离影轴的角距。

use super::longitude::{self, Aspect};
use super::{DAY, Span, coarse_lon_lat, refine_minimum, refine_root};
use crate::astrometry;
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::Result;
use crate::geometry::Vec3;
use crate::time::Time;

/// 地球赤道半径（km，WGS84）
pub const EARTH_RADIUS_KM: f64 = 6378.137;
/// 月球平均半径（km），k = 0.2725076
pub const MOON_RADIUS_KM: f64 = 0.272_507_6 * EARTH_RADIUS_KM;
/// 太阳半径（km），由 1 AU 处 959.63″ 换算
pub use super::transit::SUN_RADIUS_KM;

/// 地影放大模型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ShadowModel {
    /// 整体放大 2%（天文年历长期使用）
    Chauvenet,
    /// 地球半径放大 1/85（Danjon；NASA 五千年月食星表、法国年历使用）。
    /// 与 NASA 21 世纪月食星表对比，类型和次数完全一致，故作默认。
    #[default]
    Danjon,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LunarEclipseKind {
    Penumbral,
    Partial,
    Total,
}

/// 一次月食。接触：P1 半影食始、U1 初亏、U2 食既、U3 生光、U4 复圆、P4 半影食终。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LunarEclipse {
    pub kind: LunarEclipseKind,
    /// 食甚（月心离影轴最近）
    pub greatest: Time,
    /// 食甚时月心离影轴的距离（地球赤道半径），月球在影轴以北为正（与 NASA 星表相同）
    pub gamma: f64,
    pub penumbral_magnitude: f64,
    pub umbral_magnitude: f64,
    /// P1、U1、U2、U3、U4、P4；没有的为 None
    pub contacts: [Option<Time>; 6],
}

/// 某一时刻的月食几何量（弧度）。
#[derive(Debug, Clone, Copy)]
struct Geometry {
    /// 月心离影轴的角距
    separation: f64,
    penumbra: f64,
    umbra: f64,
    moon_semidiameter: f64,
    /// 月心离影轴的距离（地球半径），带符号
    gamma: f64,
}

fn geometry(eph: &dyn Ephemeris, tt: f64, model: ShadowModel) -> Result<Geometry> {
    let t = Time::from_tt_seconds(tt);
    let (moon, sun) = astrometry::geocentric_direction_pair(eph, Body::Moon, Body::Sun, &t)?;
    let axis: Vec3 = -sun.apparent;
    let separation = moon.apparent.angle_to(axis);

    let (dm, ds) = (moon.distance_km, sun.distance_km);
    let pi_m = (EARTH_RADIUS_KM / dm).asin();
    let pi_s = (EARTH_RADIUS_KM / ds).asin();
    let s_s = (SUN_RADIUS_KM / ds).asin();
    let s_m = (MOON_RADIUS_KM / dm).asin();
    let (penumbra, umbra) = match model {
        ShadowModel::Chauvenet => (1.02 * (pi_m + pi_s + s_s), 1.02 * (pi_m + pi_s - s_s)),
        ShadowModel::Danjon => {
            let p = 0.998_340 * (1.0 + 1.0 / 85.0) * pi_m + pi_s;
            (p + s_s, p - s_s)
        }
    };
    // 赤道坐标的 z 轴近似指向北天极，用来定 γ 的符号
    let sign = if moon.apparent.z >= axis.z { 1.0 } else { -1.0 };
    Ok(Geometry {
        separation,
        penumbra,
        umbra,
        moon_semidiameter: s_m,
        gamma: sign * dm * separation.sin() / EARTH_RADIUS_KM,
    })
}

/// 搜索 `span` 内的月食。
pub fn search(eph: &dyn Ephemeris, span: Span, model: ShadowModel) -> Result<Vec<LunarEclipse>> {
    let mut out = Vec::new();
    let step = longitude::default_step_days(Body::Moon, Body::Sun);
    for bracket in
        longitude::coarse_brackets(eph, Body::Moon, Body::Sun, Aspect::Opposition, span, step)?
    {
        let tc = longitude::coarse_root(eph, Body::Moon, Body::Sun, Aspect::Opposition, bracket)?;
        // 剪枝：望时月球黄纬超过 1.7° 不会有月食（半影食限约 1.6°）
        let (_, beta) = coarse_lon_lat(eph, Body::Moon, tc)?;
        if beta.abs() > 1.7f64.to_radians() {
            continue;
        }
        if let Some(e) = refine(eph, tc, model)? {
            if span.contains(e.greatest.tt_seconds()) {
                out.push(e);
            }
        }
    }
    Ok(out)
}

/// 在望附近求食甚、食分和接触时刻；不发生月食时返回 None。
fn refine(eph: &dyn Ephemeris, tc: f64, model: ShadowModel) -> Result<Option<LunarEclipse>> {
    let (tg, _) = refine_minimum(
        |t| Ok(geometry(eph, t, model)?.separation),
        tc - 0.3 * DAY,
        tc + 0.3 * DAY,
        1e-2,
    )?;
    let g = geometry(eph, tg, model)?;
    let pen_mag = (g.penumbra + g.moon_semidiameter - g.separation) / (2.0 * g.moon_semidiameter);
    let um_mag = (g.umbra + g.moon_semidiameter - g.separation) / (2.0 * g.moon_semidiameter);
    if pen_mag <= 0.0 {
        return Ok(None);
    }
    let kind = if um_mag >= 1.0 {
        LunarEclipseKind::Total
    } else if um_mag > 0.0 {
        LunarEclipseKind::Partial
    } else {
        LunarEclipseKind::Penumbral
    };

    // 接触：月心角距 = 影半径 ± 月半径。半影月食最长约 6 小时，每侧取 0.25 天的区间足够
    let contact = |offset: fn(&Geometry) -> f64, before: bool| -> Result<Option<Time>> {
        if offset(&g) <= g.separation {
            return Ok(None);
        }
        let f = |t: f64| -> Result<f64> {
            let x = geometry(eph, t, model)?;
            Ok(x.separation - offset(&x))
        };
        let center = if before {
            tg - 0.125 * DAY
        } else {
            tg + 0.125 * DAY
        };
        let t = refine_root(f, center, 0.125 * DAY, 0.125 * DAY, 1e-2)?;
        Ok(Some(Time::from_tt_seconds(t)))
    };
    let outer_p: fn(&Geometry) -> f64 = |x| x.penumbra + x.moon_semidiameter;
    let outer_u: fn(&Geometry) -> f64 = |x| x.umbra + x.moon_semidiameter;
    let inner_u: fn(&Geometry) -> f64 = |x| x.umbra - x.moon_semidiameter;
    let contacts = [
        contact(outer_p, true)?,
        contact(outer_u, true)?,
        contact(inner_u, true)?,
        contact(inner_u, false)?,
        contact(outer_u, false)?,
        contact(outer_p, false)?,
    ];

    Ok(Some(LunarEclipse {
        kind,
        greatest: Time::from_tt_seconds(tg),
        gamma: g.gamma,
        penumbral_magnitude: pen_mag,
        umbral_magnitude: um_mag,
        contacts,
    }))
}
