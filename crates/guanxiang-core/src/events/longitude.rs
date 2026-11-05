//! 黄经事件：合、冲。
//!
//! 定义：地心视黄经（真黄道、真春分点）之差等于 0（合）或 180°（冲），与天文年历和 Skyfield 相同。

use std::f64::consts::PI;

use super::{
    DAY, Span, apparent_pair, coarse_lon_lat, ecliptic_of_date_matrix, lon_lat, mul, refine_root,
    refine_root_secant, wrap_pi,
};
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::Result;
use crate::time::Time;

/// 合（黄经差 0）或冲（黄经差 180°）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Aspect {
    Conjunction,
    Opposition,
}

impl Aspect {
    fn offset(self) -> f64 {
        match self {
            Aspect::Conjunction => 0.0,
            Aspect::Opposition => PI,
        }
    }
}

/// 一次合或冲。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LongitudeEvent {
    pub aspect: Aspect,
    pub a: Body,
    pub b: Body,
    pub time: Time,
    /// 此刻两者的视角距（弧度）
    pub separation: f64,
    /// 黄纬差 β_a − β_b（弧度）；对冲而言是 β_a + β_b
    pub latitude_difference: f64,
    /// `a` 的光行时修正距离（km）
    pub distance_a_km: f64,
    /// `b` 的光行时修正距离（km）
    pub distance_b_km: f64,
}

/// 粗搜步长（天）。黄经差在一个步长内不能变化半圈以上，也不能来回穿越零点。
pub fn default_step_days(a: Body, b: Body) -> f64 {
    if a == Body::Moon || b == Body::Moon {
        1.0
    } else {
        2.0
    }
}

/// 粗搜得到的候选：(区间起点, 区间终点)，单位为 TT 秒。
pub(crate) fn coarse_brackets(
    eph: &dyn Ephemeris,
    a: Body,
    b: Body,
    aspect: Aspect,
    span: Span,
    step_days: f64,
) -> Result<Vec<(f64, f64)>> {
    let g = |tt: f64| -> Result<f64> {
        let (la, _) = coarse_lon_lat(eph, a, tt)?;
        let (lb, _) = coarse_lon_lat(eph, b, tt)?;
        Ok(wrap_pi(la - lb - aspect.offset()))
    };
    let (start, end) = (span.start.tt_seconds(), span.end.tt_seconds());
    let step = step_days * DAY;
    // 两端各多看一个步长，避免漏掉落在边界附近、精修后仍在范围内的事件
    let mut t0 = start - step;
    let mut g0 = g(t0)?;
    let mut out = Vec::new();
    while t0 < end + step {
        let t1 = t0 + step;
        let g1 = g(t1)?;
        if g0.signum() != g1.signum() && (g1 - g0).abs() < PI {
            out.push((t0, t1));
        }
        t0 = t1;
        g0 = g1;
    }
    Ok(out)
}

/// 用简化模型在粗搜区间内求根（秒级）。
pub(crate) fn coarse_root(
    eph: &dyn Ephemeris,
    a: Body,
    b: Body,
    aspect: Aspect,
    bracket: (f64, f64),
) -> Result<f64> {
    let g = |tt: f64| -> Result<f64> {
        let (la, _) = coarse_lon_lat(eph, a, tt)?;
        let (lb, _) = coarse_lon_lat(eph, b, tt)?;
        Ok(wrap_pi(la - lb - aspect.offset()))
    };
    let mid = 0.5 * (bracket.0 + bracket.1);
    refine_root(
        g,
        mid,
        0.5 * (bracket.1 - bracket.0),
        bracket.1 - bracket.0,
        1.0,
    )
}

/// 用完整视位置精修，返回事件。
pub(crate) fn refine(
    eph: &dyn Ephemeris,
    a: Body,
    b: Body,
    aspect: Aspect,
    guess: f64,
) -> Result<LongitudeEvent> {
    let m = ecliptic_of_date_matrix(&Time::from_tt_seconds(guess));
    let f = |tt: f64| -> Result<f64> {
        let (da, db) = apparent_pair(eph, a, b, tt)?;
        let (la, _) = lon_lat(mul(&m, da.apparent));
        let (lb, _) = lon_lat(mul(&m, db.apparent));
        Ok(wrap_pi(la - lb - aspect.offset()))
    };
    // 光行时和光行差使视黄经与几何黄经差几十角秒，对应的时间差最多几十分钟
    let tt = refine_root_secant(f, guess, 1e-3, 2.0 * DAY)?;

    let (da, db) = apparent_pair(eph, a, b, tt)?;
    let (_, ba) = lon_lat(mul(&m, da.apparent));
    let (_, bb) = lon_lat(mul(&m, db.apparent));
    Ok(LongitudeEvent {
        aspect,
        a,
        b,
        time: Time::from_tt_seconds(tt),
        separation: da.apparent.angle_to(db.apparent),
        latitude_difference: match aspect {
            Aspect::Conjunction => ba - bb,
            Aspect::Opposition => ba + bb,
        },
        distance_a_km: da.distance_km,
        distance_b_km: db.distance_km,
    })
}

/// 搜索 `a` 与 `b` 在 `span` 内的合或冲。
pub fn search(
    eph: &dyn Ephemeris,
    a: Body,
    b: Body,
    aspect: Aspect,
    span: Span,
    step_days: f64,
) -> Result<Vec<LongitudeEvent>> {
    let mut out = Vec::new();
    for bracket in coarse_brackets(eph, a, b, aspect, span, step_days)? {
        let guess = coarse_root(eph, a, b, aspect, bracket)?;
        let ev = refine(eph, a, b, aspect, guess)?;
        if span.contains(ev.time.tt_seconds()) {
            out.push(ev);
        }
    }
    Ok(out)
}
