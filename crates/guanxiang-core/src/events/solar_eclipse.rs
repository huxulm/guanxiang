//! 日食（全球）：贝塞尔根数、类型判定、食甚、中心线与食带宽度。
//!
//! 太阳和月球取地心**视位置**，转到真赤道、真春分点（与《天文年历补编》第 11 章一致）。
//! 长度单位为地球赤道半径。月球半径按 NASA 约定：半影用 k₁ = 0.2725076，本影用 k₂ = 0.2722810。
//!
//! 类型判定只依赖几何，与 ΔT 无关：
//!
//! - 影轴与地球椭球相交 → 中心食。交点处本影半径 L < 0 为全食，> 0 为环食；
//!   沿中心线 L 变号为全环食。
//! - 影轴不与地球相交，但本影（伪本影）锥能擦到地球边缘 → 非中心全食（环食）。
//! - 只有半影接触地球 → 偏食。

use sofars::erst::gst06a;
use sofars::pnp::pnm06a;

use super::longitude::{self, Aspect};
use super::lunar_eclipse::EARTH_RADIUS_KM;
use super::transit::SUN_RADIUS_KM;
use super::{DAY, Span, coarse_lon_lat, mul, refine_minimum};
use crate::astrometry;
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::Result;
use crate::geometry::Vec3;
use crate::time::Time;

/// 月球半径（地球赤道半径），半影计算用
pub const K_PENUMBRA: f64 = 0.272_507_6;
/// 月球半径（地球赤道半径），本影计算用（考虑月面谷地）
pub const K_UMBRA: f64 = 0.272_281_0;
/// WGS84 扁率
const FLATTENING: f64 = 1.0 / 298.257_223_563;

fn e2() -> f64 {
    FLATTENING * (2.0 - FLATTENING)
}

/// 贝塞尔根数（某一时刻）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BesselianElements {
    /// 影轴在基本面上的坐标（地球半径），x 向东、y 向北
    pub x: f64,
    pub y: f64,
    /// 月心在基本面坐标系中的 z（地球半径）
    pub z: f64,
    /// 影轴的赤纬、赤经（弧度，真赤道真春分点）
    pub d: f64,
    pub a: f64,
    /// 半影、本影锥在基本面上的半径（地球半径）；l2 < 0 表示本影（全食）
    pub l1: f64,
    pub l2: f64,
    pub tan_f1: f64,
    pub tan_f2: f64,
    /// 真赤道坐标中的月心位置和影轴单位向量（指向太阳）
    moon: Vec3,
    axis: Vec3,
}

/// 计算贝塞尔根数。`rot` 为 GCRS → 真赤道真春分点的矩阵，日食前后几小时内可视为不变。
fn elements(eph: &dyn Ephemeris, tt: f64, rot: &[[f64; 3]; 3]) -> Result<BesselianElements> {
    let t = Time::from_tt_seconds(tt);
    let (moon, sun) = astrometry::geocentric_direction_pair(eph, Body::Moon, Body::Sun, &t)?;
    let m = mul(rot, moon.apparent) * (moon.distance_km / EARTH_RADIUS_KM);
    let s = mul(rot, sun.apparent) * (sun.distance_km / EARTH_RADIUS_KM);
    let g_vec = s - m;
    let g_len = g_vec.norm();
    let g = g_vec * (1.0 / g_len);

    let d = g.z.asin();
    let a = g.y.atan2(g.x);
    let (sa, ca) = a.sin_cos();
    let (sd, cd) = d.sin_cos();
    let i = Vec3::new(-sa, ca, 0.0);
    let j = Vec3::new(-sd * ca, -sd * sa, cd);

    let rs = SUN_RADIUS_KM / EARTH_RADIUS_KM;
    let f1 = ((rs + K_PENUMBRA) / g_len).asin();
    let f2 = ((rs - K_UMBRA) / g_len).asin();
    let z = m.dot(g);
    Ok(BesselianElements {
        x: m.dot(i),
        y: m.dot(j),
        z,
        d,
        a,
        l1: z * f1.tan() + K_PENUMBRA / f1.cos(),
        l2: z * f2.tan() - K_UMBRA / f2.cos(),
        tan_f1: f1.tan(),
        tan_f2: f2.tan(),
        moon: m,
        axis: g,
    })
}

