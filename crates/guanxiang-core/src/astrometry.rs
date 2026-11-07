//! 视位置与站心位置。
//!
//! 计算流程（与 SOFA / NOVAS 的做法一致）：
//!
//! 1. 观测者在 BCRS 中的位置和速度：地心 = 地球质心状态；站心再加上测站的 GCRS 位置和速度
//!    （WGS84，经 ERA 和 CIO 变换，忽略极移）。
//! 2. 光行时迭代：目标在 `t − τ` 的位置减去观测者在 `t` 的位置。
//! 3. 太阳引力偏折（SOFA `ld`）。目标为太阳时跳过。
//! 4. 周年光行差（含周日光行差，SOFA `ab`）。
//! 5. 用 IAU 2006/2000A 岁差章动（含框架偏差）转到真赤道和真春分点。
//!
//! 地平坐标由 CIRS 赤经和 ERA 求时角，不含大气折射；需要时用 [`refraction`]。

use std::f64::consts::TAU;

use sofars::astro::{ab, ld, ldsun, pvtob};
use sofars::coords::hd2ae;
use sofars::erst::era00;
use sofars::pnp::{c2i06a, pnm06a, sp00};
use sofars::vm::{c2s, rxp, trxp};

use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::{Error, Result};
use crate::geometry::Vec3;
use crate::observer::Observer;
use crate::stars::Star;
use crate::time::Time;

/// 光速（km/s）
pub const C_KM_S: f64 = 299_792.458;
/// 天文单位（km）
pub const AU_KM: f64 = 149_597_870.7;

/// 赤道坐标（弧度）。赤经在 `[0, 2π)`。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Equatorial {
    pub ra: f64,
    pub dec: f64,
}

impl Equatorial {
    fn from_vector(v: [f64; 3]) -> Self {
        let (ra, dec) = c2s(&v);
        Self {
            ra: ra.rem_euclid(TAU),
            dec,
        }
    }
}

/// 地平坐标（弧度）。方位角从北向东量，`[0, 2π)`；高度角不含大气折射。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Horizontal {
    pub azimuth: f64,
    pub altitude: f64,
}

/// 地心或站心的视位置。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Place {
    /// 天体测量位置：只改正光行时，ICRF。
    pub astrometric: Equatorial,
    /// 视位置：真赤道、真春分点。
    pub apparent: Equatorial,
    /// 视方向单位向量（GCRS 轴，已含偏折和光行差），用于计算天体间的视角距。
    pub apparent_gcrs: Vec3,
    /// 光行时修正后的距离（km）。
    pub distance_km: f64,
    /// 光行时（秒）。
    pub light_time_s: f64,
}

/// 站心视位置及地平坐标。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TopocentricPlace {
    pub place: Place,
    pub horizontal: Horizontal,
    /// 本地时角（弧度，`(-π, π]`，西正），基于 CIRS 赤经和 ERA。
    pub hour_angle: f64,
}

/// 地心视位置。
pub fn geocentric(eph: &dyn Ephemeris, body: Body, t: &Time) -> Result<Place> {
    place(eph, body, t, Vec3::ZERO, Vec3::ZERO)
}

/// 站心视位置和地平坐标（不含大气折射）。
pub fn topocentric(
    eph: &dyn Ephemeris,
    body: Body,
    t: &Time,
    obs: &Observer,
) -> Result<TopocentricPlace> {
    let (uta, utb) = t.ut1_jd_parts();
    let era = era00(uta, utb);
    let rc2i = c2i_matrix(t);
    let (pos, vel) = observer_gcrs(t, obs, &rc2i);

    let place = place(eph, body, t, pos, vel)?;

    // CIRS 赤经 → 时角 → 地平
    let mut cirs = [0.0; 3];
    rxp(&rc2i, &place.apparent_gcrs.into(), &mut cirs);
    let (ra_cirs, dec) = c2s(&cirs);
    let ha = sofars::vm::anpm(era + obs.longitude - ra_cirs);
    let [az, alt] = hd2ae(ha, dec, obs.latitude);

    Ok(TopocentricPlace {
        place,
        horizontal: Horizontal {
            azimuth: az.rem_euclid(TAU),
            altitude: alt,
        },
        hour_angle: ha,
    })
}

