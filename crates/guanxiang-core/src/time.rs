//! 时间尺度（D3：用 sofars 实现）。
//!
//! [`Time`] 内部以 TT 为准（J2000.0 TT 起算的秒数），同时记录该时刻的 ΔT = TT − UT1。
//!
//! - UTC → TAI → TT 由 SOFA 处理，含闰秒和 1960–1972 年的“橡皮秒”。
//! - 1960 年以前没有 UTC，输入的民用时按 UT1 处理（TT = UT1 + ΔT）。
//! - TDB − TT 用 SOFA `dtdb`（地心，量级 1.7 ms）。
//! - ΔT 默认取 [`crate::delta_t`] 的模型，可用 [`Time::with_delta_t`] 指定（例如来自 IERS 数据或对照测试）。

use std::fmt;
use std::str::FromStr;

use sofars::ts;

use crate::delta_t;
use crate::error::{Error, Result};

/// J2000.0 的儒略日。
pub const J2000_JD: f64 = 2_451_545.0;
pub const SECONDS_PER_DAY: f64 = 86_400.0;
/// UTC 从 1960 年开始定义。
const UTC_START_JD: f64 = 2_436_934.5; // 1960-01-01 0h

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

/// 公历日期时间（不带时区）。1582 年以前也按公历外推。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DateTime {
    pub year: i32,
    pub month: u32,
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
    pub second: f64,
}

impl DateTime {
    pub fn new(
        year: i32,
        month: u32,
        day: u32,
        hour: u32,
        minute: u32,
        second: f64,
    ) -> Result<Self> {
        let dt = Self {
            year,
            month,
            day,
            hour,
            minute,
            second,
        };
        // 秒允许到 61（闰秒日由 SOFA 进一步校验）
        let ok = (1..=12).contains(&month)
            && (1..=31).contains(&day)
            && hour < 24
            && minute < 60
            && (0.0..61.0).contains(&second);
        if !ok {
            return Err(Error::InvalidTime(format!("日期时间超出范围：{dt}")));
        }
        sofars::cal::cal2jd(year, month as i32, day as i32)
            .map_err(|_| Error::InvalidTime(format!("无效日期：{dt}")))?;
        Ok(dt)
    }
}

impl fmt::Display for DateTime {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:06.3}",
            self.year, self.month, self.day, self.hour, self.minute, self.second
        )
    }
}

impl FromStr for DateTime {
    type Err = Error;

    /// 接受 `YYYY-MM-DD`、`YYYY-MM-DDTHH:MM`、`YYYY-MM-DD HH:MM:SS.sss`，末尾可带 `Z`。
    fn from_str(s: &str) -> Result<Self> {
        let bad = || Error::InvalidTime(format!("无法解析时间：{s}"));
        let t = s.trim().trim_end_matches(['Z', 'z']).trim();
        let (date, time) = match t.split_once(['T', 't', ' ']) {
            Some((d, tm)) => (d, Some(tm.trim())),
            None => (t, None),
        };
        let mut dp = date.splitn(3, '-');
        let year: i32 = dp.next().ok_or_else(bad)?.parse().map_err(|_| bad())?;
        let month: u32 = dp.next().ok_or_else(bad)?.parse().map_err(|_| bad())?;
        let day: u32 = dp.next().ok_or_else(bad)?.parse().map_err(|_| bad())?;
        let (mut hour, mut minute, mut second) = (0, 0, 0.0);
        if let Some(tm) = time {
            let mut tp = tm.split(':');
            hour = tp.next().ok_or_else(bad)?.parse().map_err(|_| bad())?;
            minute = tp.next().ok_or_else(bad)?.parse().map_err(|_| bad())?;
            if let Some(sec) = tp.next() {
                second = sec.parse().map_err(|_| bad())?;
            }
            if tp.next().is_some() {
                return Err(bad());
            }
        }
        DateTime::new(year, month, day, hour, minute, second)
    }
}

/// 一个时刻。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Time {
    /// J2000.0 TT 起算的秒数
    tt: f64,
    /// TT − UT1（秒）
    delta_t: f64,
}

impl Time {
    pub fn from_tt_seconds(tt: f64) -> Self {
        Self {
            tt,
            delta_t: delta_t::delta_t(J2000_JD + tt / SECONDS_PER_DAY),
        }
    }

    pub fn from_tt_jd(jd: f64) -> Self {
        Self::from_tt_seconds((jd - J2000_JD) * SECONDS_PER_DAY)
    }

    /// 由 TDB 求 TT（TDB − TT 很小，迭代两次即收敛到 ns 级）。
    pub fn from_tdb(tdb: Tdb) -> Self {
        let mut t = Self::from_tt_seconds(tdb.0);
        for _ in 0..2 {
            let corr = tdb.0 - t.tdb().0;
            t = Self::from_tt_seconds(t.tt + corr);
        }
        t
    }