impl BesselianElements {
    /// 影轴与地球椭球靠月球一侧的交点（真赤道坐标，地球半径）；不相交返回 None。
    fn axis_surface_point(&self) -> Option<Vec3> {
        let (m, g) = (self.moon, self.axis);
        let b = 1.0 / (1.0 - e2());
        let qa = g.x * g.x + g.y * g.y + b * g.z * g.z;
        let qb = 2.0 * (m.x * g.x + m.y * g.y + b * m.z * g.z);
        let qc = m.x * m.x + m.y * m.y + b * m.z * m.z - 1.0;
        let disc = qb * qb - 4.0 * qa * qc;
        if disc < 0.0 {
            return None;
        }
        let lambda = (-qb + disc.sqrt()) / (2.0 * qa);
        Some(m + g * lambda)
    }

    /// 地表点到基本面的距离 ζ（沿影轴方向）。
    fn zeta(&self, p: Vec3) -> f64 {
        p.dot(self.axis)
    }

    /// 影轴到地球椭球（在基本面上的投影椭圆）的距离；影轴穿过地球时为负。
    fn miss_distance(&self) -> f64 {
        let rho1 = (1.0 - e2() * self.d.cos().powi(2)).sqrt();
        (self.x * self.x + (self.y / rho1).powi(2)).sqrt() - 1.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SolarEclipseKind {
    Partial,
    Annular,
    Total,
    /// 全环食
    Hybrid,
}

/// 一次日食（全球情况）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SolarEclipse {
    pub kind: SolarEclipseKind,
    /// 影轴是否穿过地球（中心食）；全食、环食可能是非中心的
    pub central: bool,
    /// 食甚：影轴离地心最近
    pub greatest: Time,
    /// 影轴离地心的最近距离（地球半径），影轴在地心以北为正
    pub gamma: f64,
    /// 食分：中心食为食甚点的视直径比，偏食为最接近影轴的地面点的食分（与 NASA 定义相同）
    pub magnitude: f64,
    /// 食甚时影轴在地面的点（中心食），或最接近影轴的地面点附近
    pub greatest_point: Option<GroundPoint>,
    elements_rot: [[f64; 3]; 3],
}

/// 地面上的点。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GroundPoint {
    pub time: Time,
    /// 大地纬度、经度（度，东经为正）
    pub latitude_deg: f64,
    pub longitude_deg: f64,
    /// 太阳高度角（度）
    pub sun_altitude_deg: f64,
    /// 本影（伪本影）食带宽度（km），只对中心食有意义
    pub path_width_km: f64,
}

/// 搜索 `span` 内的日食。
pub fn search(eph: &dyn Ephemeris, span: Span) -> Result<Vec<SolarEclipse>> {
    let mut out = Vec::new();
    let step = longitude::default_step_days(Body::Moon, Body::Sun);
    for bracket in
        longitude::coarse_brackets(eph, Body::Moon, Body::Sun, Aspect::Conjunction, span, step)?
    {
        let tc = longitude::coarse_root(eph, Body::Moon, Body::Sun, Aspect::Conjunction, bracket)?;
        // 剪枝：朔时月球黄纬超过 1.65° 不会有日食（日食食限约 1.58°）
        let (_, beta) = coarse_lon_lat(eph, Body::Moon, tc)?;
        if beta.abs() > 1.65f64.to_radians() {
            continue;
        }
        if let Some(e) = refine(eph, tc)? {
            if span.contains(e.greatest.tt_seconds()) {
                out.push(e);
            }
        }
    }
    Ok(out)
}

fn rotation(tt: f64) -> [[f64; 3]; 3] {
    let t = Time::from_tt_seconds(tt);
    let (a, b) = t.tt_jd_parts();
    pnm06a(a, b)
}

