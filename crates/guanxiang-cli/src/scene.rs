//! `guanxiang scene`：导出供 Manim 等演示动画工具使用的结构化场景 JSON。
//!
//! 将耗时的星历、岁差章动、地影切平面与贝塞尔基本面计算在 Rust 中一次性完成，
//! 输出带明确物理单位（度、秒、千米、AU）的时间序列 JSON，供动画脚本直接插值渲染。

use std::fs;
use std::path::PathBuf;

use clap::{Args, Subcommand};
use guanxiang_core::astrometry::{self, AU_KM};
use guanxiang_core::events::local_eclipse::{self, LocalSolarKind};
use guanxiang_core::events::lunar_eclipse::{
    self, LunarEclipse, LunarEclipseKind, ShadowModel, ShadowPoint,
};
use guanxiang_core::events::saros;
use guanxiang_core::events::solar_eclipse::{self, SolarEclipseKind};
use guanxiang_core::events::visibility::apparent_altitude;
use guanxiang_core::events::{Span, ecliptic_of_date_matrix};
use guanxiang_core::{AniseEphemeris, Body, DateTime, Ephemeris, Error, Observer, Result, Time};
use serde_json::{Value, json};

#[derive(Args)]
pub struct SceneArgs {
    #[command(subcommand)]
    pub command: SceneCommand,
}

#[derive(Subcommand)]
pub enum SceneCommand {
    /// 导出单次月食的地影切平面轨迹、各接触时刻与可选测站地平高度
    LunarEclipse {
        /// 食甚附近的日期（UTC），如 2025-09-07
        #[arg(long)]
        date: DateTime,
        /// 可选测站：纬度,经度[,高度米]（度，东经、北纬为正）
        #[arg(long, value_name = "LAT,LON[,H]", allow_hyphen_values = true)]
        at: Option<Observer>,
        /// 轨迹采样步长（秒）
        #[arg(long, default_value_t = 60.0)]
        step_s: f64,
        /// 输出 JSON 文件路径；省略时输出到标准输出
        #[arg(long)]
        out: Option<PathBuf>,
    },
    /// 导出单次日食的贝塞尔基本面轨迹、地面中心线与可选测站的日面遮掩序列
    SolarEclipse {
        /// 食甚附近的日期（UTC），如 2027-08-02
        #[arg(long)]
        date: DateTime,
        /// 可选测站：纬度,经度[,高度米]（度，东经、北纬为正）
        #[arg(long, value_name = "LAT,LON[,H]", allow_hyphen_values = true)]
        at: Option<Observer>,
        /// 轨迹与日面采样步长（秒）
        #[arg(long, default_value_t = 60.0)]
        step_s: f64,
        /// 输出 JSON 文件路径；省略时输出到标准输出
        #[arg(long)]
        out: Option<PathBuf>,
    },
    /// 导出多个天体在一段时间内的日心轨道坐标与地心视赤经/赤纬/黄经/黄纬序列（适合合冲、顺行-留-逆行动画）
    EphemTrack {
        /// 天体列表（逗号分隔），如 mars,earth,sun
        #[arg(long, value_delimiter = ',', required = true)]
        bodies: Vec<Body>,
        /// 起始日期（UTC），如 2026-11-01
        #[arg(long)]
        from: DateTime,
        /// 结束日期（UTC），如 2027-05-01
        #[arg(long)]
        to: DateTime,
        /// 采样步长（小时）
        #[arg(long, default_value_t = 24.0)]
        step_hours: f64,
        /// 输出 JSON 文件路径；省略时输出到标准输出
        #[arg(long)]
        out: Option<PathBuf>,
    },
}

fn utc_str(t: &Time) -> String {
    t.to_utc()
        .map(|d| d.to_string()[..19].replace('T', " "))
        .unwrap_or_else(|_| format!("TT JD {:.5}", t.tt_jd()))
}

fn write_output(val: &Value, out: Option<&PathBuf>) -> Result<()> {
    let text = serde_json::to_string_pretty(val).map_err(|e| Error::Catalog(e.to_string()))?;
    if let Some(path) = out {
        if let Some(parent) = path.parent()
            && !parent.as_os_str().is_empty()
        {
            fs::create_dir_all(parent).map_err(|e| Error::Catalog(e.to_string()))?;
        }
        fs::write(path, text).map_err(|e| Error::Catalog(e.to_string()))?;
    } else {
        println!("{text}");
    }
    Ok(())
}