    /// 由 UT1 儒略日求时刻。
    pub fn from_ut1_jd(jd: f64) -> Self {
        let ut1 = (jd - J2000_JD) * SECONDS_PER_DAY;
        let mut t = Self::from_tt_seconds(ut1);
        for _ in 0..3 {
            t = Self::from_tt_seconds(ut1 + t.delta_t);
        }
        t
    }

    /// 由 UTC 求时刻。1960 年以前按 UT1 处理。
    pub fn from_utc(dt: &DateTime) -> Result<Self> {
        let err = |code: i32| Error::InvalidTime(format!("SOFA 状态 {code}：{dt}"));
        let (y, mo, d) = (dt.year, dt.month as i32, dt.day as i32);
        let (h, mi) = (dt.hour as i32, dt.minute as i32);

        let (d1, d2) = ts::dtf2d("UTC", y, mo, d, h, mi, dt.second).map_err(err)?;
        if d1 + d2 < UTC_START_JD {
            let (u1, u2) = ts::dtf2d("UT1", y, mo, d, h, mi, dt.second).map_err(err)?;
            return Ok(Self::from_ut1_jd(u1 + u2));
        }
        let (a1, a2) = ts::utctai(d1, d2).map_err(err)?;
        let (t1, t2) = ts::taitt(a1, a2).map_err(err)?;
        Ok(Self::from_tt_seconds(
            ((t1 - J2000_JD) + t2) * SECONDS_PER_DAY,
        ))
    }

    /// 指定本时刻的 ΔT（秒）。只作用于这个时刻；`add_seconds` 之后重新使用模型值。
    pub fn with_delta_t(self, delta_t: f64) -> Self {
        Self { delta_t, ..self }
    }

    pub fn add_seconds(self, s: f64) -> Self {
        Self::from_tt_seconds(self.tt + s)
    }

    pub fn tt_seconds(&self) -> f64 {
        self.tt
    }

    pub fn tt_jd(&self) -> f64 {
        J2000_JD + self.tt / SECONDS_PER_DAY
    }

    /// TT 两段式儒略日，供 SOFA 使用。
    pub fn tt_jd_parts(&self) -> (f64, f64) {
        (J2000_JD, self.tt / SECONDS_PER_DAY)
    }

    /// UT1 两段式儒略日。
    pub fn ut1_jd_parts(&self) -> (f64, f64) {
        (J2000_JD, (self.tt - self.delta_t) / SECONDS_PER_DAY)
    }

    pub fn ut1_jd(&self) -> f64 {
        let (a, b) = self.ut1_jd_parts();
        a + b
    }

    /// TT − UT1（秒）
    pub fn delta_t(&self) -> f64 {
        self.delta_t
    }

    /// ΔT 是否来自外推（模型表尾之后）。用 [`Time::with_delta_t`] 指定时也按日期判断。
    pub fn delta_t_is_extrapolated(&self) -> bool {
        delta_t::is_extrapolated(self.tt_jd())
    }

    pub fn tdb(&self) -> Tdb {
        Tdb(self.tt + self.tdb_minus_tt())
    }

    /// TDB − TT（秒），地心值。
    pub fn tdb_minus_tt(&self) -> f64 {
        let (a, b) = self.tt_jd_parts();
        let ut_frac = self.ut1_jd().fract();
        ts::dtdb(a, b, ut_frac, 0.0, 0.0, 0.0)
    }