fn refine(eph: &dyn Ephemeris, tc: f64) -> Result<Option<SolarEclipse>> {
    let rot = rotation(tc);
    let gamma_of = |t: f64| -> Result<f64> {
        let e = elements(eph, t, &rot)?;
        Ok((e.x * e.x + e.y * e.y).sqrt())
    };
    let (tg, gamma_abs) = refine_minimum(gamma_of, tc - 0.3 * DAY, tc + 0.3 * DAY, 1e-2)?;
    let e = elements(eph, tg, &rot)?;
    let miss = e.miss_distance();

    let (kind, central, magnitude) = if let Some(p) = e.axis_surface_point() {
        let zeta = e.zeta(p);
        let l1 = e.l1 - zeta * e.tan_f1;
        let l2 = e.l2 - zeta * e.tan_f2;
        let base = if l2 < 0.0 {
            SolarEclipseKind::Total
        } else {
            SolarEclipseKind::Annular
        };
        let kind = if changes_sign_along_path(eph, tg, &rot, l2 < 0.0)? {
            SolarEclipseKind::Hybrid
        } else {
            base
        };
        (kind, true, (l1 - l2) / (l1 + l2))
    } else if miss < e.l2.abs() {
        let kind = if e.l2 < 0.0 {
            SolarEclipseKind::Total
        } else {
            SolarEclipseKind::Annular
        };
        (kind, false, (e.l1 - miss) / (e.l1 + e.l2))
    } else if miss < e.l1 {
        (
            SolarEclipseKind::Partial,
            false,
            (e.l1 - miss) / (e.l1 + e.l2),
        )
    } else {
        return Ok(None);
    };

    let eclipse = SolarEclipse {
        kind,
        central,
        greatest: Time::from_tt_seconds(tg),
        gamma: gamma_abs.copysign(e.y),
        magnitude,
        greatest_point: None,
        elements_rot: rot,
    };
    let greatest_point = if central {
        central_point(eph, &eclipse, tg, None)?
    } else {
        None
    };
    Ok(Some(SolarEclipse {
        greatest_point,
        ..eclipse
    }))
}

/// 沿中心线（影轴与地球相交的整段时间）检查本影半径是否变号。
fn changes_sign_along_path(
    eph: &dyn Ephemeris,
    tg: f64,
    rot: &[[f64; 3]; 3],
    total_at_greatest: bool,
) -> Result<bool> {
    const STEP: f64 = 60.0;
    for dir in [-1.0, 1.0] {
        let mut t = tg;
        // 中心食最长约 4 小时（影轴扫过地球），每侧最多看 5 小时
        for _ in 0..300 {
            t += dir * STEP;
            let e = elements(eph, t, rot)?;
            let Some(p) = e.axis_surface_point() else {
                break;
            };
            let l2 = e.l2 - e.zeta(p) * e.tan_f2;
            if (l2 < 0.0) != total_at_greatest {
                return Ok(true);
            }
        }
    }
    Ok(false)
}

/// 地球自转角：真春分点格林尼治视恒星时（弧度）。
fn gast(t: &Time) -> f64 {
    let (ua, ub) = t.ut1_jd_parts();
    let (ta, tb) = t.tt_jd_parts();
    gst06a(ua, ub, ta, tb)
}

/// 真赤道坐标中的地表点 → 地固坐标（绕 z 轴转 GAST，忽略极移）。
fn to_earth_fixed(p: Vec3, gast: f64) -> Vec3 {
    let (s, c) = gast.sin_cos();
    Vec3::new(c * p.x + s * p.y, -s * p.x + c * p.y, p.z)
}

fn geodetic(p_fixed: Vec3) -> (f64, f64) {
    let lon = p_fixed.y.atan2(p_fixed.x);
    let rxy = (p_fixed.x * p_fixed.x + p_fixed.y * p_fixed.y).sqrt();
    let lat = (p_fixed.z / ((1.0 - e2()) * rxy)).atan();
    (lat, lon)
}

/// 地表点的椭球法向（真赤道坐标）。
fn surface_normal(p: Vec3) -> Vec3 {
    Vec3::new(p.x, p.y, p.z / (1.0 - e2())).unit()
}

