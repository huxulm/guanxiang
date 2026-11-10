//! 日月食列表：按年份搜索，给列表页用。
//!
//! 调用方按年分块调用（每块之间回传进度、检查取消，思路同 D15），这里只算一段。

use guanxiang_core::events::Span;
use guanxiang_core::events::lunar_eclipse::{self, LunarEclipseKind};
use guanxiang_core::events::saros::{self, Saros};
use guanxiang_core::events::solar_eclipse::{self, SolarEclipseKind};
use guanxiang_core::{DateTime, Ephemeris, Result, Time};
use serde_json::{Value, json};

use crate::{SHADOW_MODEL, time_json};

/// 某年 1 月 1 日 0 时（UTC）。
fn year_start(year: i32) -> Result<Time> {
    Time::from_utc(&DateTime::new(year, 1, 1, 0, 0, 0.0)?)
}

fn years(from_year: i32, to_year: i32) -> Result<Span> {
    Span::new(year_start(from_year)?, year_start(to_year)?)
}

fn saros_json(s: Option<Saros>) -> Value {
    s.map_or(
        Value::Null,
        |s| json!({ "series": s.series, "member": s.member, "count": s.count }),
    )
}

/// `[from_year, to_year)` 年内的月食（UTC 年初为界）。
///
/// 每条：`kind`（penumbral / partial / total）、`greatest`（`{utc, tt}`）、`gamma`、
/// `penumbral_magnitude`、`umbral_magnitude`、`contacts`（P1、U1、U2、U3、U4、P4，没有的为 null）、`saros`。
pub fn lunar_eclipses_json(eph: &dyn Ephemeris, from_year: i32, to_year: i32) -> Result<Value> {
    let mut out = Vec::new();
    for e in lunar_eclipse::search(eph, years(from_year, to_year)?, SHADOW_MODEL)? {
        let kind = match e.kind {
            LunarEclipseKind::Penumbral => "penumbral",
            LunarEclipseKind::Partial => "partial",
            LunarEclipseKind::Total => "total",
        };
        let contacts = e
            .contacts
            .iter()
            .map(|c| c.as_ref().map(time_json).transpose())
            .collect::<Result<Vec<_>>>()?;
        out.push(json!({
            "kind": kind,
            "greatest": time_json(&e.greatest)?,
            "gamma": e.gamma,
            "penumbral_magnitude": e.penumbral_magnitude,
            "umbral_magnitude": e.umbral_magnitude,
            "contacts": contacts,
            "saros": saros_json(saros::lunar_saros(&e.greatest)),
        }));
    }
    Ok(Value::Array(out))
}

/// `[from_year, to_year)` 年内的日食（UTC 年初为界）。
///
/// 每条：`kind`（partial / annular / total / hybrid）、`central`、`greatest`、`gamma`、`magnitude`、
/// `greatest_point`（中心食食甚点：`lat_deg`、`lon_deg`、`sun_alt_deg`、`width_km`；偏食为最接近影轴的地面点附近，可能为 null）、`saros`。
pub fn solar_eclipses_json(eph: &dyn Ephemeris, from_year: i32, to_year: i32) -> Result<Value> {
    let mut out = Vec::new();
    for e in solar_eclipse::search(eph, years(from_year, to_year)?)? {
        let kind = match e.kind {
            SolarEclipseKind::Partial => "partial",
            SolarEclipseKind::Annular => "annular",
            SolarEclipseKind::Total => "total",
            SolarEclipseKind::Hybrid => "hybrid",
        };
        out.push(json!({
            "kind": kind,
            "central": e.central,
            "greatest": time_json(&e.greatest)?,
            "gamma": e.gamma,
            "magnitude": e.magnitude,
            "greatest_point": e.greatest_point.map(|p| json!({
                "lat_deg": p.latitude_deg,
                "lon_deg": p.longitude_deg,
                "sun_alt_deg": p.sun_altitude_deg,
                "width_km": p.path_width_km,
            })),
            "saros": saros_json(saros::solar_saros(&e.greatest)),
        }));
    }
    Ok(Value::Array(out))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_ephemeris as ephemeris;

    #[test]
    fn lunar_eclipses_2025() {
        let Some(eph) = ephemeris() else { return };
        let val = lunar_eclipses_json(&eph, 2025, 2026).unwrap();
        let list = val.as_array().unwrap();
        // 2025 年有两次月全食：3 月 14 日、9 月 7 日（沙罗 123、128）
        assert_eq!(list.len(), 2);
        for (e, (date, series)) in list.iter().zip([("2025-03-14", 123), ("2025-09-07", 128)]) {
            assert_eq!(e["kind"], "total");
            assert!(e["greatest"]["utc"].as_str().unwrap().starts_with(date));
            assert_eq!(e["saros"]["series"], series);
            let contacts = e["contacts"].as_array().unwrap();
            assert_eq!(contacts.len(), 6);
            assert!(contacts.iter().all(|c| c.is_object()));
        }
    }

    #[test]
    fn solar_eclipses_2027() {
        let Some(eph) = ephemeris() else { return };
        let val = solar_eclipses_json(&eph, 2027, 2028).unwrap();
        let list = val.as_array().unwrap();
        // 2027 年：2 月 6 日日环食、8 月 2 日日全食（沙罗 136）
        assert_eq!(list.len(), 2);
        assert_eq!(list[0]["kind"], "annular");
        assert_eq!(list[1]["kind"], "total");
        assert!(
            list[1]["greatest"]["utc"]
                .as_str()
                .unwrap()
                .starts_with("2027-08-02")
        );
        assert_eq!(list[1]["saros"]["series"], 136);
        assert!(list[1]["greatest_point"]["width_km"].as_f64().unwrap() > 200.0);
    }
}
