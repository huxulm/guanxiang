//! 动画场景：单次日月食的完整时间序列，格式就是 `guanxiang scene` 输出的 JSON（`tools/manim` 读取）。
//!
//! 星历、岁差章动、地影切平面与贝塞尔基本面都在这里一次算完，输出带明确物理单位
//! （度、秒、千米、AU）的序列，动画脚本只做插值和绘制。改字段时要同步 `tools/manim/scenes/`。

use guanxiang_core::astrometry::{self, AU_KM};
use guanxiang_core::events::local_eclipse::{self, LocalSolarKind};
use guanxiang_core::events::lunar_eclipse::{self, LunarEclipse, LunarEclipseKind, ShadowPoint};
use guanxiang_core::events::saros;
use guanxiang_core::events::solar_eclipse::{SolarEclipse, SolarEclipseKind};
use guanxiang_core::events::visibility::apparent_altitude;
use guanxiang_core::events::{Span, ecliptic_of_date_matrix};
use guanxiang_core::{Body, DateTime, Ephemeris, Error, Observer, Result, Time};
use serde_json::{Value, json};

use crate::{SHADOW_MODEL, find_lunar_eclipse, find_solar_eclipse, observer_json, utc_str};

fn check_step(step_s: f64) -> Result<()> {
    if !(1.0..=3600.0).contains(&step_s) {
        return Err(Error::InvalidTime("step_s 应在 1..=3600 秒之间".into()));
    }
    Ok(())
}

/// `date`（UTC）前后 3 天内最近一次月食的场景。
pub fn build_lunar_eclipse_json(
    eph: &dyn Ephemeris,
    date: &DateTime,
    at: Option<&Observer>,
    step_s: f64,
) -> Result<Value> {
    check_step(step_s)?;
    let e = find_lunar_eclipse(eph, date)?;
    lunar_eclipse_scene(eph, &e, at, step_s)
}

/// 月食场景：地影切平面轨迹（每 `step_s` 秒）、各接触时刻，给出观测地时加上月亮高度。
pub fn lunar_eclipse_scene(
    eph: &dyn Ephemeris,
    e: &LunarEclipse,
    at: Option<&Observer>,
    step_s: f64,
) -> Result<Value> {
    check_step(step_s)?;
    let diag = lunar_eclipse::diagram(eph, e, SHADOW_MODEL, step_s)?;
    let tg = e.greatest.tt_seconds();
    let (kind_en, kind_zh) = match e.kind {
        LunarEclipseKind::Penumbral => ("penumbral", "半影月食"),
        LunarEclipseKind::Partial => ("partial", "月偏食"),
        LunarEclipseKind::Total => ("total", "月全食"),
    };
    let saros_val = saros::lunar_saros(&e.greatest).map(|s| {
        json!({
            "series": s.series,
            "member": s.member,
            "count": s.count,
        })
    });

    let codes = ["P1", "U1", "U2", "G", "U3", "U4", "P4"];
    let labels_zh = [
        "半影食始",
        "初亏",
        "食既",
        "食甚",
        "生光",
        "复圆",
        "半影食终",
    ];
    let points: [Option<ShadowPoint>; 7] = [
        diag.contacts[0],
        diag.contacts[1],
        diag.contacts[2],
        Some(diag.greatest),
        diag.contacts[3],
        diag.contacts[4],
        diag.contacts[5],
    ];
    let alts = match at {
        Some(obs) => Some(local_eclipse::lunar_altitudes(eph, e, obs)?),
        None => None,
    };

    let mut contacts_json = Vec::new();
    for i in 0..7 {
        if let Some(p) = points[i] {
            let alt = alts.and_then(|a| a[i].is_finite().then_some(a[i]));
            contacts_json.push(json!({
                "code": codes[i],
                "label_zh": labels_zh[i],
                "utc": utc_str(&p.time),
                "t_rel_s": p.time.tt_seconds() - tg,
                "x_deg": p.x_deg,
                "y_deg": p.y_deg,
                "altitude_deg": alt,
            }));
        }
    }

    let mut path_json = Vec::with_capacity(diag.path.len());
    for p in &diag.path {
        let sep_deg = p.x_deg.hypot(p.y_deg);
        let umbral_mag_inst = (diag.umbra_deg + diag.moon_semidiameter_deg - sep_deg)
            / (2.0 * diag.moon_semidiameter_deg);
        let penumbral_mag_inst = (diag.penumbra_deg + diag.moon_semidiameter_deg - sep_deg)
            / (2.0 * diag.moon_semidiameter_deg);
        let alt = match at {
            Some(obs) => Some(apparent_altitude(eph, Body::Moon, &p.time, obs)?.to_degrees()),
            None => None,
        };
        path_json.push(json!({
            "t_rel_s": p.time.tt_seconds() - tg,
            "utc": utc_str(&p.time),
            "x_deg": p.x_deg,
            "y_deg": p.y_deg,
            "sep_deg": sep_deg,
            "umbral_mag": umbral_mag_inst,
            "penumbral_mag": penumbral_mag_inst,
            "altitude_deg": alt,
        }));
    }

    Ok(json!({
        "scene": "lunar_eclipse",
        "kind": kind_en,
        "kind_zh": kind_zh,
        "greatest_utc": utc_str(&e.greatest),
        "greatest_tt_jd": e.greatest.tt_jd(),
        "gamma": e.gamma,
        "penumbral_magnitude": e.penumbral_magnitude,
        "umbral_magnitude": e.umbral_magnitude,
        "saros": saros_val,
        "observer": at.map(observer_json),
        "radii_deg": {
            "penumbra": diag.penumbra_deg,
            "umbra": diag.umbra_deg,
            "moon": diag.moon_semidiameter_deg,
        },
        "contacts": contacts_json,
        "path": path_json,
    }))
}

