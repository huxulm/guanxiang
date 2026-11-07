//! 天文事件搜索（M2 起）。
//!
//! 统一流程（D2）：
//!
//! 1. **粗搜**：按固定步长计算几何位置（不含光行时、光行差、岁差章动），找出符号变化或局部极小。
//! 2. **初步精修**：在粗搜区间内用同一个简化模型求根，得到秒级的近似时刻。
//! 3. **精修**：在近似时刻附近用完整视位置求根。黄道矩阵（岁差章动）在事件附近一天内变化可以
//!    忽略，所以每个事件只算一次。
//!
//! 所有事件都是**地心**的；本地是否可见由 [`visibility`] 另行判断。

pub mod almanac;
pub mod catalog;
pub mod local_eclipse;
pub mod longitude;
pub mod lunar_eclipse;
pub mod occultation;
pub mod saros;
pub mod sat_transit;
pub mod separation;
pub mod solar_eclipse;
pub mod transit;
pub mod visibility;

use sofars::pnp::pn06a;

use crate::astrometry;
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::{Error, Result};
use crate::geometry::Vec3;
use crate::time::{Tdb, Time};

pub(crate) const DAY: f64 = 86_400.0;

/// J2000 平黄赤交角（IAU 2006），粗搜用。
const OBLIQUITY_J2000: f64 = 84_381.406 / 206_264.806_247_096_36;

/// 搜索时间范围。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Span {
    pub start: Time,
    pub end: Time,
}

impl Span {
    pub fn new(start: Time, end: Time) -> Result<Self> {
        if end.tt_seconds() <= start.tt_seconds() {
            return Err(Error::InvalidBracket("结束时间必须晚于开始时间"));
        }
        Ok(Self { start, end })
    }

    fn contains(&self, t: f64) -> bool {
        (self.start.tt_seconds()..=self.end.tt_seconds()).contains(&t)
    }
}

/// 3×3 矩阵乘向量。
fn mul(m: &[[f64; 3]; 3], v: Vec3) -> Vec3 {
    Vec3::new(
        m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
        m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
        m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z,
    )
}

/// GCRS → 真黄道、真春分点（与 Skyfield 的 `ecliptic_frame` 相同）。
pub fn ecliptic_of_date_matrix(t: &Time) -> [[f64; 3]; 3] {
    let (a, b) = t.tt_jd_parts();
    // pn06a 一次给出章动和岁差章动矩阵，避免重复计算 IAU 2000A 章动
    let (_dpsi, deps, epsa, _rb, _rp, _rbp, _rn, rbpn) = pn06a(a, b);
    rotate_x_rows(&rbpn, epsa + deps)
}

/// 返回 R1(eps) · m。
fn rotate_x_rows(m: &[[f64; 3]; 3], eps: f64) -> [[f64; 3]; 3] {
    let (s, c) = eps.sin_cos();
    let mut out = [[0.0; 3]; 3];
    for j in 0..3 {
        out[0][j] = m[0][j];
        out[1][j] = c * m[1][j] + s * m[2][j];
        out[2][j] = -s * m[1][j] + c * m[2][j];
    }
    out
}

/// 黄经、黄纬（弧度）。
fn lon_lat(v: Vec3) -> (f64, f64) {
    (v.y.atan2(v.x), v.z.atan2((v.x * v.x + v.y * v.y).sqrt()))
}

/// 归一化到 (−π, π]。
pub(crate) fn wrap_pi(x: f64) -> f64 {
    let y = x.rem_euclid(std::f64::consts::TAU);
    if y > std::f64::consts::PI {
        y - std::f64::consts::TAU
    } else {
        y
    }
}

/// 粗搜用的几何地心位置（km，ICRF），时间直接把 TT 当 TDB（差 < 2 ms）。
fn geometric(eph: &dyn Ephemeris, body: Body, tt: f64) -> Result<Vec3> {
    eph.position(body, Body::Earth, Tdb(tt))
}

