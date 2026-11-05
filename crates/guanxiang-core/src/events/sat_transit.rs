//! 卫星凌日、凌月（D8：与长期事件分开）。
//!
//! 所有方向在地固系（伪地固系，忽略极移）中比较：
//!
//! - 卫星：SGP4（TEME）在发光时刻 t − τ 的位置，按接收时刻 t 的 GMST82 转到地固系，
//!   再加周日光行差（测站随地球自转的速度）。卫星与地球同在地心系中运动，不加周年光行差。
//! - 太阳、月球：站心视位置（含周年和周日光行差），GCRS → CIRS → 地固（ERA）。
//!
//! 流程：30 秒步长找出卫星和目标都在地平线上的时段 → 1 秒步长找角距局部极小 → Brent 精修。
//! 太阳、月球的方向在 10 秒网格上精确计算后线性插值（误差约 0.01″），精修时逐点精确计算。

use sofars::erst::era00;

use super::lunar_eclipse::EARTH_RADIUS_KM;
use super::solar_eclipse::K_PENUMBRA;
use super::transit::SUN_RADIUS_KM;
use super::{Span, refine_minimum, refine_root};
use crate::astrometry::{self, C_KM_S, c2i_matrix, observer_gcrs};
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::{Error, Result};
use crate::geometry::Vec3;
use crate::observer::Observer;
use crate::satellite::{Satellite, teme_to_fixed};
use crate::time::Time;

/// 地球自转角速度（rad/s）
const OMEGA_EARTH: f64 = 7.292_115_146_706_979e-5;
const FLATTENING: f64 = 1.0 / 298.257_223_563;

/// 一次卫星接近（凌日、凌月或擦边）。
#[derive(Debug, Clone, PartialEq)]
pub struct SatTransit {
    pub norad_id: u32,
    pub satellite: String,
    /// 太阳或月球
    pub body: Body,
    /// 角距最小的时刻
    pub closest: Time,
    /// 卫星与日心（月心）的最小视角距（弧度）
    pub min_separation: f64,
    /// 太阳（月球）视半径（弧度）
    pub body_semidiameter: f64,
    /// 卫星穿过日面（月面）的时间（秒）；没有穿过为 None
    pub duration_s: Option<f64>,
    /// 卫星距离（km）
    pub range_km: f64,
    /// 卫星高度角、方位角（度）
    pub altitude_deg: f64,
    pub azimuth_deg: f64,
    /// 根数龄期（天）
    pub elements_age_days: f64,
    /// 测站到地面中心线的最近距离（km）及中心线上最近点（纬度、经度，度）
    pub distance_to_centerline_km: f64,
    pub centerline_nearest: (f64, f64),
    /// 能看到穿越的带宽的一半（km），近似为中心线距离 × 视半径 / 最小角距
    pub band_half_width_km: f64,
    /// 地面中心线：最近时刻前后各 10 秒、每 0.5 秒一点的（纬度, 经度），度
    pub centerline: Vec<(f64, f64)>,
}

impl SatTransit {
    pub fn is_transit(&self) -> bool {
        self.min_separation < self.body_semidiameter
    }
}

/// 测站在地固系中的位置（km），WGS84。
fn observer_fixed(obs: &Observer) -> Result<Vec3> {
    let p = sofars::coords::gd2gc(1, obs.longitude, obs.latitude, obs.height)
        .map_err(|_| Error::InvalidObserver("WGS84 坐标转换失败".into()))?;
    Ok(Vec3::from(p) * 1e-3)
}

struct Site {
    obs: Observer,
    fixed: Vec3,
    up: Vec3,
    east: Vec3,
    north: Vec3,
    /// 测站相对地心惯性系的速度（在地固轴上），用于周日光行差
    velocity: Vec3,
}