/// 天体的地下点：地心视方向在地球上的投影，返回（纬度，经度），弧度，经度东正、`(-π, π]`。
/// 地球按球体处理（纬度是地心纬度，即 CIRS 赤纬），忽略极移。月食可见区域图用它。
pub fn sub_body_point(eph: &dyn Ephemeris, body: Body, t: &Time) -> Result<(f64, f64)> {
    let p = place(eph, body, t, Vec3::ZERO, Vec3::ZERO)?;
    let mut cirs = [0.0; 3];
    rxp(&c2i_matrix(t), &p.apparent_gcrs.into(), &mut cirs);
    let (ra_cirs, dec) = c2s(&cirs);
    let (uta, utb) = t.ut1_jd_parts();
    Ok((dec, sofars::vm::anpm(ra_cirs - era00(uta, utb))))
}

/// GCRS → CIRS 矩阵（IAU 2006/2000A）。几小时内变化在毫角秒量级，同一事件内可复用。
pub fn c2i_matrix(t: &Time) -> [[f64; 3]; 3] {
    let (tta, ttb) = t.tt_jd_parts();
    c2i06a(tta, ttb)
}

/// 测站在 GCRS 中相对地心的位置（km）和速度（km/s），WGS84，忽略极移。
/// `rc2i` 为 [`c2i_matrix`] 的结果；地球自转角由 `t` 的 UT1 计算。
pub fn observer_gcrs(t: &Time, obs: &Observer, rc2i: &[[f64; 3]; 3]) -> (Vec3, Vec3) {
    let (tta, ttb) = t.tt_jd_parts();
    let (uta, utb) = t.ut1_jd_parts();
    let mut pv = [[0.0; 3]; 2];
    pvtob(
        obs.longitude,
        obs.latitude,
        obs.height,
        0.0,
        0.0,
        sp00(tta, ttb),
        era00(uta, utb),
        &mut pv,
    );
    let mut pos = [0.0; 3];
    let mut vel = [0.0; 3];
    trxp(rc2i, &pv[0], &mut pos);
    trxp(rc2i, &pv[1], &mut vel);
    (Vec3::from(pos) * 1e-3, Vec3::from(vel) * 1e-3)
}

/// 同一时刻、同一观测者看两个天体的视方向。`geo_pos`、`geo_vel` 为观测者相对地心的
/// GCRS 位置和速度（地心观测传零向量，站心观测用 [`observer_gcrs`]）。
pub fn direction_pair_from(
    eph: &dyn Ephemeris,
    a: Body,
    b: Body,
    t: &Time,
    geo_pos: Vec3,
    geo_vel: Vec3,
) -> Result<(Direction, Direction)> {
    let state = ObserverState::new(eph, t, geo_pos, geo_vel)?;
    Ok((state.direction(eph, a)?, state.direction(eph, b)?))
}

/// 同一时刻、同一观测者看恒星和某个天体的视方向（恒星只返回单位向量）。
pub fn star_and_body_from(
    eph: &dyn Ephemeris,
    star: &Star,
    body: Body,
    t: &Time,
    geo_pos: Vec3,
    geo_vel: Vec3,
) -> Result<(Vec3, Direction)> {
    let state = ObserverState::new(eph, t, geo_pos, geo_vel)?;
    Ok((state.star(star), state.direction(eph, body)?))
}

/// 视方向（GCRS 轴，未做岁差章动）。事件搜索在精修阶段反复调用它，
/// 岁差章动矩阵由调用方按需计算一次后复用。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Direction {
    /// 视方向单位向量（含偏折和光行差）
    pub apparent: Vec3,
    /// 天体测量方向单位向量（只改正光行时，ICRF）
    pub astrometric: Vec3,
    /// 光行时修正后的距离（km）
    pub distance_km: f64,
    /// 光行时（秒）
    pub light_time_s: f64,
}