/// 粗搜用的 J2000 平黄道黄经黄纬。
fn coarse_lon_lat(eph: &dyn Ephemeris, body: Body, tt: f64) -> Result<(f64, f64)> {
    let v = geometric(eph, body, tt)?;
    let (s, c) = OBLIQUITY_J2000.sin_cos();
    let e = Vec3::new(v.x, c * v.y + s * v.z, -s * v.y + c * v.z);
    Ok(lon_lat(e))
}

/// 同一时刻两个天体的地心视方向。
fn apparent_pair(
    eph: &dyn Ephemeris,
    a: Body,
    b: Body,
    tt: f64,
) -> Result<(astrometry::Direction, astrometry::Direction)> {
    astrometry::geocentric_direction_pair(eph, a, b, &Time::from_tt_seconds(tt))
}

/// 从很接近根的初值出发用割线法求根；不收敛时退回扩区间 + Brent。
///
/// 精修时函数近似线性、初值误差通常只有几分钟，割线法 3–4 次求值即可，
/// 比先找符号变化再用 Brent 少一半以上的求值。
fn refine_root_secant(
    mut f: impl FnMut(f64) -> Result<f64>,
    guess: f64,
    tol: f64,
    max_distance: f64,
) -> Result<f64> {
    let (mut x0, mut x1) = (guess, guess + 60.0);
    let (mut f0, mut f1) = (f(x0)?, f(x1)?);
    for _ in 0..12 {
        if f1 == 0.0 {
            return Ok(x1);
        }
        if f1 == f0 {
            break;
        }
        let x2 = x1 - f1 * (x1 - x0) / (f1 - f0);
        if !x2.is_finite() || (x2 - guess).abs() > max_distance {
            break;
        }
        if (x2 - x1).abs() < tol {
            return Ok(x2);
        }
        (x0, f0) = (x1, f1);
        x1 = x2;
        f1 = f(x1)?;
    }
    refine_root(f, guess, 600.0, max_distance, tol)
}

/// 在 `f` 的根附近扩大区间直到出现符号变化，再用 Brent 法求根。
fn refine_root(
    mut f: impl FnMut(f64) -> Result<f64>,
    guess: f64,
    half_width: f64,
    max_half_width: f64,
    tol: f64,
) -> Result<f64> {
    let mut w = half_width;
    loop {
        let (a, b) = (guess - w, guess + w);
        let (fa, fb) = (f(a)?, f(b)?);
        if fa.signum() != fb.signum() || fa == 0.0 || fb == 0.0 {
            // Brent 需要普通闭包；把错误留到外面处理
            let mut err = None;
            let root = crate::search::find_root(
                |x| match f(x) {
                    Ok(v) => v,
                    Err(e) => {
                        err.get_or_insert(e);
                        0.0
                    }
                },
                a,
                b,
                tol,
            )?;
            return match err {
                Some(e) => Err(e),
                None => Ok(root.x),
            };
        }
        if w >= max_half_width {
            return Err(Error::InvalidBracket("精修时找不到符号变化"));
        }
        w *= 4.0;
    }
}

/// 在 `[a, b]` 内用 Brent 法求极小值，返回 (x, f(x))。
///
/// 以区间中点为原点求解：Brent 极小值法的容差含 √ε·|x| 项，直接用 J2000 起算的秒数（~10⁹）
/// 会把精度限制在十几秒。
fn refine_minimum(
    mut f: impl FnMut(f64) -> Result<f64>,
    a: f64,
    b: f64,
    tol: f64,
) -> Result<(f64, f64)> {
    let origin = 0.5 * (a + b);
    let mut err = None;
    let m = crate::search::find_minimum(
        |u| match f(origin + u) {
            Ok(v) => v,
            Err(e) => {
                err.get_or_insert(e);
                f64::INFINITY
            }
        },
        a - origin,
        b - origin,
        tol,
    )?;
    match err {
        Some(e) => Err(e),
        None => Ok((origin + m.x, m.f)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wrap() {
        use std::f64::consts::PI;
        assert!((wrap_pi(3.0 * PI) - PI).abs() < 1e-12);
        assert!((wrap_pi(-0.5) + 0.5).abs() < 1e-15);
        assert!((wrap_pi(2.0 * PI + 0.25) - 0.25).abs() < 1e-12);
    }
}
