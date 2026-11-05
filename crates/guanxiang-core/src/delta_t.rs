//! ΔT = TT − UT1。
//!
//! - 1800–2026：查表（[`crate::delta_t_table`]，来自 USNO / IERS），线性插值。
//! - 表前：Espenak & Meeus（2006）多项式。de440s 从 1849 年开始，表前部分实际用不到。
//! - 表后：从表尾值和表尾斜率出发，用三次 Hermite 曲线平滑过渡到
//!   Espenak & Meeus 2050–2150 年公式，与 NASA 日月食星表的外推保持一致。
//!   未来 ΔT 无法精确预测，表后结果应在界面上标为“外推”。

use crate::delta_t_table::TABLE;

const J2000_JD: f64 = 2_451_545.0;
const MJD_OFFSET: f64 = 2_400_000.5;
const DAYS_PER_YEAR: f64 = 365.25;
/// 表后外推与 Espenak & Meeus 公式衔接的时刻：2050.0（MJD）。
const BLEND_END_MJD: f64 = 69_807.0;

/// ΔT（秒）。参数为 TT 儒略日；表以 UT 为自变量，两者相差约 70 秒，对结果的影响小于 1 ms。
pub fn delta_t(tt_jd: f64) -> f64 {
    delta_t_mjd(tt_jd - MJD_OFFSET)
}

/// 该时刻的 ΔT 是否来自外推（表尾之后）。
pub fn is_extrapolated(tt_jd: f64) -> bool {
    tt_jd - MJD_OFFSET > table_end_mjd()
}

/// 表中最后一个值的 MJD。
pub fn table_end_mjd() -> f64 {
    TABLE[TABLE.len() - 1].0
}

fn delta_t_mjd(mjd: f64) -> f64 {
    let (first, last) = (TABLE[0], TABLE[TABLE.len() - 1]);
    if mjd < first.0 {
        return espenak_meeus(mjd_to_year(mjd));
    }
    if mjd <= last.0 {
        return interpolate(mjd);
    }
    if mjd >= BLEND_END_MJD {
        return espenak_meeus(mjd_to_year(mjd));
    }

    // 表尾到 2050 年：三次 Hermite。斜率单位为 秒/天。
    let back = interpolate(last.0 - 365.0);
    let m0 = (last.1 - back) / 365.0;
    let y1 = mjd_to_year(BLEND_END_MJD);
    let p1 = espenak_meeus(y1);
    let m1 = espenak_meeus_2050_slope(y1) / DAYS_PER_YEAR;
    hermite(last.0, last.1, m0, BLEND_END_MJD, p1, m1, mjd)
}

fn interpolate(mjd: f64) -> f64 {
    // 第一个 MJD 大于 mjd 的位置
    let i = TABLE.partition_point(|&(m, _)| m <= mjd);
    if i == 0 {
        return TABLE[0].1;
    }
    if i >= TABLE.len() {
        return TABLE[TABLE.len() - 1].1;
    }
    let (m0, v0) = TABLE[i - 1];
    let (m1, v1) = TABLE[i];
    v0 + (v1 - v0) * (mjd - m0) / (m1 - m0)
}

fn hermite(x0: f64, p0: f64, m0: f64, x1: f64, p1: f64, m1: f64, x: f64) -> f64 {
    let h = x1 - x0;
    let s = (x - x0) / h;
    let (s2, s3) = (s * s, s * s * s);
    (2.0 * s3 - 3.0 * s2 + 1.0) * p0
        + (s3 - 2.0 * s2 + s) * h * m0
        + (-2.0 * s3 + 3.0 * s2) * p1
        + (s3 - s2) * h * m1
}

fn mjd_to_year(mjd: f64) -> f64 {
    2000.0 + (mjd + MJD_OFFSET - J2000_JD) / DAYS_PER_YEAR
}