impl Site {
    fn new(obs: &Observer) -> Result<Self> {
        let fixed = observer_fixed(obs)?;
        let (sl, cl) = obs.longitude.sin_cos();
        let (sp, cp) = obs.latitude.sin_cos();
        Ok(Self {
            obs: *obs,
            fixed,
            up: Vec3::new(cp * cl, cp * sl, sp),
            east: Vec3::new(-sl, cl, 0.0),
            north: Vec3::new(-sp * cl, -sp * sl, cp),
            velocity: Vec3::new(-OMEGA_EARTH * fixed.y, OMEGA_EARTH * fixed.x, 0.0),
        })
    }

    fn alt_az(&self, u: Vec3) -> (f64, f64) {
        let alt = u.dot(self.up).clamp(-1.0, 1.0).asin();
        let az = u
            .dot(self.east)
            .atan2(u.dot(self.north))
            .rem_euclid(std::f64::consts::TAU);
        (alt, az)
    }
}

/// 卫星的视方向（地固轴，单位向量）和距离（km）。
fn satellite_direction(sat: &Satellite, site: &Site, t: &Time) -> Result<(Vec3, f64)> {
    let r0 = sat.earth_fixed(t)? - site.fixed;
    let tau = r0.norm() / C_KM_S;
    // 发光时刻的惯性位置，按接收时刻的地球自转角转到地固轴
    let (r_teme, _) = sat.teme(&t.add_seconds(-tau))?;
    let p = teme_to_fixed(r_teme, t) - site.fixed;
    let range = p.norm();
    let u = p.unit();
    let beta = site.velocity * (1.0 / C_KM_S);
    let aberrated = (u + beta - u * u.dot(beta)).unit();
    Ok((aberrated, range))
}

/// 太阳或月球的站心视方向（地固轴）和视半径。
fn body_direction(
    eph: &dyn Ephemeris,
    body: Body,
    site: &Site,
    t: &Time,
    rc2i: &[[f64; 3]; 3],
) -> Result<(Vec3, f64)> {
    let (pos, vel) = observer_gcrs(t, &site.obs, rc2i);
    let (d, _) = astrometry::direction_pair_from(eph, body, Body::Sun, t, pos, vel)?;
    let mut cirs = [0.0; 3];
    sofars::vm::rxp(rc2i, &d.apparent.into(), &mut cirs);
    let (ua, ub) = t.ut1_jd_parts();
    let era = era00(ua, ub);
    let (s, c) = era.sin_cos();
    let fixed = Vec3::new(
        c * cirs[0] + s * cirs[1],
        -s * cirs[0] + c * cirs[1],
        cirs[2],
    );
    let radius = match body {
        Body::Sun => SUN_RADIUS_KM,
        Body::Moon => K_PENUMBRA * EARTH_RADIUS_KM,
        _ => return Err(Error::Unsupported("卫星凌日只支持太阳和月球")),
    };
    Ok((fixed, (radius / d.distance_km).asin()))
}

