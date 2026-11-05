//! 人造卫星（D4：sgp4 crate，OMM 为主，编号 u32）。
//!
//! 坐标约定：SGP4 输出 TEME（真赤道、平春分点）。转到地固系用 GMST82（UT1）绕 z 轴旋转，
//! 忽略极移（Vallado 的 TEME → PEF）。网络请求不在这里做（D5）：调用方传入 OMM JSON 字符串。

use crate::error::{Error, Result};
use crate::geometry::Vec3;
use crate::time::{DateTime, Time};

/// 一颗卫星（一组根数）。
#[derive(Clone)]
pub struct Satellite {
    pub name: String,
    pub norad_id: u32,
    /// 根数历元
    pub epoch: Time,
    constants: sgp4::Constants,
}

impl std::fmt::Debug for Satellite {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Satellite")
            .field("name", &self.name)
            .field("norad_id", &self.norad_id)
            .field("epoch_tt_jd", &self.epoch.tt_jd())
            .finish()
    }
}

impl Satellite {
    /// 解析 CelesTrak `FORMAT=JSON` 的 OMM（数组）。
    pub fn from_omm_json(json: &str) -> Result<Vec<Satellite>> {
        let elements: Vec<sgp4::Elements> = serde_json::from_str(json)
            .map_err(|e| Error::Satellite(format!("OMM JSON 解析失败：{e}")))?;
        elements.iter().map(Satellite::from_elements).collect()
    }

    /// 解析两行根数（旧格式，五位编号以内）。
    pub fn from_tle(name: &str, line1: &str, line2: &str) -> Result<Satellite> {
        let e =
            sgp4::Elements::from_tle(Some(name.to_string()), line1.as_bytes(), line2.as_bytes())
                .map_err(|e| Error::Satellite(format!("TLE 解析失败：{e}")))?;
        Satellite::from_elements(&e)
    }

    fn from_elements(e: &sgp4::Elements) -> Result<Satellite> {
        use chrono::{Datelike, Timelike};
        let d = e.datetime;
        let second = f64::from(d.second()) + f64::from(d.nanosecond()) * 1e-9;
        let epoch = Time::from_utc(&DateTime::new(
            d.year(),
            d.month(),
            d.day(),
            d.hour(),
            d.minute(),
            second,
        )?)?;
        // NORAD 根数是用 WGS72 拟合的；sgp4 crate 的 from_elements 默认 WGS84，
        // 与 Vallado 参考实现、python-sgp4（Skyfield）的默认不同，一周后位置会差到百米级。
        // 这里与 python-sgp4 的默认（WGS72 + 改进模式）一致。
        let deg = std::f64::consts::PI / 180.0;
        let orbit = sgp4::Orbit::from_kozai_elements(
            &sgp4::WGS72,
            e.inclination * deg,
            e.right_ascension * deg,
            e.eccentricity,
            e.argument_of_perigee * deg,
            e.mean_anomaly * deg,
            e.mean_motion * (std::f64::consts::PI / 720.0),
        )
        .map_err(|err| Error::Satellite(format!("根数无效：{err:?}")))?;
        let constants = sgp4::Constants::new(
            sgp4::WGS72,
            sgp4::iau_epoch_to_sidereal_time,
            e.epoch(),
            e.drag_term,
            orbit,
        )
        .map_err(|err| Error::Satellite(format!("根数无效：{err:?}")))?;
        let norad_id = u32::try_from(e.norad_id)
            .map_err(|_| Error::Satellite(format!("编号超出 u32：{}", e.norad_id)))?;
        Ok(Satellite {
            name: e
                .object_name
                .clone()
                .unwrap_or_else(|| format!("NORAD {norad_id}")),
            norad_id,
            epoch,
            constants,
        })
    }

    /// 根数龄期（天）：`t` 距根数历元的时间，负值表示 `t` 早于历元。
    pub fn age_days(&self, t: &Time) -> f64 {
        (t.tt_seconds() - self.epoch.tt_seconds()) / 86_400.0
    }

    /// TEME 位置（km）和速度（km/s）。
    pub fn teme(&self, t: &Time) -> Result<(Vec3, Vec3)> {
        let minutes = (t.tt_seconds() - self.epoch.tt_seconds()) / 60.0;
        let p = self
            .constants
            .propagate(sgp4::MinutesSinceEpoch(minutes))
            .map_err(|e| Error::Satellite(format!("SGP4 预报失败：{e}")))?;
        Ok((Vec3::from(p.position), Vec3::from(p.velocity)))
    }

    /// 地固系位置（km），忽略极移。
    pub fn earth_fixed(&self, t: &Time) -> Result<Vec3> {
        Ok(teme_to_fixed(self.teme(t)?.0, t))
    }
}

/// TEME → 地固系（伪地固系 PEF，忽略极移）：绕 z 轴转 GMST82(UT1)。
pub fn teme_to_fixed(r: Vec3, t: &Time) -> Vec3 {
    let (a, b) = t.ut1_jd_parts();
    let g = sofars::erst::gmst82(a, b);
    let (s, c) = g.sin_cos();
    Vec3::new(c * r.x + s * r.y, -s * r.x + c * r.y, r.z)
}

#[cfg(test)]
mod tests {
    use super::*;

    // CelesTrak 2026-11-04 的空间站 OMM
    const ISS: &str = r#"[{"OBJECT_NAME":"ISS (ZARYA)","OBJECT_ID":"1998-067A","EPOCH":"2026-11-04T21:15:15.204960","MEAN_MOTION":15.49180468,"ECCENTRICITY":0.00072122,"INCLINATION":51.6327,"RA_OF_ASC_NODE":323.8448,"ARG_OF_PERICENTER":348.649,"MEAN_ANOMALY":11.4335,"EPHEMERIS_TYPE":0,"CLASSIFICATION_TYPE":"U","NORAD_CAT_ID":25544,"ELEMENT_SET_NO":999,"REV_AT_EPOCH":59356,"BSTAR":0.00010456704,"MEAN_MOTION_DOT":5.352e-5,"MEAN_MOTION_DDOT":0}]"#;

    #[test]
    fn parse_and_propagate() {
        let sats = Satellite::from_omm_json(ISS).unwrap();
        let iss = &sats[0];
        assert_eq!(iss.norad_id, 25544);
        assert_eq!(iss.name, "ISS (ZARYA)");
        let (r, v) = iss.teme(&iss.epoch).unwrap();
        let alt = r.norm() - 6378.137;
        assert!((380.0..450.0).contains(&alt), "高度 {alt}");
        assert!((7.5..7.8).contains(&v.norm()), "速度 {}", v.norm());
        assert!(iss.age_days(&iss.epoch.add_seconds(86_400.0)) - 1.0 < 1e-9);
    }

    #[test]
    fn bad_input() {
        assert!(Satellite::from_omm_json("not json").is_err());
        assert!(Satellite::from_omm_json("[]").unwrap().is_empty());
    }
}
