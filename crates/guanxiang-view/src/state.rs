//! 逐帧状态：任意时刻的日月食几何量，动画每一帧直接求值，不在前端插值。
//!
//! 时间用相对食甚的 TT 秒数 `t_rel_s`，与 [`crate::scene`] 里各序列的 `t_rel_s` 一致，
//! 前端的时间轴可以直接拿来用。

use guanxiang_core::astrometry;
use guanxiang_core::events::local_eclipse::{self, SolarDiskView};
use guanxiang_core::events::lunar_eclipse::{self, LunarEclipse};
use guanxiang_core::events::solar_eclipse::{SolarEclipse, normalize_longitude_deg};
use guanxiang_core::events::visibility::apparent_altitude;
use guanxiang_core::{Body, Ephemeris, Observer, Result, Time};
use serde_json::{Value, json};

use crate::{SHADOW_MODEL, utc_iso};

/// 观测地看到的日月圆面，字段与场景 `local.disk_frames` 相同（不含时间）。
pub fn disk_json(v: &SolarDiskView) -> Value {
    json!({
        "x_deg": v.x.to_degrees(),
        "y_deg": v.y.to_degrees(),
        "sun_r_deg": v.sun_radius.to_degrees(),
        "moon_r_deg": v.moon_radius.to_degrees(),
        "obscuration": v.obscuration,
        "sun_alt_deg": v.sun_altitude_deg,
        "zenith_angle_deg": v.zenith_angle.to_degrees(),
    })
}

/// 月食在食甚后 `t_rel_s` 秒（TT）的状态。
///
/// - `x_deg`、`y_deg`、`sep_deg`：月心在地影切平面上的位置（x 向东、y 向北）和离影轴的角距；
/// - `radii_deg`：该时刻的半影、本影半径和月球视半径（场景里用的是食甚时的值，这里随时间变化）；
/// - `umbral_mag`、`penumbral_mag`：该时刻的本影、半影食分（负数表示还没进入）；
/// - `altitude_deg`：给出观测地时的月亮视高度（含折射），否则为 null。
pub fn lunar_state_json(
    eph: &dyn Ephemeris,
    e: &LunarEclipse,
    t_rel_s: f64,
    at: Option<&Observer>,
) -> Result<Value> {
    let t = Time::from_tt_seconds(e.greatest.tt_seconds() + t_rel_s);
    let s = lunar_eclipse::shadow_state(eph, &t, SHADOW_MODEL)?;
    let sep = s.point.x_deg.hypot(s.point.y_deg);
    let d = 2.0 * s.moon_semidiameter_deg;
    let alt = match at {
        Some(obs) => Some(apparent_altitude(eph, Body::Moon, &t, obs)?.to_degrees()),
        None => None,
    };
    Ok(json!({
        "t_rel_s": t_rel_s,
        "utc": utc_iso(&t)?,
        "x_deg": s.point.x_deg,
        "y_deg": s.point.y_deg,
        "sep_deg": sep,
        "radii_deg": {
            "penumbra": s.penumbra_deg,
            "umbra": s.umbra_deg,
            "moon": s.moon_semidiameter_deg,
        },
        "umbral_mag": (s.umbra_deg + s.moon_semidiameter_deg - sep) / d,
        "penumbral_mag": (s.penumbra_deg + s.moon_semidiameter_deg - sep) / d,
        "altitude_deg": alt,
    }))
}

