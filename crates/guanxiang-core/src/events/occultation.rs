//! 月掩星（月掩行星、月掩恒星）。
//!
//! 掩始、掩终定义为月面边缘经过目标**中心**的时刻（站心视位置）。月球半径 k = 0.2725076。
//!
//! 流程：几何位置粗搜地心角距极小（每半天一点），角距小于“月球半径 + 月球视差 + 余量”的作为候选；
//! 再用站心视位置求本地最近时刻、掩始和掩终。

use super::lunar_eclipse::EARTH_RADIUS_KM;
use super::solar_eclipse::K_PENUMBRA;
use super::visibility::apparent_altitude;
use super::{DAY, Span, refine_minimum, refine_root};
use crate::astrometry::{self, c2i_matrix, observer_gcrs};
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::{Error, Result};
use crate::geometry::Vec3;
use crate::observer::Observer;
use crate::stars::Star;
use crate::time::{Tdb, Time};

/// 被掩的目标。
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Target {
    Planet(Body),
    Star(&'static Star),
}

impl Target {
    pub fn label(&self) -> String {
        match self {
            Target::Planet(b) => b.name_zh().to_string(),
            Target::Star(s) => s.label(),
        }
    }

    /// 平均半径（km），恒星为 0。
    pub fn radius_km(&self) -> f64 {
        match self {
            Target::Planet(Body::Mercury) => 2439.7,
            Target::Planet(Body::Venus) => 6051.8,
            Target::Planet(Body::Mars) => 3389.5,
            Target::Planet(Body::Jupiter) => 69_911.0,
            Target::Planet(Body::Saturn) => 58_232.0,
            Target::Planet(Body::Uranus) => 25_362.0,
            Target::Planet(Body::Neptune) => 24_622.0,
            _ => 0.0,
        }
    }

    fn check(&self) -> Result<()> {
        match self {
            Target::Planet(Body::Moon | Body::Earth | Body::Sun | Body::SolarSystemBarycenter) => {
                Err(Error::Unsupported("月掩星的目标只能是行星或恒星"))
            }
            _ => Ok(()),
        }
    }
}

/// 地心候选：地心角距极小。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Candidate {
    pub target: Target,
    pub time: Time,
    /// 几何地心角距（弧度）
    pub separation: f64,
}

/// 某地看到的一次月掩星。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Occultation {
    pub target: Target,
    /// 掩始（目标中心消失于月面边缘）
    pub disappearance: Time,
    /// 掩终（目标中心重新出现）
    pub reappearance: Time,
    /// 站心角距最小的时刻
    pub closest: Time,
    /// 最小站心角距与月球视半径（弧度）
    pub min_separation: f64,
    pub moon_semidiameter: f64,
    /// 掩始、掩终时月球的视高度（含折射，度）
    pub moon_altitude_deg: [f64; 2],
    /// 掩始、掩终时太阳的视高度（含折射，度）
    pub sun_altitude_deg: [f64; 2],
}

impl Occultation {
    /// 掩始或掩终时月球在地平线上。
    pub fn moon_above_horizon(&self) -> bool {
        self.moon_altitude_deg.iter().any(|&h| h > 0.0)
    }
}

/// 粗搜用的几何地心方向。
fn coarse_direction(eph: &dyn Ephemeris, target: Target, tt: f64) -> Result<Vec3> {
    match target {
        Target::Planet(b) => Ok(eph.position(b, Body::Earth, Tdb(tt))?.unit()),
        Target::Star(s) => Ok(s.barycentric_direction(Tdb(tt))),
    }
}

/// 月球视半径 + 最大地平视差（约 1.02°）+ 粗搜和光行差余量。
const CANDIDATE_LIMIT_DEG: f64 = 0.28 + 1.03 + 0.25;

/// 地心候选（每月至多一次）。
pub fn candidates(eph: &dyn Ephemeris, target: Target, span: Span) -> Result<Vec<Candidate>> {
    target.check()?;
    let sep = |tt: f64| -> Result<f64> {
        let m = eph.position(Body::Moon, Body::Earth, Tdb(tt))?.unit();
        Ok(m.angle_to(coarse_direction(eph, target, tt)?))
    };
    // 行星的视半径（木星最大约 0.014°）也算进阈值；恒星与 candidates_all_stars 用同一阈值
    let planet_margin = if matches!(target, Target::Planet(_)) {
        0.02
    } else {
        0.0
    };
    let limit = (CANDIDATE_LIMIT_DEG + planet_margin).to_radians();
    let step = 0.5 * DAY;
    let (start, end) = (span.start.tt_seconds(), span.end.tt_seconds());
    let mut t = start - step;
    let (mut s0, mut s1) = (sep(t)?, sep(t + step)?);
    let mut out = Vec::new();
    while t + step < end + step {
        let s2 = sep(t + 2.0 * step)?;
        if s1 <= s0 && s1 < s2 && s1 - (s0 - s1).max(s2 - s1) < limit {
            let (tc, sc) = refine_minimum(sep, t, t + 2.0 * step, 1.0)?;
            if sc < limit && span.contains(tc) {
                out.push(Candidate {
                    target,
                    time: Time::from_tt_seconds(tc),
                    separation: sc,
                });
            }
        }
        t += step;
        s0 = s1;
        s1 = s2;
    }
    Ok(out)
}

