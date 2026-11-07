//! 某地的日月出没、晨昏蒙影，以及月相。
//!
//! 定义与美国海军天文台（USNO）、Skyfield `almanac` 相同：
//!
//! - 日出、日落：太阳上边缘与地平线相切。用站心几何高度（不含折射）判断：
//!   太阳中心高度 = −(34′ + 视半径)，34′ 是地平线处的标准大气折射。
//! - 月出、月落：同上，用月球站心中心高度（已含视差）= −(34′ + 站心视半径)。
//! - 民用、航海、天文晨昏：太阳中心几何高度 −6°、−12°、−18°，不计折射。
//! - 月相：照亮比例 k = (1 + cos i) / 2，i 为相位角（月球处看太阳与地球的夹角），
//!   由地心视位置的日月角距和距离求出（Meeus 式 48.2、48.3）；盈亏看日月视黄经差。
//!
//! 搜索方法：每 10 分钟取样一次高度，找出穿越阈值的区间，再用 Brent 法精修到 0.1 秒。
//! 在 10 分钟内先升后落（高纬度地区擦过地平线）的情形会漏掉。

use std::f64::consts::PI;

use super::longitude::{self, Aspect};
use super::{Span, ecliptic_of_date_matrix, lon_lat, mul, wrap_pi};
use crate::astrometry;
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::Result;
use crate::observer::Observer;
use crate::search::find_root;
use crate::time::Time;

/// 地平线处的标准大气折射（34′）
const REFRACTION_AT_HORIZON: f64 = 34.0 / 60.0 * PI / 180.0;
/// 太阳半径（km，IAU 2015 名义值）
pub const SUN_RADIUS_KM: f64 = 695_700.0;
/// 月球平均半径（km）
pub const MOON_RADIUS_KM: f64 = 1_737.4;
/// 取样步长（秒）
const STEP_S: f64 = 600.0;
/// 精修容差（秒）
const TOL_S: f64 = 0.1;

/// 出没和晨昏事件。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SkyEventKind {
    AstronomicalDawn,
    NauticalDawn,
    CivilDawn,
    Sunrise,
    Sunset,
    CivilDusk,
    NauticalDusk,
    AstronomicalDusk,
    Moonrise,
    Moonset,
}

/// 一次出没或晨昏。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SkyEvent {
    pub kind: SkyEventKind,
    pub time: Time,
}

/// 判据的阈值：固定高度，或按天体视半径（上边缘相切）。
#[derive(Debug, Clone, Copy)]
enum Horizon {
    Fixed(f64),
    UpperLimb { radius_km: f64 },
}

impl Horizon {
    /// 中心站心几何高度的阈值（弧度）。
    fn altitude(self, distance_km: f64) -> f64 {
        match self {
            Horizon::Fixed(h) => h,
            Horizon::UpperLimb { radius_km } => {
                -(REFRACTION_AT_HORIZON + (radius_km / distance_km).asin())
            }
        }
    }
}

struct Criterion {
    body: Body,
    horizon: Horizon,
    rising: SkyEventKind,
    setting: SkyEventKind,
}

fn criteria() -> [Criterion; 5] {
    let deg = PI / 180.0;
    [
        Criterion {
            body: Body::Sun,
            horizon: Horizon::UpperLimb {
                radius_km: SUN_RADIUS_KM,
            },
            rising: SkyEventKind::Sunrise,
            setting: SkyEventKind::Sunset,
        },
        Criterion {
            body: Body::Sun,
            horizon: Horizon::Fixed(-6.0 * deg),
            rising: SkyEventKind::CivilDawn,
            setting: SkyEventKind::CivilDusk,
        },
        Criterion {
            body: Body::Sun,
            horizon: Horizon::Fixed(-12.0 * deg),
            rising: SkyEventKind::NauticalDawn,
            setting: SkyEventKind::NauticalDusk,
        },
        Criterion {
            body: Body::Sun,
            horizon: Horizon::Fixed(-18.0 * deg),
            rising: SkyEventKind::AstronomicalDawn,
            setting: SkyEventKind::AstronomicalDusk,
        },
        Criterion {
            body: Body::Moon,
            horizon: Horizon::UpperLimb {
                radius_km: MOON_RADIUS_KM,
            },
            rising: SkyEventKind::Moonrise,
            setting: SkyEventKind::Moonset,
        },
    ]
}

/// TT 秒 → 时刻；`delta_t` 为 None 时用内置 ΔT 模型。
fn at(tt: f64, delta_t: Option<f64>) -> Time {
    let t = Time::from_tt_seconds(tt);
    match delta_t {
        Some(d) => t.with_delta_t(d),
        None => t,
    }
}

/// 站心几何高度（弧度）和距离（km）。
fn altitude_distance(
    eph: &dyn Ephemeris,
    body: Body,
    obs: &Observer,
    tt: f64,
    delta_t: Option<f64>,
) -> Result<(f64, f64)> {
    let p = astrometry::topocentric(eph, body, &at(tt, delta_t), obs)?;
    Ok((p.horizontal.altitude, p.place.distance_km))
}

