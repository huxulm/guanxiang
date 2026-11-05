//! 时间类型。
//!
//! M0 只提供 TDB 时刻。UTC / TT / UT1 转换和 ΔT 在 M1 用 sofars 实现（D3）。

/// J2000.0 的儒略日（TDB）。
pub const J2000_JD: f64 = 2_451_545.0;
pub const SECONDS_PER_DAY: f64 = 86_400.0;

/// TDB 时刻，以 J2000.0 TDB 起算的秒数表示（与 SPICE 的 ET 相同）。
#[derive(Debug, Clone, Copy, PartialEq, PartialOrd, Default)]
pub struct Tdb(pub f64);

impl Tdb {
    pub const J2000: Tdb = Tdb(0.0);

    pub fn from_jd(jd: f64) -> Self {
        Tdb((jd - J2000_JD) * SECONDS_PER_DAY)
    }

    pub fn to_jd(self) -> f64 {
        J2000_JD + self.0 / SECONDS_PER_DAY
    }

    pub fn seconds_past_j2000(self) -> f64 {
        self.0
    }

    pub fn add_seconds(self, s: f64) -> Self {
        Tdb(self.0 + s)
    }

    pub fn add_days(self, d: f64) -> Self {
        Tdb(self.0 + d * SECONDS_PER_DAY)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jd_round_trip() {
        assert_eq!(Tdb::from_jd(J2000_JD), Tdb::J2000);
        let t = Tdb::from_jd(2_460_000.25);
        assert!((t.to_jd() - 2_460_000.25).abs() < 1e-9);
        assert_eq!(Tdb::J2000.add_days(1.0).0, SECONDS_PER_DAY);
    }
}