/// 搜索 `span` 内卫星与太阳、月球的接近（视角距 ≤ `max_separation`，弧度）。
///
/// `span` 应在根数历元前后 14 天以内（根数越旧越不准）。`delta_t` 为 None 时用内置 ΔT 模型。
pub fn search(
    eph: &dyn Ephemeris,
    sat: &Satellite,
    bodies: &[Body],
    span: Span,
    obs: &Observer,
    max_separation: f64,
    delta_t: Option<f64>,
) -> Result<Vec<SatTransit>> {
    let site = Site::new(obs)?;
    let time_at = |tt: f64| {
        let t = Time::from_tt_seconds(tt);
        delta_t.map_or(t, |dt| t.with_delta_t(dt))
    };
    let rc2i = c2i_matrix(&span.start);
    let (start, end) = (span.start.tt_seconds(), span.end.tt_seconds());
    let mut out = Vec::new();

    // 1. 卫星在地平线上的时段（30 秒步长）
    const PASS_STEP: f64 = 30.0;
    let mut t = start;
    let mut pass_start: Option<f64> = None;
    let mut passes = Vec::new();
    while t <= end {
        let (u, _) = satellite_direction(sat, &site, &time_at(t))?;
        let up = site.alt_az(u).0 > 0.0;
        match (up, pass_start) {
            (true, None) => pass_start = Some((t - PASS_STEP).max(start)),
            (false, Some(s0)) => {
                passes.push((s0, t));
                pass_start = None;
            }
            _ => {}
        }
        t += PASS_STEP;
    }
    if let Some(s0) = pass_start {
        passes.push((s0, end));
    }

    for &body in bodies {
        for &(p0, p1) in &passes {
            // 2. 目标方向：10 秒网格精确计算，线性插值
            const GRID: f64 = 10.0;
            let n = ((p1 - p0) / GRID).ceil() as usize + 1;
            let grid: Vec<(Vec3, f64)> = (0..=n)
                .map(|i| body_direction(eph, body, &site, &time_at(p0 + i as f64 * GRID), &rc2i))
                .collect::<Result<_>>()?;
            // 目标整段都在地平线下就跳过
            if grid.iter().all(|(u, _)| site.alt_az(*u).0 < -0.01) {
                continue;
            }
            let interp = |tt: f64| -> Vec3 {
                let x = ((tt - p0) / GRID).clamp(0.0, n as f64);
                let i = (x.floor() as usize).min(n - 1);
                let f = x - i as f64;
                (grid[i].0 * (1.0 - f) + grid[i + 1].0 * f).unit()
            };

            // 3. 1 秒步长找角距局部极小
            let coarse = |tt: f64| -> Result<f64> {
                Ok(satellite_direction(sat, &site, &time_at(tt))?
                    .0
                    .angle_to(interp(tt)))
            };
            let mut tt = p0;
            let (mut s0, mut s1) = (coarse(tt)?, coarse(tt + 1.0)?);
            while tt + 2.0 <= p1 {
                let s2 = coarse(tt + 2.0)?;
                if s1 <= s0 && s1 < s2 && s1 < max_separation + 0.01 {
                    if let Some(ev) =
                        refine(eph, sat, body, &site, &rc2i, &time_at, tt, max_separation)?
                    {
                        if span.contains(ev.closest.tt_seconds()) {
                            out.push(ev);
                        }
                    }
                }
                tt += 1.0;
                s0 = s1;
                s1 = s2;
            }
        }
    }
    out.sort_by(|a, b| a.closest.tt_seconds().total_cmp(&b.closest.tt_seconds()));
    Ok(out)
}