/// 日食在食甚后 `t_rel_s` 秒（TT）的状态。
///
/// - `bessel`：贝塞尔根数 x、y、z（地球赤道半径）、d、μ（度）、l1、l2、tan f1、tan f2，
///   可以把半影、本影边界从基本面换算到地面；
/// - `sub_solar`：日下点；
/// - `shadow_center`：影轴在地面的点（中心线上的点，含太阳高度和食带宽度），影轴不与地球相交时为 null；
/// - `local`：给出观测地时看到的日月圆面（字段同场景 `disk_frames`），否则为 null。
pub fn solar_state_json(
    eph: &dyn Ephemeris,
    e: &SolarEclipse,
    t_rel_s: f64,
    at: Option<&Observer>,
) -> Result<Value> {
    let t = Time::from_tt_seconds(e.greatest.tt_seconds() + t_rel_s);
    let b = e.elements_at(eph, &t)?;
    let center = e.central_point_at(eph, &t)?;
    let (sub_lat, sub_lon) = astrometry::sub_body_point(eph, Body::Sun, &t)?;
    let local = match at {
        Some(obs) => local_eclipse::solar_disk_views(eph, obs, &[t])?
            .first()
            .map(disk_json),
        None => None,
    };
    Ok(json!({
        "t_rel_s": t_rel_s,
        "utc": utc_iso(&t)?,
        "bessel": {
            "x": b.x,
            "y": b.y,
            "z": b.z,
            "d_deg": b.d.to_degrees(),
            "mu_deg": b.hour_angle(&t).to_degrees(),
            "l1": b.l1,
            "l2": b.l2,
            "tan_f1": b.tan_f1,
            "tan_f2": b.tan_f2,
        },
        "sub_solar": {
            "lat_deg": sub_lat.to_degrees(),
            "lon_deg": normalize_longitude_deg(sub_lon.to_degrees()),
        },
        "shadow_center": center.map(|p| json!({
            "lat_deg": p.latitude_deg,
            "lon_deg": p.longitude_deg,
            "sun_alt_deg": p.sun_altitude_deg,
            "width_km": p.path_width_km,
        })),
        "local": local,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_ephemeris as ephemeris;
    use crate::{find_lunar_eclipse, find_solar_eclipse};
    use guanxiang_core::DateTime;

    fn f(v: &Value) -> f64 {
        v.as_f64().unwrap()
    }

    #[test]
    fn lunar_state_matches_diagram_and_contacts() {
        let Some(eph) = ephemeris() else { return };
        let date: DateTime = "2025-09-07".parse().unwrap();
        let e = find_lunar_eclipse(&eph, &date).unwrap();
        let diag = lunar_eclipse::diagram(&eph, &e, SHADOW_MODEL, 600.0).unwrap();

        // 食甚：与示意图的点完全相同（同一个函数），食分与搜索结果一致
        let g = lunar_state_json(&eph, &e, 0.0, None).unwrap();
        assert_eq!(f(&g["x_deg"]), diag.greatest.x_deg);
        assert_eq!(f(&g["y_deg"]), diag.greatest.y_deg);
        assert!(
            (f(&g["umbral_mag"]) - e.umbral_magnitude).abs() < 0.002,
            "{g}"
        );
        assert!(g["altitude_deg"].is_null());

        // 初亏 U1、食既 U2：月心到影轴的距离 = 本影半径 ± 月球半径
        let tg = e.greatest.tt_seconds();
        for (i, sign) in [(1, 1.0), (2, -1.0)] {
            let t_rel = e.contacts[i].unwrap().tt_seconds() - tg;
            let s = lunar_state_json(&eph, &e, t_rel, None).unwrap();
            let r = &s["radii_deg"];
            let expect = f(&r["umbra"]) + sign * f(&r["moon"]);
            assert!((f(&s["sep_deg"]) - expect).abs() < 0.002, "{s}");
        }

        // 北京：食甚时月亮在地平线上
        let obs = Observer::from_degrees(39.9, 116.4, 50.0).unwrap();
        let s = lunar_state_json(&eph, &e, 0.0, Some(&obs)).unwrap();
        assert!(f(&s["altitude_deg"]) > 10.0, "{s}");
    }

    /// 由贝塞尔根数 x、y、d、μ 换算影轴地面点（Explanatory Supplement 的标准公式，WGS84 椭球）。
    fn axis_ground_point(b: &Value) -> (f64, f64) {
        let e2 = {
            let fl = 1.0 / 298.257_223_563;
            fl * (2.0 - fl)
        };
        let (x, y) = (f(&b["x"]), f(&b["y"]));
        let (d, mu) = (f(&b["d_deg"]).to_radians(), f(&b["mu_deg"]).to_radians());
        let rho1 = (1.0 - e2 * d.cos().powi(2)).sqrt();
        let (sd1, cd1) = (d.sin() / rho1, (1.0 - e2).sqrt() * d.cos() / rho1);
        let eta1 = y / rho1;
        let zeta1 = (1.0 - x * x - eta1 * eta1).sqrt();
        let sin_phi1 = eta1 * cd1 + zeta1 * sd1;
        let theta = x.atan2(-eta1 * sd1 + zeta1 * cd1);
        let phi1 = sin_phi1.asin();
        let lat = (phi1.tan() / (1.0 - e2).sqrt()).atan();
        let lon = normalize_longitude_deg((theta - mu).to_degrees());
        (lat.to_degrees(), lon)
    }

    #[test]
    fn solar_state_matches_diagram_central_line_and_local() {
        let Some(eph) = ephemeris() else { return };
        let date: DateTime = "2027-08-02".parse().unwrap();
        let e = find_solar_eclipse(&eph, &date).unwrap();
        let diag = e.diagram(&eph, 600.0).unwrap();
        let line = e.central_line(&eph, 600.0).unwrap();
        let tg = e.greatest.tt_seconds();

        let g = solar_state_json(&eph, &e, 0.0, None).unwrap();
        assert_eq!(f(&g["bessel"]["x"]), diag.greatest.x);
        assert_eq!(f(&g["bessel"]["y"]), diag.greatest.y);
        assert!(g["local"].is_null());

        // 中心线上每个点：逐帧求值与中心线完全相同，并且用 x、y、d、μ 换算的地面点与之一致（验证 μ）
        for p in &line {
            let s = solar_state_json(&eph, &e, p.time.tt_seconds() - tg, None).unwrap();
            let c = &s["shadow_center"];
            assert_eq!(f(&c["lat_deg"]), p.latitude_deg);
            assert_eq!(f(&c["lon_deg"]), p.longitude_deg);
            let (lat, lon) = axis_ground_point(&s["bessel"]);
            assert!(
                (lat - p.latitude_deg).abs() < 1e-6,
                "{lat} vs {}",
                p.latitude_deg
            );
            let dlon = normalize_longitude_deg(lon - p.longitude_deg).abs();
            assert!(dlon < 1e-6, "{lon} vs {}", p.longitude_deg);
        }

        // 半影离开地球后影轴不与地球相交
        let last = diag.track.last().unwrap().time.tt_seconds() - tg;
        let s = solar_state_json(&eph, &e, last, None).unwrap();
        assert!(s["shadow_center"].is_null());

        // 卢克索：本地食甚时的食面积与 local_solar 一致（日全食为 1）
        let obs = Observer::from_degrees(25.687, 32.640, 80.0).unwrap();
        let loc = local_eclipse::local_solar(&eph, &e, &obs, None)
            .unwrap()
            .unwrap();
        let s = solar_state_json(&eph, &e, loc.maximum.tt_seconds() - tg, Some(&obs)).unwrap();
        assert!(
            (f(&s["local"]["obscuration"]) - loc.obscuration).abs() < 1e-6,
            "{s}"
        );
        assert!(f(&s["local"]["sun_alt_deg"]) > 30.0);
    }
}