/// `date`（UTC）前后 3 天内最近一次日食的场景。
pub fn build_solar_eclipse_json(
    eph: &dyn Ephemeris,
    date: &DateTime,
    at: Option<&Observer>,
    step_s: f64,
) -> Result<Value> {
    check_step(step_s)?;
    let e = find_solar_eclipse(eph, date)?;
    solar_eclipse_scene(eph, &e, at, step_s)
}

/// 日食场景：贝塞尔基本面轨迹、中心线（每 `step_s` 秒），给出观测地时加上日面遮掩序列。
pub fn solar_eclipse_scene(
    eph: &dyn Ephemeris,
    e: &SolarEclipse,
    at: Option<&Observer>,
    step_s: f64,
) -> Result<Value> {
    check_step(step_s)?;
    let tg = e.greatest.tt_seconds();
    let diag = e.diagram(eph, step_s)?;
    let central_line = e.central_line(eph, step_s)?;
    let (kind_en, kind_zh) = match e.kind {
        SolarEclipseKind::Partial => ("partial", "日偏食"),
        SolarEclipseKind::Annular => ("annular", "日环食"),
        SolarEclipseKind::Total => ("total", "日全食"),
        SolarEclipseKind::Hybrid => ("hybrid", "全环食"),
    };
    let saros_val = saros::solar_saros(&e.greatest).map(|s| {
        json!({
            "series": s.series,
            "member": s.member,
            "count": s.count,
        })
    });

    let local_val = match at {
        Some(obs) => {
            if let Some(loc) = local_eclipse::local_solar(eph, e, obs, None)? {
                let (lkind_en, lkind_zh) = match loc.kind {
                    LocalSolarKind::Partial => ("partial", "日偏食"),
                    LocalSolarKind::Annular => ("annular", "日环食"),
                    LocalSolarKind::Total => ("total", "日全食"),
                };
                let tm = loc.maximum.tt_seconds();
                let t0 = loc.contacts[0].map_or(tm - 3600.0, |t| t.tt_seconds()) - 300.0;
                let t1 = loc.contacts[3].map_or(tm + 3600.0, |t| t.tt_seconds()) + 300.0;
                let n = ((t1 - t0) / step_s).ceil().max(1.0) as usize;
                let mut raw_tts: Vec<f64> =
                    (0..=n).map(|i| (t0 + i as f64 * step_s).min(t1)).collect();
                // 在食甚前后 5 分钟内加密至 ≤ 2 秒步长，并注入精确接触时刻
                let fine_step = step_s.min(2.0);
                let fine_n = (600.0 / fine_step).ceil() as usize;
                for i in 0..=fine_n {
                    let tt = (tm - 300.0 + i as f64 * fine_step).clamp(t0, t1);
                    raw_tts.push(tt);
                }
                raw_tts.push(tm);
                for ct in loc.contacts.into_iter().flatten() {
                    raw_tts.push(ct.tt_seconds());
                }
                raw_tts.sort_by(|a, b| a.total_cmp(b));
                let mut sample_times: Vec<Time> = Vec::with_capacity(raw_tts.len());
                let mut prev_tt = f64::NEG_INFINITY;
                for tt in raw_tts {
                    if tt - prev_tt >= 0.05 {
                        sample_times.push(Time::from_tt_seconds(tt));
                        prev_tt = tt;
                    }
                }
                let views = local_eclipse::solar_disk_views(eph, obs, &sample_times)?;
                let frames: Vec<Value> = views
                    .iter()
                    .map(|v| {
                        json!({
                            "t_rel_s": v.time.tt_seconds() - tg,
                            "utc": utc_str(&v.time),
                            "x_deg": v.x.to_degrees(),
                            "y_deg": v.y.to_degrees(),
                            "sun_r_deg": v.sun_radius.to_degrees(),
                            "moon_r_deg": v.moon_radius.to_degrees(),
                            "obscuration": v.obscuration,
                            "sun_alt_deg": v.sun_altitude_deg,
                            "zenith_angle_deg": v.zenith_angle.to_degrees(),
                        })
                    })
                    .collect();

                let codes = ["C1", "C2", "MAX", "C3", "C4"];
                let labels_zh = ["初亏", "食既", "食甚", "生光", "复圆"];
                let moments = [
                    loc.contacts[0],
                    loc.contacts[1],
                    Some(loc.maximum),
                    loc.contacts[2],
                    loc.contacts[3],
                ];
                let mut c_json = Vec::new();
                for i in 0..5 {
                    if let Some(mt) = moments[i] {
                        let v = local_eclipse::solar_disk_views(eph, obs, &[mt])?;
                        let first = v.first();
                        c_json.push(json!({
                            "code": codes[i],
                            "label_zh": labels_zh[i],
                            "utc": utc_str(&mt),
                            "t_rel_s": mt.tt_seconds() - tg,
                            "x_deg": first.map(|f| f.x.to_degrees()),
                            "y_deg": first.map(|f| f.y.to_degrees()),
                            "sun_r_deg": first.map(|f| f.sun_radius.to_degrees()),
                            "moon_r_deg": first.map(|f| f.moon_radius.to_degrees()),
                            "obscuration": first.map(|f| f.obscuration),
                            "sun_alt_deg": first.map(|f| f.sun_altitude_deg),
                            "zenith_angle_deg": first.map(|f| f.zenith_angle.to_degrees()),
                        }));
                    }
                }

                Some(json!({
                    "kind": lkind_en,
                    "kind_zh": lkind_zh,
                    "maximum_utc": utc_str(&loc.maximum),
                    "magnitude": loc.magnitude,
                    "obscuration": loc.obscuration,
                    "central_duration_s": loc.central_duration_s(),
                    "contacts": c_json,
                    "disk_frames": frames,
                }))
            } else {
                None
            }
        }
        None => None,
    };

    let (sub_sun_lat, sub_sun_lon) = astrometry::sub_body_point(eph, Body::Sun, &e.greatest)?;

    Ok(json!({
        "scene": "solar_eclipse",
        "kind": kind_en,
        "kind_zh": kind_zh,
        "central": e.central,
        "greatest_utc": utc_str(&e.greatest),
        "greatest_tt_jd": e.greatest.tt_jd(),
        "gamma": e.gamma,
        "magnitude": e.magnitude,
        "saros": saros_val,
        "greatest_point": e.greatest_point.map(|gp| json!({
            "lat_deg": gp.latitude_deg,
            "lon_deg": gp.longitude_deg,
            "sun_alt_deg": gp.sun_altitude_deg,
            "width_km": gp.path_width_km,
        })),
        "observer": at.map(observer_json),
        "diagram": {
            "l1": diag.l1,
            "l2": diag.l2,
            "d_deg": diag.d.to_degrees(),
            "sub_solar_lat_deg": sub_sun_lat.to_degrees(),
            "sub_solar_lon_deg": sub_sun_lon.to_degrees(),
            "greatest": {
                "x": diag.greatest.x,
                "y": diag.greatest.y,
            },
            "track": diag.track.iter().map(|p| json!({
                "t_rel_s": p.time.tt_seconds() - tg,
                "utc": utc_str(&p.time),
                "x": p.x,
                "y": p.y,
            })).collect::<Vec<_>>(),
        },
        "central_line": central_line.iter().map(|p| json!({
            "t_rel_s": p.time.tt_seconds() - tg,
            "utc": utc_str(&p.time),
            "lat_deg": p.latitude_deg,
            "lon_deg": p.longitude_deg,
            "sun_alt_deg": p.sun_altitude_deg,
            "width_km": p.path_width_km,
        })).collect::<Vec<_>>(),
        "local": local_val,
    }))
}