/// 地心视方向。
pub fn geocentric_direction(eph: &dyn Ephemeris, body: Body, t: &Time) -> Result<Direction> {
    direction(eph, body, t, Vec3::ZERO, Vec3::ZERO)
}

/// 同一时刻两个天体的地心视方向（共用地球和太阳的状态，比分别调用少查几次星历）。
pub fn geocentric_direction_pair(
    eph: &dyn Ephemeris,
    a: Body,
    b: Body,
    t: &Time,
) -> Result<(Direction, Direction)> {
    let state = ObserverState::new(eph, t, Vec3::ZERO, Vec3::ZERO)?;
    Ok((state.direction(eph, a)?, state.direction(eph, b)?))
}

/// `geo_pos`、`geo_vel` 为观测者相对地心的 GCRS 位置（km）和速度（km/s）。
fn place(eph: &dyn Ephemeris, body: Body, t: &Time, geo_pos: Vec3, geo_vel: Vec3) -> Result<Place> {
    let d = direction(eph, body, t, geo_pos, geo_vel)?;

    // 岁差章动（含框架偏差）
    let (tta, ttb) = t.tt_jd_parts();
    let rbpn = pnm06a(tta, ttb);
    let mut of_date = [0.0; 3];
    rxp(&rbpn, &d.apparent.into(), &mut of_date);

    Ok(Place {
        astrometric: Equatorial::from_vector(d.astrometric.into()),
        apparent: Equatorial::from_vector(of_date),
        apparent_gcrs: d.apparent,
        distance_km: d.distance_km,
        light_time_s: d.light_time_s,
    })
}

fn direction(
    eph: &dyn Ephemeris,
    body: Body,
    t: &Time,
    geo_pos: Vec3,
    geo_vel: Vec3,
) -> Result<Direction> {
    ObserverState::new(eph, t, geo_pos, geo_vel)?.direction(eph, body)
}

/// 观测时刻的观测者和太阳状态（BCRS）。
struct ObserverState {
    tdb: crate::time::Tdb,
    obs_pos: Vec3,
    obs_vel: Vec3,
    sun_now: Vec3,
}

impl ObserverState {
    fn new(eph: &dyn Ephemeris, t: &Time, geo_pos: Vec3, geo_vel: Vec3) -> Result<Self> {
        let ssb = Body::SolarSystemBarycenter;
        let tdb = t.tdb();
        let (earth_pos, earth_vel) = eph.state(Body::Earth, ssb, tdb)?;
        Ok(Self {
            tdb,
            obs_pos: earth_pos + geo_pos,
            obs_vel: earth_vel + geo_vel,
            sun_now: eph.position(Body::Sun, ssb, tdb)?,
        })
    }

    /// 恒星的视方向：自行、视差、太阳引力偏折、光行差。
    fn star(&self, star: &Star) -> Vec3 {
        let u = star.barycentric_direction(self.tdb);
        let p = match star.distance_km() {
            Some(d) => (u * d - self.obs_pos).unit(),
            None => u,
        };
        let sun_to_obs = self.obs_pos - self.sun_now;
        let em = sun_to_obs.norm() / AU_KM;
        let deflected = ldsun(p.into(), sun_to_obs.unit().into(), em);
        let v = self.obs_vel * (1.0 / C_KM_S);
        let bm1 = (1.0 - v.dot(v)).sqrt();
        Vec3::from(ab(&deflected, &v.into(), em, bm1))
    }