/// 区间内的日月出没和晨昏，按时间排序。
///
/// `delta_t`（秒）用于和其他软件按同一 ΔT 对比；应用里传 None，用内置 ΔT 模型。
pub fn rise_set_twilight(
    eph: &dyn Ephemeris,
    obs: &Observer,
    span: Span,
    delta_t: Option<f64>,
) -> Result<Vec<SkyEvent>> {
    let (t0, t1) = (span.start.tt_seconds(), span.end.tt_seconds());
    let n = ((t1 - t0) / STEP_S).ceil().max(1.0) as usize;
    let times: Vec<f64> = (0..=n).map(|i| (t0 + i as f64 * STEP_S).min(t1)).collect();

    // 每个天体每个取样点只算一次位置，几个判据共用
    let mut samples = Vec::new();
    for body in [Body::Sun, Body::Moon] {
        let v = times
            .iter()
            .map(|&tt| altitude_distance(eph, body, obs, tt, delta_t))
            .collect::<Result<Vec<_>>>()?;
        samples.push((body, v));
    }

    let mut out = Vec::new();
    for c in criteria() {
        let s = &samples.iter().find(|(b, _)| *b == c.body).unwrap().1;
        let g = |(alt, dist): (f64, f64)| alt - c.horizon.altitude(dist);
        for i in 0..n {
            let (ga, gb) = (g(s[i]), g(s[i + 1]));
            if ga == 0.0 || ga.signum() == gb.signum() {
                continue;
            }
            let mut err = None;
            let root = find_root(
                |tt| match altitude_distance(eph, c.body, obs, tt, delta_t) {
                    Ok(v) => g(v),
                    Err(e) => {
                        err.get_or_insert(e);
                        0.0
                    }
                },
                times[i],
                times[i + 1],
                TOL_S,
            )?;
            if let Some(e) = err {
                return Err(e);
            }
            out.push(SkyEvent {
                kind: if gb > ga { c.rising } else { c.setting },
                time: at(root.x, delta_t),
            });
        }
    }
    out.sort_by(|a, b| a.time.tt_seconds().total_cmp(&b.time.tt_seconds()));
    Ok(out)
}

/// 某一时刻的太阳中心站心几何高度（弧度），用来判断极昼、极夜。
pub fn sun_altitude(eph: &dyn Ephemeris, obs: &Observer, t: &Time) -> Result<f64> {
    let p = astrometry::topocentric(eph, Body::Sun, t, obs)?;
    Ok(p.horizontal.altitude)
}

/// 月相。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MoonPhase {
    /// 照亮比例，0（朔）到 1（望）
    pub illuminated_fraction: f64,
    /// 相位角（弧度），0 为望、π 为朔
    pub phase_angle: f64,
    /// 月球视黄经减太阳视黄经，归一化到 [0, 2π)：0 朔、π/2 上弦、π 望、3π/2 下弦
    pub longitude_difference: f64,
}

impl MoonPhase {
    /// 上半月（新月到满月）
    pub fn waxing(&self) -> bool {
        self.longitude_difference < PI
    }
}

/// 地心看到的月相。
pub fn moon_phase(eph: &dyn Ephemeris, t: &Time) -> Result<MoonPhase> {
    let sun = astrometry::geocentric(eph, Body::Sun, t)?;
    let moon = astrometry::geocentric(eph, Body::Moon, t)?;
    let psi = sun.apparent_gcrs.angle_to(moon.apparent_gcrs);
    let (r, d) = (sun.distance_km, moon.distance_km);
    let i = (r * psi.sin()).atan2(d - r * psi.cos());
    let m = ecliptic_of_date_matrix(t);
    let (ls, _) = lon_lat(mul(&m, sun.apparent_gcrs));
    let (lm, _) = lon_lat(mul(&m, moon.apparent_gcrs));
    Ok(MoonPhase {
        illuminated_fraction: (1.0 + i.cos()) / 2.0,
        phase_angle: i,
        longitude_difference: wrap_pi(lm - ls).rem_euclid(2.0 * PI),
    })
}

/// `t` 之后的第一次朔（Conjunction）或望（Opposition），在 35 天内一定有。
pub fn next_lunar_phase(eph: &dyn Ephemeris, t: &Time, aspect: Aspect) -> Result<Option<Time>> {
    let span = Span::new(*t, t.add_seconds(35.0 * 86_400.0))?;
    let found = longitude::search(
        eph,
        Body::Moon,
        Body::Sun,
        aspect,
        span,
        longitude::default_step_days(Body::Moon, Body::Sun),
    )?;
    Ok(found
        .into_iter()
        .map(|e| e.time)
        .find(|x| x.tt_seconds() > t.tt_seconds()))
}