/// 星表中所有恒星的地心候选。月球位置每步只算一次，比逐颗调用 [`candidates`] 快得多。
/// 结果按时间排序。
pub fn candidates_all_stars(eph: &dyn Ephemeris, span: Span) -> Result<Vec<Candidate>> {
    let stars = crate::stars::catalog();
    let limit = CANDIDATE_LIMIT_DEG.to_radians();
    let step = 0.5 * DAY;
    let (start, end) = (span.start.tt_seconds(), span.end.tt_seconds());
    let moon =
        |tt: f64| -> Result<Vec3> { Ok(eph.position(Body::Moon, Body::Earth, Tdb(tt))?.unit()) };
    let seps = |tt: f64, m: Vec3| -> Vec<f64> {
        stars
            .iter()
            .map(|s| m.angle_to(s.barycentric_direction(Tdb(tt))))
            .collect()
    };

    let mut t = start - step;
    let mut s0 = seps(t, moon(t)?);
    let mut s1 = seps(t + step, moon(t + step)?);
    let mut out = Vec::new();
    while t + step < end + step {
        let t2 = t + 2.0 * step;
        let s2 = seps(t2, moon(t2)?);
        for (i, star) in stars.iter().enumerate() {
            let (a, b, c) = (s0[i], s1[i], s2[i]);
            if b <= a && b < c && b - (a - b).max(c - b) < limit {
                let target = Target::Star(star);
                let sep = |tt: f64| -> Result<f64> {
                    Ok(moon(tt)?.angle_to(star.barycentric_direction(Tdb(tt))))
                };
                let (tc, sc) = refine_minimum(sep, t, t2, 1.0)?;
                if sc < limit && span.contains(tc) {
                    out.push(Candidate {
                        target,
                        time: Time::from_tt_seconds(tc),
                        separation: sc,
                    });
                }
            }
        }
        t += step;
        s0 = s1;
        s1 = s2;
    }
    out.sort_by(|x, y| x.time.tt_seconds().total_cmp(&y.time.tt_seconds()));
    Ok(out)
}

/// 某地在 `span` 内看到的月掩星（不论月球是否在地平线上；用 [`Occultation::moon_above_horizon`] 过滤）。
pub fn search_local(
    eph: &dyn Ephemeris,
    target: Target,
    span: Span,
    obs: &Observer,
    delta_t: Option<f64>,
) -> Result<Vec<Occultation>> {
    let mut out = Vec::new();
    for c in candidates(eph, target, span)? {
        if let Some(o) = local(eph, &c, obs, delta_t)? {
            out.push(o);
        }
    }
    Ok(out)
}

/// 针对一个地心候选计算本地情况；该地看不到掩星时返回 None。
pub fn local(
    eph: &dyn Ephemeris,
    candidate: &Candidate,
    obs: &Observer,
    delta_t: Option<f64>,
) -> Result<Option<Occultation>> {
    let target = candidate.target;
    let time_at = |tt: f64| {
        let t = Time::from_tt_seconds(tt);
        delta_t.map_or(t, |dt| t.with_delta_t(dt))
    };
    let rc2i = c2i_matrix(&candidate.time);
    // (站心角距, 月球视半径)
    let geometry = |tt: f64| -> Result<(f64, f64)> {
        let t = time_at(tt);
        let (pos, vel) = observer_gcrs(&t, obs, &rc2i);
        let (dir, moon) = match target {
            Target::Planet(b) => {
                let (moon, p) = astrometry::direction_pair_from(eph, Body::Moon, b, &t, pos, vel)?;
                (p.apparent, moon)
            }
            Target::Star(s) => astrometry::star_and_body_from(eph, s, Body::Moon, &t, pos, vel)?,
        };
        let s_m = (K_PENUMBRA * EARTH_RADIUS_KM / moon.distance_km).asin();
        Ok((moon.apparent.angle_to(dir), s_m))
    };

    let tc = candidate.time.tt_seconds();
    let (tm, sep) = refine_minimum(
        |t| Ok(geometry(t)?.0),
        tc - 0.25 * DAY,
        tc + 0.25 * DAY,
        1e-2,
    )?;
    let (_, s_m) = geometry(tm)?;
    if sep >= s_m {
        return Ok(None);
    }
    let f = |t: f64| -> Result<f64> {
        let (sep, s_m) = geometry(t)?;
        Ok(sep - s_m)
    };
    // 掩星最长约 1.5 小时；考虑到地球自转使站心相对运动变慢，每侧给 0.15 天
    let half = 0.075 * DAY;
    let d = refine_root(f, tm - half, half, half, 1e-2)?;
    let r = refine_root(f, tm + half, half, half, 1e-2)?;
    let (td, tr) = (time_at(d), time_at(r));
    let alt = |body: Body, t: &Time| -> Result<f64> {
        Ok(apparent_altitude(eph, body, t, obs)?.to_degrees())
    };
    Ok(Some(Occultation {
        target,
        disappearance: td,
        reappearance: tr,
        closest: time_at(tm),
        min_separation: sep,
        moon_semidiameter: s_m,
        moon_altitude_deg: [alt(Body::Moon, &td)?, alt(Body::Moon, &tr)?],
        sun_altitude_deg: [alt(Body::Sun, &td)?, alt(Body::Sun, &tr)?],
    }))
}