/// 中心线在 `tt` 时刻的地面点（影轴不与地球相交时返回 None）。
/// `delta_t` 为 None 时用内置 ΔT 模型；与 NASA 等星表比较时可传入对方使用的 ΔT。
fn central_point(
    eph: &dyn Ephemeris,
    eclipse: &SolarEclipse,
    tt: f64,
    delta_t: Option<f64>,
) -> Result<Option<GroundPoint>> {
    let time_at = |tt: f64| {
        let t = Time::from_tt_seconds(tt);
        delta_t.map_or(t, |dt| t.with_delta_t(dt))
    };
    let rot = &eclipse.elements_rot;
    let e = elements(eph, tt, rot)?;
    let Some(p) = e.axis_surface_point() else {
        return Ok(None);
    };
    let t = time_at(tt);
    let theta = gast(&t);
    let fixed = to_earth_fixed(p, theta);
    let (lat, lon) = geodetic(fixed);
    let n = surface_normal(p);
    let cos_z = n.dot(e.axis);
    let half = (e.l2 - e.zeta(p) * e.tan_f2).abs();

    // 食带宽度：影锥截面（半径 half）投影到地面成椭圆，长轴沿影轴在地面上的投影方向。
    // 宽度取垂直于中心线行进方向的全宽。行进方向由 ±30 s 的中心线点在地固系中差分得到。
    let width = {
        let track = |dt: f64| -> Result<Option<Vec3>> {
            let e2_ = elements(eph, tt + dt, rot)?;
            Ok(e2_
                .axis_surface_point()
                .map(|q| to_earth_fixed(q, gast(&time_at(tt + dt)))))
        };
        match (track(-30.0)?, track(30.0)?) {
            (Some(a), Some(b)) => {
                let n_f = to_earth_fixed(n, theta);
                let g_f = to_earth_fixed(e.axis, theta);
                let dir = b - a;
                let path = (dir - n_f * dir.dot(n_f)).unit();
                let w = n_f.cross(path); // 地面上垂直于路径的方向
                let u_raw = g_f - n_f * g_f.dot(n_f);
                let (major, minor) = (half / cos_z, half);
                if u_raw.norm() < 1e-9 {
                    2.0 * half
                } else {
                    let u = u_raw.unit();
                    let v = n_f.cross(u);
                    2.0 * ((major * w.dot(u)).powi(2) + (minor * w.dot(v)).powi(2)).sqrt()
                }
            }
            _ => 2.0 * half / cos_z,
        }
    };

    Ok(Some(GroundPoint {
        time: t,
        latitude_deg: lat.to_degrees(),
        longitude_deg: sofars::vm::anpm(lon).to_degrees(),
        sun_altitude_deg: cos_z.clamp(-1.0, 1.0).asin().to_degrees(),
        path_width_km: width * EARTH_RADIUS_KM,
    }))
}

impl SolarEclipse {
    /// 食甚时中心线的地面点，`delta_t` 指定 ΔT（秒）。非中心食返回 None。
    pub fn greatest_point_with_delta_t(
        &self,
        eph: &dyn Ephemeris,
        delta_t: f64,
    ) -> Result<Option<GroundPoint>> {
        if !self.central {
            return Ok(None);
        }
        central_point(eph, self, self.greatest.tt_seconds(), Some(delta_t))
    }

    /// 中心线：从影轴接触地球到离开地球，每隔 `step_s` 秒一个点。非中心食返回空。
    pub fn central_line(&self, eph: &dyn Ephemeris, step_s: f64) -> Result<Vec<GroundPoint>> {
        if !self.central {
            return Ok(Vec::new());
        }
        let tg = self.greatest.tt_seconds();
        let mut before = Vec::new();
        let mut t = tg - step_s;
        while let Some(p) = central_point(eph, self, t, None)? {
            before.push(p);
            t -= step_s;
            if tg - t > 0.25 * DAY {
                break;
            }
        }
        before.reverse();
        let mut t = tg;
        while let Some(p) = central_point(eph, self, t, None)? {
            before.push(p);
            t += step_s;
            if t - tg > 0.25 * DAY {
                break;
            }
        }
        Ok(before)
    }
}

/// 经度归一化到 (−180°, 180°]（供调用方显示用）。
pub fn normalize_longitude_deg(lon: f64) -> f64 {
    let x = lon.rem_euclid(360.0);
    if x > 180.0 { x - 360.0 } else { x }
}