#[allow(clippy::too_many_arguments)]
fn refine(
    eph: &dyn Ephemeris,
    sat: &Satellite,
    body: Body,
    site: &Site,
    rc2i: &[[f64; 3]; 3],
    time_at: &dyn Fn(f64) -> Time,
    t0: f64,
    max_separation: f64,
) -> Result<Option<SatTransit>> {
    let geometry = |tt: f64| -> Result<(f64, f64, Vec3, Vec3, f64)> {
        let t = time_at(tt);
        let (us, range) = satellite_direction(sat, site, &t)?;
        let (ub, sd) = body_direction(eph, body, site, &t, rc2i)?;
        Ok((us.angle_to(ub), sd, us, ub, range))
    };
    let (tc, sep) = refine_minimum(|t| Ok(geometry(t)?.0), t0, t0 + 2.0, 1e-4)?;
    if sep > max_separation {
        return Ok(None);
    }
    let (_, sd, us, ub, range) = geometry(tc)?;
    let (body_alt, _) = site.alt_az(ub);
    if body_alt < 0.0 {
        return Ok(None);
    }
    let (alt, az) = site.alt_az(us);

    let duration_s = if sep < sd {
        let f = |t: f64| -> Result<f64> {
            let (s, d, ..) = geometry(t)?;
            Ok(s - d)
        };
        // 穿越日面最长不过几秒
        let a = refine_root(f, tc - 2.5, 2.5, 20.0, 1e-4)?;
        let b = refine_root(f, tc + 2.5, 2.5, 20.0, 1e-4)?;
        Some(b - a)
    } else {
        None
    };

    // 地面中心线：每个时刻，从卫星沿“目标 → 卫星”方向延长到地面的点
    let line_point = |tt: f64| -> Result<Option<Vec3>> {
        let t = time_at(tt);
        let r = sat.earth_fixed(&t)?;
        let (ub, _) = body_direction(eph, body, site, &t, rc2i)?;
        Ok(ellipsoid_hit(r, -ub))
    };
    let dist_at = |tt: f64| -> Result<f64> {
        Ok(line_point(tt)?.map_or(f64::INFINITY, |p| (p - site.fixed).norm()))
    };
    let mut best_k = f64::NAN;
    let mut best_d = f64::INFINITY;
    let mut k = -10.0;
    while k <= 10.0 {
        let d = dist_at(tc + k)?;
        if d < best_d {
            (best_k, best_d) = (k, d);
        }
        k += 0.25;
    }
    let (distance, nearest) = if best_d.is_finite() {
        let (tk, d) = refine_minimum(dist_at, tc + best_k - 0.25, tc + best_k + 0.25, 1e-4)?;
        (d, line_point(tk)?.unwrap_or(site.fixed))
    } else {
        (f64::INFINITY, site.fixed)
    };
    let (lat, lon) = geodetic(nearest);
    let mut centerline = Vec::new();
    let mut k = -10.0;
    while k <= 10.0 {
        if let Some(p) = line_point(tc + k)? {
            let (la, lo) = geodetic(p);
            centerline.push((la.to_degrees(), lo.to_degrees()));
        }
        k += 0.5;
    }
    let band_half_width_km = if sep > 1e-7 && distance.is_finite() {
        distance * sd / sep
    } else {
        sd * range / body_alt.sin().max(0.05)
    };

    Ok(Some(SatTransit {
        norad_id: sat.norad_id,
        satellite: sat.name.clone(),
        body,
        closest: time_at(tc),
        min_separation: sep,
        body_semidiameter: sd,
        duration_s,
        range_km: range,
        altitude_deg: alt.to_degrees(),
        azimuth_deg: az.to_degrees(),
        elements_age_days: sat.age_days(&time_at(tc)),
        distance_to_centerline_km: distance,
        centerline_nearest: (lat.to_degrees(), lon.to_degrees()),
        band_half_width_km,
        centerline,
    }))
}

/// 射线 `origin + λ·dir`（λ > 0）与 WGS84 椭球（km）的第一个交点。
fn ellipsoid_hit(origin: Vec3, dir: Vec3) -> Option<Vec3> {
    let a = EARTH_RADIUS_KM;
    let b = a * (1.0 - FLATTENING);
    let s = Vec3::new(1.0 / a, 1.0 / a, 1.0 / b);
    let o = Vec3::new(origin.x * s.x, origin.y * s.y, origin.z * s.z);
    let d = Vec3::new(dir.x * s.x, dir.y * s.y, dir.z * s.z);
    let qa = d.dot(d);
    let qb = 2.0 * o.dot(d);
    let qc = o.dot(o) - 1.0;
    let disc = qb * qb - 4.0 * qa * qc;
    if disc < 0.0 {
        return None;
    }
    let lambda = (-qb - disc.sqrt()) / (2.0 * qa);
    (lambda > 0.0).then(|| origin + dir * lambda)
}

fn geodetic(p: Vec3) -> (f64, f64) {
    let e2 = FLATTENING * (2.0 - FLATTENING);
    let rxy = (p.x * p.x + p.y * p.y).sqrt();
    // 近地表点：一次迭代足够（误差 < 1 m）
    let mut lat = (p.z / ((1.0 - e2) * rxy)).atan();
    for _ in 0..3 {
        let n = EARTH_RADIUS_KM / (1.0 - e2 * lat.sin().powi(2)).sqrt();
        let h = rxy / lat.cos() - n;
        lat = (p.z / (rxy * (1.0 - e2 * n / (n + h)))).atan();
    }
    (lat, p.y.atan2(p.x))
}