fn mat_mul(m: &[[f64; 3]; 3], v: guanxiang_core::Vec3) -> guanxiang_core::Vec3 {
    guanxiang_core::Vec3::new(
        m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
        m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
        m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z,
    )
}

/// 多个天体在一段时间内的日心黄道坐标与地心视赤经、赤纬、黄经、黄纬（合冲、顺逆行动画用）。
pub fn build_ephem_track_json(
    eph: &dyn Ephemeris,
    bodies: &[Body],
    from: &DateTime,
    to: &DateTime,
    step_hours: f64,
) -> Result<Value> {
    if !(0.1..=720.0).contains(&step_hours) {
        return Err(Error::InvalidTime(
            "step_hours 应在 0.1..=720 小时之间".into(),
        ));
    }
    let span = Span::new(Time::from_utc(from)?, Time::from_utc(to)?)?;
    let step_s = step_hours * 3600.0;
    let (t0, t1) = (span.start.tt_seconds(), span.end.tt_seconds());
    let n = ((t1 - t0) / step_s).ceil().max(1.0) as usize;
    let j2000_ecl = ecliptic_of_date_matrix(&Time::from_tt_seconds(0.0));

    let mut frames = Vec::with_capacity(n + 1);
    for i in 0..=n {
        let tt = (t0 + i as f64 * step_s).min(t1);
        let t = Time::from_tt_seconds(tt);
        let tdb = t.tdb();
        let ecl_mat = ecliptic_of_date_matrix(&t);
        let mut body_map = serde_json::Map::new();
        for &b in bodies {
            let helio_icrf = eph.position(b, Body::Sun, tdb)?;
            let helio_ecl = mat_mul(&j2000_ecl, helio_icrf);
            let mut entry = json!({
                "helio_ecl_au": [
                    helio_ecl.x / AU_KM,
                    helio_ecl.y / AU_KM,
                    helio_ecl.z / AU_KM,
                ],
            });
            if b != Body::Earth {
                let place = astrometry::geocentric(eph, b, &t)?;
                let dir = astrometry::geocentric_direction(eph, b, &t)?;
                let ecl_v = mat_mul(&ecl_mat, dir.apparent);
                let lon_deg = ecl_v.y.atan2(ecl_v.x).to_degrees().rem_euclid(360.0);
                let lat_deg = ecl_v.z.clamp(-1.0, 1.0).asin().to_degrees();
                entry["ra_deg"] = json!(place.apparent.ra.to_degrees());
                entry["dec_deg"] = json!(place.apparent.dec.to_degrees());
                entry["ecl_lon_deg"] = json!(lon_deg);
                entry["ecl_lat_deg"] = json!(lat_deg);
                entry["distance_au"] = json!(place.distance_km / AU_KM);
            }
            body_map.insert(b.name().to_string(), entry);
        }
        frames.push(json!({
            "t_days": (tt - t0) / 86_400.0,
            "utc": utc_str(&t),
            "tt_jd": t.tt_jd(),
            "bodies": body_map,
        }));
    }

    Ok(json!({
        "scene": "ephem_track",
        "from_utc": utc_str(&span.start),
        "to_utc": utc_str(&span.end),
        "step_hours": step_hours,
        "bodies": bodies.iter().map(|b| json!({
            "name": b.name(),
            "name_zh": b.name_zh(),
        })).collect::<Vec<_>>(),
        "frames": frames,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_ephemeris as ephemeris;

    #[test]
    fn lunar_eclipse_scene_json_schema() {
        let Some(eph) = ephemeris() else { return };
        let date: DateTime = "2025-09-07".parse().unwrap();
        let obs = Observer::from_degrees(39.9, 116.4, 50.0).unwrap();
        let val = build_lunar_eclipse_json(&eph, &date, Some(&obs), 120.0).unwrap();

        assert_eq!(val["scene"], "lunar_eclipse");
        assert_eq!(val["kind"], "total");
        assert_eq!(val["saros"]["series"], 128);
        assert_eq!(val["contacts"].as_array().unwrap().len(), 7);
        assert!(val["path"].as_array().unwrap().len() > 100);
        assert!(val["radii_deg"]["umbra"].as_f64().unwrap() > 0.6);
    }

    #[test]
    fn solar_eclipse_scene_json_schema() {
        let Some(eph) = ephemeris() else { return };
        let date: DateTime = "2027-08-02".parse().unwrap();
        let obs = Observer::from_degrees(25.687, 32.640, 80.0).unwrap();
        let val = build_solar_eclipse_json(&eph, &date, Some(&obs), 120.0).unwrap();

        assert_eq!(val["scene"], "solar_eclipse");
        assert_eq!(val["kind"], "total");
        assert_eq!(val["local"]["kind"], "total");
        assert!(val["local"]["central_duration_s"].as_f64().unwrap() > 370.0);
        assert_eq!(val["local"]["contacts"].as_array().unwrap().len(), 5);
    }

    #[test]
    fn ephem_track_scene_json_schema() {
        let Some(eph) = ephemeris() else { return };
        let from: DateTime = "2026-11-01".parse().unwrap();
        let to: DateTime = "2026-11-11".parse().unwrap();
        let val =
            build_ephem_track_json(&eph, &[Body::Mars, Body::Earth], &from, &to, 24.0).unwrap();

        assert_eq!(val["scene"], "ephem_track");
        assert_eq!(val["frames"].as_array().unwrap().len(), 11);
        assert!(val["frames"][0]["bodies"]["mars"]["ra_deg"].is_f64());
    }
}
