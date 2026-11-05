//! `guanxiang satellite`：卫星凌日、凌月。
//!
//! 按 D5，Rust 不做网络请求：根数从文件读取（CelesTrak `gp.php?CATNR=…&FORMAT=JSON` 的输出）。

use std::path::PathBuf;
use std::time::Instant;

use clap::Args;
use guanxiang_core::events::Span;
use guanxiang_core::events::sat_transit;
use guanxiang_core::satellite::Satellite;
use guanxiang_core::{AniseEphemeris, Body, Error, Observer, Result, Time};

#[derive(Args)]
pub struct SatelliteArgs {
    /// OMM JSON 文件（CelesTrak FORMAT=JSON，可含多颗卫星）
    #[arg(long)]
    omm: PathBuf,
    /// 测站：纬度,经度[,高度米]
    #[arg(long, value_name = "LAT,LON[,H]", allow_hyphen_values = true)]
    at: Observer,
    /// 从根数历元起搜索的天数（根数越旧越不准，建议 ≤ 7）
    #[arg(long, default_value_t = 7.0)]
    days: f64,
    /// 列出视角距不超过此值（度）的接近，包括未穿过日面、月面的
    #[arg(long, default_value_t = 1.0)]
    max_sep: f64,
}

fn utc(t: &Time) -> String {
    t.to_utc()
        .map(|d| d.to_string()[..23].replace('T', " "))
        .unwrap_or_else(|_| format!("TT JD {:.6}", t.tt_jd()))
}

pub fn run(eph: &AniseEphemeris, args: &SatelliteArgs) -> Result<()> {
    let text = std::fs::read_to_string(&args.omm)
        .map_err(|e| Error::Satellite(format!("{}：{e}", args.omm.display())))?;
    let sats = Satellite::from_omm_json(&text)?;
    let started = Instant::now();
    let mut n = 0;
    for sat in &sats {
        println!(
            "{}（NORAD {}），根数历元 {} UTC",
            sat.name,
            sat.norad_id,
            utc(&sat.epoch)
        );
        let span = Span::new(sat.epoch, sat.epoch.add_seconds(args.days * 86_400.0))?;
        let found = sat_transit::search(
            eph,
            sat,
            &[Body::Sun, Body::Moon],
            span,
            &args.at,
            args.max_sep.to_radians(),
            None,
        )?;
        for e in found {
            let what = match (e.body, e.is_transit()) {
                (Body::Sun, true) => "凌日",
                (Body::Moon, true) => "凌月",
                (Body::Sun, false) => "近日（未凌）",
                _ => "近月（未凌）",
            };
            let dur = e
                .duration_s
                .map_or(String::new(), |d| format!("  历时 {d:.2} s"));
            println!(
                "  {}  {what}  角距 {:.1}′（视半径 {:.1}′）{dur}  距离 {:.0} km  高度 {:.0}° 方位 {:.0}°",
                utc(&e.closest),
                e.min_separation.to_degrees() * 60.0,
                e.body_semidiameter.to_degrees() * 60.0,
                e.range_km,
                e.altitude_deg,
                e.azimuth_deg
            );
            println!(
                "      离中心线 {:.2} km（最近点 {:.4}°, {:.4}°），可见带半宽约 {:.2} km，根数龄期 {:.1} 天",
                e.distance_to_centerline_km,
                e.centerline_nearest.0,
                e.centerline_nearest.1,
                e.band_half_width_km,
                e.elements_age_days
            );
            n += 1;
        }
    }
    println!("共 {n} 次，用时 {:.2} s", started.elapsed().as_secs_f64());
    Ok(())
}
