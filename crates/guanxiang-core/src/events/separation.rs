//! 最小角距（相合、天体接近）。
//!
//! 找出两个天体地心视角距的局部极小，只保留不超过给定角距的事件。

use super::{DAY, Span, apparent_pair, geometric, refine_minimum};
use crate::body::Body;
use crate::ephemeris::Ephemeris;
use crate::error::Result;
use crate::time::Time;

/// 一次角距极小。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SeparationMinimum {
    pub a: Body,
    pub b: Body,
    pub time: Time,
    /// 视角距（弧度）
    pub separation: f64,
}

/// 粗搜步长（天）。相邻两个极小至少相隔数天（月球约一个月），1 天足够分辨。
pub fn default_step_days(_a: Body, _b: Body) -> f64 {
    1.0
}

/// 几何角距与视角距之差的上限：光行差差值约 20″，光行时造成的行星位移可达约 45″（金星），
/// 留足余量取 2′。
const APPARENT_MARGIN: f64 = 2.0 / 60.0 * std::f64::consts::PI / 180.0;

/// 搜索角距不超过 `max_separation`（弧度）的极小。
pub fn search(
    eph: &dyn Ephemeris,
    a: Body,
    b: Body,
    span: Span,
    step_days: f64,
    max_separation: f64,
) -> Result<Vec<SeparationMinimum>> {
    let coarse =
        |tt: f64| -> Result<f64> { Ok(geometric(eph, a, tt)?.angle_to(geometric(eph, b, tt)?)) };
    let fine = |tt: f64| -> Result<f64> {
        let (da, db) = apparent_pair(eph, a, b, tt)?;
        Ok(da.apparent.angle_to(db.apparent))
    };

    let (start, end) = (span.start.tt_seconds(), span.end.tt_seconds());
    let step = step_days * DAY;
    let mut t = start - step;
    let (mut s0, mut s1) = (coarse(t)?, coarse(t + step)?);
    let mut out = Vec::new();
    while t + step < end + step {
        let s2 = coarse(t + 2.0 * step)?;
        if s1 <= s0 && s1 < s2 {
            // 真正的极小不会比采样点低出相邻采样点的变化量太多
            let slack = (s0 - s1).max(s2 - s1);
            if s1 - slack <= max_separation + APPARENT_MARGIN {
                // 先用几何位置找近似极小，再用视位置在附近精修
                let (tc, _) = refine_minimum(coarse, t, t + 2.0 * step, 1.0)?;
                let (tt, sep) = refine_fine(fine, tc)?;
                if sep <= max_separation && span.contains(tt) {
                    out.push(SeparationMinimum {
                        a,
                        b,
                        time: Time::from_tt_seconds(tt),
                        separation: sep,
                    });
                }
            }
        }
        t += step;
        s0 = s1;
        s1 = s2;
    }
    Ok(out)
}

/// 在 `guess` ± 30 分钟内求视角距极小；若结果贴近窗口边缘，以它为中心再求一次。
fn refine_fine(mut fine: impl FnMut(f64) -> Result<f64>, guess: f64) -> Result<(f64, f64)> {
    const HALF: f64 = 1800.0;
    let mut center = guess;
    for _ in 0..4 {
        let (tt, sep) = refine_minimum(&mut fine, center - HALF, center + HALF, 1e-2)?;
        if (tt - center).abs() < HALF - 1.0 {
            return Ok((tt, sep));
        }
        center = tt;
    }
    Err(crate::error::Error::InvalidBracket("角距极小精修不收敛"))
}