/// Espenak & Meeus（2006）ΔT 多项式，参数为小数年。只覆盖本库用到的区间。
fn espenak_meeus(y: f64) -> f64 {
    let long_term = |y: f64| {
        let u = (y - 1820.0) / 100.0;
        -20.0 + 32.0 * u * u
    };
    if !(-500.0..2150.0).contains(&y) {
        long_term(y)
    } else if y < 500.0 {
        let u = y / 100.0;
        10583.6 - 1014.41 * u + 33.78311 * u.powi(2) - 5.952053 * u.powi(3) - 0.1798452 * u.powi(4)
            + 0.022174192 * u.powi(5)
            + 0.0090316521 * u.powi(6)
    } else if y < 1600.0 {
        let u = (y - 1000.0) / 100.0;
        1574.2 - 556.01 * u + 71.23472 * u.powi(2) + 0.319781 * u.powi(3)
            - 0.8503463 * u.powi(4)
            - 0.005050998 * u.powi(5)
            + 0.0083572073 * u.powi(6)
    } else if y < 1700.0 {
        let t = y - 1600.0;
        120.0 - 0.9808 * t - 0.01532 * t.powi(2) + t.powi(3) / 7129.0
    } else if y < 1800.0 {
        let t = y - 1700.0;
        8.83 + 0.1603 * t - 0.0059285 * t.powi(2) + 0.00013336 * t.powi(3) - t.powi(4) / 1_174_000.0
    } else if y < 2050.0 {
        // 1800–2050 由表和 Hermite 外推覆盖，正常不会走到这里。
        // 退化为 2005–2050 多项式，保证函数在任何输入下都有定义。
        let t = y - 2000.0;
        62.92 + 0.32217 * t + 0.005589 * t * t
    } else {
        long_term(y) - 0.5628 * (2150.0 - y)
    }
}

/// Espenak & Meeus 2050–2150 公式的导数（秒/年）。
fn espenak_meeus_2050_slope(y: f64) -> f64 {
    64.0 * (y - 1820.0) / 10_000.0 + 0.5628
}

#[cfg(test)]
mod tests {
    use super::*;

    fn jd(y: i32, m: i32, d: i32) -> f64 {
        let (a, b) = sofars::cal::cal2jd(y, m, d).unwrap();
        a + b
    }

    #[test]
    fn table_values() {
        assert!((delta_t(jd(2000, 1, 1)) - 63.8285).abs() < 0.002);
        assert!((delta_t(jd(2020, 1, 1)) - 69.3612).abs() < 0.002);
        assert!((delta_t(jd(1900, 1, 1)) - -2.70).abs() < 0.01);
        assert!((delta_t(jd(1962, 1, 1)) - 33.992).abs() < 0.01);
    }

    #[test]
    fn continuous_at_table_end() {
        let end = table_end_mjd() + MJD_OFFSET;
        let eps = 1e-6;
        assert!((delta_t(end - eps) - delta_t(end + eps)).abs() < 1e-6);
        assert!(!is_extrapolated(end - 1.0));
        assert!(is_extrapolated(end + 1.0));
    }

    #[test]
    fn continuous_at_2050_and_2150() {
        for y in [2050, 2150] {
            let x = jd(y, 1, 1);
            let a = delta_t(x - 1e-4);
            let b = delta_t(x + 1e-4);
            assert!((a - b).abs() < 1e-3, "{y}: {a} vs {b}");
        }
    }

    #[test]
    fn future_is_smooth_and_plausible() {
        let mut prev = delta_t(jd(2027, 1, 1));
        for y in 2028..=2100 {
            let v = delta_t(jd(y, 1, 1));
            assert!(v.is_finite());
            assert!((v - prev).abs() < 5.0, "{y}: {prev} → {v}");
            prev = v;
        }
        let v2100 = delta_t(jd(2100, 1, 1));
        assert!((150.0..250.0).contains(&v2100), "2100: {v2100}");
    }
}