pub fn run(eph: &AniseEphemeris, args: &SceneArgs) -> Result<()> {
    match &args.command {
        SceneCommand::LunarEclipse {
            date,
            at,
            step_s,
            out,
        } => {
            let val = build_lunar_eclipse_json(eph, date, at.as_ref(), *step_s)?;
            write_output(&val, out.as_ref())
        }
        SceneCommand::SolarEclipse {
            date,
            at,
            step_s,
            out,
        } => {
            let val = build_solar_eclipse_json(eph, date, at.as_ref(), *step_s)?;
            write_output(&val, out.as_ref())
        }
        SceneCommand::EphemTrack {
            bodies,
            from,
            to,
            step_hours,
            out,
        } => {
            let val = build_ephem_track_json(eph, bodies, from, to, *step_hours)?;
            write_output(&val, out.as_ref())
        }
    }
}

pub fn build_lunar_eclipse_json(
    eph: &dyn Ephemeris,
    date: &DateTime,
    at: Option<&Observer>,
    step_s: f64,
) -> Result<Value> {
    if !(1.0..=3600.0).contains(&step_s) {
        return Err(Error::InvalidTime("step_s 应在 1..=3600 秒之间".into()));
    }
    let center = Time::from_utc(date)?;
    let span = Span::new(
        center.add_seconds(-3.0 * 86_400.0),
        center.add_seconds(3.0 * 86_400.0),
    )?;
    let eclipses = lunar_eclipse::search(eph, span, ShadowModel::Danjon)?;
    let e: LunarEclipse = eclipses
        .into_iter()
        .min_by(|a, b| {
            (a.greatest.tt_seconds() - center.tt_seconds())
                .abs()
                .total_cmp(&(b.greatest.tt_seconds() - center.tt_seconds()).abs())
        })
        .ok_or_else(|| Error::InvalidTime(format!("在 {date} 前后 3 天内未找到月食")))?;

    let diag = lunar_eclipse::diagram(eph, &e, ShadowModel::Danjon, step_s)?;
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
        Some(obs) => Some(local_eclipse::lunar_altitudes(eph, &e, obs)?),
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
        "observer": at.map(|o| json!({
            "lat_deg": o.latitude_deg(),
            "lon_deg": o.longitude_deg(),
            "height_m": o.height,
        })),
        "radii_deg": {
            "penumbra": diag.penumbra_deg,
            "umbra": diag.umbra_deg,
            "moon": diag.moon_semidiameter_deg,
        },
        "contacts": contacts_json,
        "path": path_json,
    }))
}

pub fn build_solar_eclipse_json(
    eph: &dyn Ephemeris,
    date: &DateTime,
    at: Option<&Observer>,
    step_s: f64,
) -> Result<Value> {
    if !(1.0..=3600.0).contains(&step_s) {
        return Err(Error::InvalidTime("step_s 应在 1..=3600 秒之间".into()));
    }
    let center = Time::from_utc(date)?;
    let span = Span::new(
        center.add_seconds(-3.0 * 86_400.0),
        center.add_seconds(3.0 * 86_400.0),
    )?;
    let eclipses = solar_eclipse::search(eph, span)?;
    let e = eclipses
        .into_iter()
        .min_by(|a, b| {
            (a.greatest.tt_seconds() - center.tt_seconds())
                .abs()
                .total_cmp(&(b.greatest.tt_seconds() - center.tt_seconds()).abs())
        })
        .ok_or_else(|| Error::InvalidTime(format!("在 {date} 前后 3 天内未找到日食")))?;

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
            if let Some(loc) = local_eclipse::local_solar(eph, &e, obs, None)? {
                let (lkind_en, lkind_zh) = match loc.kind {
                    LocalSolarKind::Partial => ("partial", "日偏食"),
                    LocalSolarKind::Annular => ("annular", "日环食"),
                    LocalSolarKind::Total => ("total", "日全食"),
                };
                let t0 = loc.contacts[0]
                    .map_or(loc.maximum.tt_seconds() - 3600.0, |t| t.tt_seconds())
                    - 300.0;
                let t1 = loc.contacts[3]
                    .map_or(loc.maximum.tt_seconds() + 3600.0, |t| t.tt_seconds())
                    + 300.0;
                let n = ((t1 - t0) / step_s).ceil().max(1.0) as usize;
                let sample_times: Vec<Time> = (0..=n)
                    .map(|i| Time::from_tt_seconds((t0 + i as f64 * step_s).min(t1)))
                    .collect();
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
                            "sun_alt_deg": first.map(|f| f.sun_altitude_deg),
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
        "observer": at.map(|o| json!({
            "lat_deg": o.latitude_deg(),
            "lon_deg": o.longitude_deg(),
            "height_m": o.height,
        })),
        "diagram": {
            "l1": diag.l1,
            "l2": diag.l2,
            "d_deg": diag.d.to_degrees(),
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

    fn ephemeris() -> Option<AniseEphemeris> {
        let path = std::env::var_os("GUANXIANG_EPHEM")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../data/de440s.bsp")
            });
        if !path.exists() {
            return None;
        }
        Some(AniseEphemeris::from_path(&path).expect("加载 de440s"))
    }

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