    fn direction(&self, eph: &dyn Ephemeris, body: Body) -> Result<Direction> {
        if matches!(body, Body::Earth | Body::SolarSystemBarycenter) {
            return Err(Error::Unsupported("不能从地球上观测这个目标"));
        }
        let ssb = Body::SolarSystemBarycenter;
        let (tdb, obs_pos, obs_vel) = (self.tdb, self.obs_pos, self.obs_vel);

        // 光行时迭代（太阳的当前位置已知，可省一次查询）
        let mut tau = 0.0;
        let mut target = if body == Body::Sun {
            self.sun_now
        } else {
            eph.position(body, ssb, tdb)?
        };
        for _ in 0..10 {
            let new_tau = (target - obs_pos).norm() / C_KM_S;
            let done = (new_tau - tau).abs() < 1e-9;
            tau = new_tau;
            target = eph.position(body, ssb, tdb.add_seconds(-tau))?;
            if done {
                break;
            }
        }
        let p = target - obs_pos;
        let distance_km = p.norm();
        let p_unit = p.unit();

        // 太阳引力偏折
        let sun_to_obs = obs_pos - self.sun_now;
        let em = sun_to_obs.norm() / AU_KM;
        let deflected: [f64; 3] = if body == Body::Sun {
            p_unit.into()
        } else {
            let sun_then = eph.position(Body::Sun, ssb, tdb.add_seconds(-tau))?;
            let q = (target - sun_then).unit();
            let dlim = 1e-6 / em.max(1.0).powi(2);
            ld(
                1.0,
                p_unit.into(),
                q.into(),
                sun_to_obs.unit().into(),
                em,
                dlim,
            )
        };

        // 光行差
        let v = obs_vel * (1.0 / C_KM_S);
        let bm1 = (1.0 - v.dot(v)).sqrt();
        let aberrated = ab(&deflected, &v.into(), em, bm1);

        Ok(Direction {
            apparent: Vec3::from(aberrated),
            astrometric: p_unit,
            distance_km,
            light_time_s: tau,
        })
    }
}

/// 大气折射（弧度），Sæmundsson 公式（Meeus《天文算法》16.4）。
///
/// `true_altitude` 为几何高度角（弧度）。返回值加到几何高度角上得到视高度角。
/// 公式在 −1° 以上有效；−1° 到 −5° 之间线性减到 0，更低时返回 0（地平线下折射没有意义，
/// 这样处理只是为了函数连续）。
pub fn refraction(true_altitude: f64, pressure_hpa: f64, temperature_c: f64) -> f64 {
    let h = true_altitude.to_degrees();
    let saemundsson = |h: f64| 1.02 / (h + 10.3 / (h + 5.11)).to_radians().tan();
    let r_arcmin = if h >= -1.0 {
        saemundsson(h)
    } else if h > -5.0 {
        saemundsson(-1.0) * (h + 5.0) / 4.0
    } else {
        0.0
    };
    let scale = (pressure_hpa / 1010.0) * (283.0 / (273.0 + temperature_c));
    (r_arcmin * scale / 60.0).to_radians()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refraction_values() {
        // 几何高度 0° 约 29′（对应视高度约 0.5°，视地平处的 34′ 是 Bennett 公式的值），
        // 10° 约 5.4′，天顶为 0
        let r0 = refraction(0.0, 1010.0, 10.0).to_degrees() * 60.0;
        assert!((r0 - 29.0).abs() < 0.1, "{r0}");
        let r10 = refraction(10f64.to_radians(), 1010.0, 10.0).to_degrees() * 60.0;
        assert!((r10 - 5.41).abs() < 0.05, "{r10}");
        let r90 = refraction(90f64.to_radians(), 1010.0, 10.0).to_degrees() * 3600.0;
        assert!(r90.abs() < 1.0, "{r90}");
        // 地平线下逐渐减到 0，且连续
        assert_eq!(refraction(-10f64.to_radians(), 1010.0, 10.0), 0.0);
        let a = refraction(-1.0f64.to_radians() + 1e-9, 1010.0, 10.0);
        let b = refraction(-1.0f64.to_radians() - 1e-9, 1010.0, 10.0);
        assert!((a - b).abs() < 1e-9);
    }
}
