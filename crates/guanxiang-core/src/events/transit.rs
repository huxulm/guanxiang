//! 水星、金星凌日（地心）。
//!
//! 只在下合附近计算：先用几何位置找下合并按黄纬差剪枝，再用视位置求最小角距和四个接触时刻。
//! 半径取 NASA（Espenak）凌日星表的值：太阳 959.63″（1 AU 处），水星 2439.7 km，金星 6051.8 km。

use super::longitude::{self, Aspect};
use super::{DAY, Span, apparent_pair, coarse_lon_lat, geometric, refine_minimum, refine_root};
use crate::astrometry::AU_KM;
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::{Error, Result};
use crate::time::Time;

const ARCSEC: f64 = 1.0 / 206_264.806_247_096_36;
/// 太阳半径（km），由 1 AU 处 959.63″ 换算
pub const SUN_RADIUS_KM: f64 = 959.63 * ARCSEC * AU_KM;
pub const MERCURY_RADIUS_KM: f64 = 2439.7;
pub const VENUS_RADIUS_KM: f64 = 6051.8;

/// 一次凌日。接触时刻：外切入（I）、内切入（II）、内切出（III）、外切出（IV）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Transit {
    pub planet: Body,
    /// I、II、III、IV；掠凌（只有外切）时 II、III 为 None
    pub contacts: [Option<Time>; 4],
    /// 凌甚（角距最小）
    pub greatest: Time,
    /// 凌甚时行星中心与日心的视角距（弧度）
    pub min_separation: f64,
    /// 凌甚时太阳视半径（弧度）
    pub sun_semidiameter: f64,
    /// 凌甚时行星视半径（弧度）
    pub planet_semidiameter: f64,
}

impl Transit {
    /// 行星整个圆面进入过日面以内
    pub fn is_full(&self) -> bool {
        self.contacts[1].is_some()
    }
}

fn planet_radius(planet: Body) -> Result<f64> {
    match planet {
        Body::Mercury => Ok(MERCURY_RADIUS_KM),
        Body::Venus => Ok(VENUS_RADIUS_KM),
        _ => Err(Error::Unsupported("凌日只支持水星和金星")),
    }
}

/// 搜索 `planet`（水星或金星）在 `span` 内的凌日。
pub fn search(eph: &dyn Ephemeris, planet: Body, span: Span) -> Result<Vec<Transit>> {
    let radius = planet_radius(planet)?;
    let mut out = Vec::new();

    // 黄经差每天最多变化约 4°，两次合相隔一个多月，4 天步长足够
    for bracket in
        longitude::coarse_brackets(eph, planet, Body::Sun, Aspect::Conjunction, span, 4.0)?
    {
        let tc = longitude::coarse_root(eph, planet, Body::Sun, Aspect::Conjunction, bracket)?;

        // 剪枝 1：只要下合（行星比太阳近）
        if geometric(eph, planet, tc)?.norm() >= geometric(eph, Body::Sun, tc)?.norm() {
            continue;
        }
        // 剪枝 2：黄纬差大于 0.5° 不可能凌日（太阳半径约 0.27°，几何与视位置差远小于 0.2°）
        let (_, bp) = coarse_lon_lat(eph, planet, tc)?;
        let (_, bs) = coarse_lon_lat(eph, Body::Sun, tc)?;
        if (bp - bs).abs() > 0.5f64.to_radians() {
            continue;
        }

        // 视角距 与 两个半径
        let geom = |tt: f64| -> Result<(f64, f64, f64)> {
            let (dp, ds) = apparent_pair(eph, planet, Body::Sun, tt)?;
            Ok((
                dp.apparent.angle_to(ds.apparent),
                (SUN_RADIUS_KM / ds.distance_km).asin(),
                (radius / dp.distance_km).asin(),
            ))
        };

        let (tg, min_sep) = refine_minimum(|t| Ok(geom(t)?.0), tc - DAY, tc + DAY, 1e-2)?;
        let (_, s_sun, s_p) = geom(tg)?;
        if min_sep >= s_sun + s_p {
            continue;
        }

        // 接触时刻：角距 = 外切/内切距离。凌日最长不到 9 小时，半天的区间足够
        let contact = |inner: bool, before: bool| -> Result<Option<Time>> {
            let f = |t: f64| -> Result<f64> {
                let (sep, ss, sp) = geom(t)?;
                Ok(sep - if inner { ss - sp } else { ss + sp })
            };
            if inner && min_sep >= s_sun - s_p {
                return Ok(None);
            }
            let (a, b) = if before {
                (tg - 0.5 * DAY, tg)
            } else {
                (tg, tg + 0.5 * DAY)
            };
            let t = refine_root(f, 0.5 * (a + b), 0.25 * DAY, 0.25 * DAY, 1e-2)?;
            Ok(Some(Time::from_tt_seconds(t)))
        };
        let contacts = [
            contact(false, true)?,
            contact(true, true)?,
            contact(true, false)?,
            contact(false, false)?,
        ];

        if span.contains(tg) {
            out.push(Transit {
                planet,
                contacts,
                greatest: Time::from_tt_seconds(tg),
                min_separation: min_sep,
                sun_semidiameter: s_sun,
                planet_semidiameter: s_p,
            });
        }
    }
    Ok(out)
}