    /// 转换为 UTC（1960 年以前为 UT1），秒保留 3 位小数。
    pub fn to_utc(&self) -> Result<DateTime> {
        let err =
            |code: i32| Error::InvalidTime(format!("SOFA 状态 {code}：TT JD {}", self.tt_jd()));
        let (scale, d1, d2) = if self.ut1_jd() < UTC_START_JD {
            let (a, b) = self.ut1_jd_parts();
            ("UT1", a, b)
        } else {
            let (a, b) = self.tt_jd_parts();
            let (a1, a2) = ts::tttai(a, b).map_err(err)?;
            let (u1, u2) = ts::taiutc(a1, a2).map_err(err)?;
            ("UTC", u1, u2)
        };
        let (y, m, d, hmsf) = ts::d2dtf(scale, 3, d1, d2).map_err(err)?;
        DateTime::new(
            y,
            m as u32,
            d as u32,
            hmsf[0] as u32,
            hmsf[1] as u32,
            f64::from(hmsf[2]) + f64::from(hmsf[3]) / 1000.0,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn utc(s: &str) -> Time {
        Time::from_utc(&s.parse().unwrap()).unwrap()
    }

    #[test]
    fn tdb_jd_round_trip() {
        assert_eq!(Tdb::from_jd(J2000_JD), Tdb::J2000);
        let t = Tdb::from_jd(2_460_000.25);
        assert!((t.to_jd() - 2_460_000.25).abs() < 1e-9);
        assert_eq!(Tdb::J2000.add_days(1.0).0, SECONDS_PER_DAY);
    }

    #[test]
    fn parse_datetime() {
        let d: DateTime = "2026-11-05T12:34:56.5Z".parse().unwrap();
        assert_eq!(
            (d.year, d.month, d.day, d.hour, d.minute),
            (2026, 11, 5, 12, 34)
        );
        assert_eq!(d.second, 56.5);
        let d: DateTime = "2026-11-05".parse().unwrap();
        assert_eq!((d.hour, d.minute, d.second), (0, 0, 0.0));
        let d: DateTime = "2026-11-05 08:00".parse().unwrap();
        assert_eq!(d.hour, 8);
        assert!("2026-13-01".parse::<DateTime>().is_err());
        assert!("2026-02-30".parse::<DateTime>().is_err());
        assert!("2026-11-05T25:00".parse::<DateTime>().is_err());
        assert!("hello".parse::<DateTime>().is_err());
    }

    #[test]
    fn utc_to_tt_offsets() {
        // TT − UTC = 32.184 + (TAI − UTC)
        let cases = [
            ("1972-01-01T00:00:00", 32.184 + 10.0),
            ("1999-01-01T00:00:00", 32.184 + 32.0),
            // 闰秒日内 SOFA 的准儒略日拉长为 86401 s，这里取当天 0 时
            ("2016-12-31T00:00:00", 32.184 + 36.0),
            ("2017-01-01T00:00:00", 32.184 + 37.0),
            ("2026-11-05T00:00:00", 32.184 + 37.0),
        ];
        for (s, expect) in cases {
            let t = utc(s);
            let d: DateTime = s.parse().unwrap();
            let (u1, u2) = ts::dtf2d(
                "UTC",
                d.year,
                d.month as i32,
                d.day as i32,
                d.hour as i32,
                0,
                0.0,
            )
            .unwrap();
            let utc_s = ((u1 - J2000_JD) + u2) * SECONDS_PER_DAY;
            let off = t.tt_seconds() - utc_s;
            assert!((off - expect).abs() < 1e-6, "{s}: {off}");
        }
    }

    #[test]
    fn leap_second_is_representable() {
        let a = utc("2016-12-31T23:59:60");
        let b = utc("2017-01-01T00:00:00");
        assert!((b.tt_seconds() - a.tt_seconds() - 1.0).abs() < 1e-6);
        assert_eq!(a.to_utc().unwrap().second, 60.0);
    }

    #[test]
    fn j2000_epoch() {
        // J2000.0 = 2000-01-01T12:00:00 TT = 11:58:55.816 UTC
        let t = utc("2000-01-01T11:58:55.816");
        assert!(t.tt_seconds().abs() < 1e-6, "{}", t.tt_seconds());
    }

    #[test]
    fn utc_round_trip() {
        for s in [
            "1975-06-15T03:04:05.678",
            "2000-01-01T00:00:00",
            "2026-11-05T12:00:00.001",
            "2099-12-31T23:59:59.999",
        ] {
            let back = utc(s).to_utc().unwrap();
            assert_eq!(back.to_string(), s.parse::<DateTime>().unwrap().to_string());
        }
    }

    #[test]
    fn pre_1960_is_ut1() {
        let t = utc("1900-01-01T00:00:00");
        let (u1, u2) = t.ut1_jd_parts();
        assert!(((u1 + u2) - 2_415_020.5).abs() < 1e-9);
        assert!(
            (t.tt_seconds() / SECONDS_PER_DAY
                - (2_415_020.5 - J2000_JD)
                - t.delta_t() / SECONDS_PER_DAY)
                .abs()
                < 1e-9
        );
        assert_eq!(t.to_utc().unwrap().to_string(), "1900-01-01T00:00:00.000");
    }

    #[test]
    fn tdb_tt_difference_is_small() {
        for jd in [2_451_545.0, 2_455_000.3, 2_470_000.7] {
            let t = Time::from_tt_jd(jd);
            assert!(t.tdb_minus_tt().abs() < 0.0017, "{}", t.tdb_minus_tt());
            let back = Time::from_tdb(t.tdb());
            assert!((back.tt_seconds() - t.tt_seconds()).abs() < 1e-7);
        }
    }

    #[test]
    fn delta_t_override() {
        let t = Time::from_tt_jd(2_460_000.0).with_delta_t(70.0);
        assert_eq!(t.delta_t(), 70.0);
        let ((a1, a2), (b1, b2)) = (t.tt_jd_parts(), t.ut1_jd_parts());
        assert!((((a1 - b1) + (a2 - b2)) * SECONDS_PER_DAY - 70.0).abs() < 1e-6);
    }
}
