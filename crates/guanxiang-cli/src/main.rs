mod search;

use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use guanxiang_core::astrometry::{self, AU_KM, refraction};
use guanxiang_core::{AniseEphemeris, Body, DateTime, Ephemeris, Observer, Tdb, Time};

#[derive(Parser)]
#[command(name = "guanxiang", version, about = "观象：天文事件搜索工具")]
struct Cli {
    /// 星历文件路径。默认取 GUANXIANG_EPHEM，否则为 data/de440s.bsp
    #[arg(
        long,
        global = true,
        env = "GUANXIANG_EPHEM",
        default_value = "data/de440s.bsp"
    )]
    ephem: PathBuf,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// 显示星历文件的覆盖范围
    Info,
    /// 两个天体之间的几何距离与位置向量（ICRF，km）
    Distance {
        /// 目标天体，如 moon、月球
        target: Body,
        /// 中心天体，如 earth、地球
        #[arg(default_value = "earth")]
        center: Body,
        /// 时刻，TDB 儒略日（默认 J2000.0）
        #[arg(long, default_value_t = 2_451_545.0)]
        jd_tdb: f64,
    },
    /// 天体的视位置；给出 --at 时同时计算站心位置和地平坐标
    Position {
        /// 天体，如 moon、月球、jupiter
        body: Body,
        /// 时刻（UTC），如 2026-11-05T12:00:00；1960 年以前按 UT1 处理
        utc: DateTime,
        /// 测站：纬度,经度[,高度米]（度，东经、北纬为正）
        #[arg(long, value_name = "LAT,LON[,H]", allow_hyphen_values = true)]
        at: Option<Observer>,
        /// 指定 ΔT = TT − UT1（秒），默认用内置模型
        #[arg(long)]
        delta_t: Option<f64>,
        /// 计算折射用的气压（hPa）
        #[arg(long, default_value_t = 1010.0)]
        pressure: f64,
        /// 计算折射用的气温（°C）
        #[arg(long, default_value_t = 10.0)]
        temperature: f64,
    },
    /// 搜索合、冲、角距极小、凌日
    Search(search::SearchArgs),
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("错误：{e}");
            ExitCode::FAILURE
        }
    }
}

fn run(cli: Cli) -> guanxiang_core::Result<()> {
    let eph = AniseEphemeris::from_path(&cli.ephem)?;
    match cli.command {
        Command::Search(args) => search::run(&eph, &args)?,
        Command::Info => {
            println!("星历：{}", cli.ephem.display());
            for b in Body::ALL {
                match eph.coverage(b) {
                    Ok((start, end)) => println!(
                        "  {:<8} {:<6} JD {:.1} – {:.1}",
                        b.name(),
                        b.name_zh(),
                        start.to_jd(),
                        end.to_jd()
                    ),
                    Err(e) => println!("  {:<8} {:<6} 不可用：{e}", b.name(), b.name_zh()),
                }
            }
        }
        Command::Distance {
            target,
            center,
            jd_tdb,
        } => {
            let t = Tdb::from_jd(jd_tdb);
            let r = eph.position(target, center, t)?;
            let d = r.norm();
            println!(
                "{} → {} @ JD(TDB) {jd_tdb}",
                center.name_zh(),
                target.name_zh()
            );
            println!("  距离 = {d:.3} km = {:.9} AU", d / AU_KM);
            println!("  r    = ({:.3}, {:.3}, {:.3}) km", r.x, r.y, r.z);
        }
        Command::Position {
            body,
            utc,
            at,
            delta_t,
            pressure,
            temperature,
        } => {
            let mut t = Time::from_utc(&utc)?;
            if let Some(dt) = delta_t {
                t = t.with_delta_t(dt);
            }
            let scale = if utc.year < 1960 { "UT1" } else { "UTC" };
            let dt_note = if delta_t.is_some() {
                "指定"
            } else if t.delta_t_is_extrapolated() {
                "外推，不确定"
            } else {
                "IERS 实测表"
            };
            println!("{} @ {utc} {scale}", body.name_zh());
            println!(
                "  TT  JD {:.6}    ΔT = {:.3} s（{dt_note}）",
                t.tt_jd(),
                t.delta_t()
            );

            let geo = astrometry::geocentric(&eph, body, &t)?;
            println!("地心");
            print_place(&geo);

            if let Some(obs) = at {
                let topo = astrometry::topocentric(&eph, body, &t, &obs)?;
                println!(
                    "站心  纬度 {:.4}°  经度 {:.4}°  高度 {:.0} m",
                    obs.latitude_deg(),
                    obs.longitude_deg(),
                    obs.height
                );
                print_place(&topo.place);
                let h = topo.horizontal;
                let r = refraction(h.altitude, pressure, temperature);
                println!(
                    "  时角               {}",
                    hms(topo.hour_angle.rem_euclid(std::f64::consts::TAU))
                );
                println!("  方位角（北起向东） {:>12.5}°", h.azimuth.to_degrees());
                println!("  高度角（无大气）   {:>12.5}°", h.altitude.to_degrees());
                println!(
                    "  高度角（含折射）   {:>12.5}°   折射 {:.2}′（{pressure} hPa, {temperature} °C）",
                    (h.altitude + r).to_degrees(),
                    r.to_degrees() * 60.0
                );
            }
        }
    }
    Ok(())
}

fn print_place(p: &astrometry::Place) {
    println!(
        "  天体测量 RA/Dec（ICRF）     {}  {}",
        hms(p.astrometric.ra),
        dms(p.astrometric.dec)
    );
    println!(
        "  视位置 RA/Dec（真赤道春分点）{}  {}",
        hms(p.apparent.ra),
        dms(p.apparent.dec)
    );
    println!(
        "  距离 {:.3} km = {:.9} AU   光行时 {:.3} s",
        p.distance_km,
        p.distance_km / AU_KM,
        p.light_time_s
    );
}

/// 弧度 → `HHh MMm SS.sssss`
fn hms(rad: f64) -> String {
    let total = (rad.to_degrees() / 15.0).rem_euclid(24.0) * 3600.0;
    let total = (total * 1e4).round() / 1e4;
    let h = (total / 3600.0).floor();
    let m = ((total - h * 3600.0) / 60.0).floor();
    let s = total - h * 3600.0 - m * 60.0;
    format!("{:02}h{:02}m{:07.4}s", h as u32 % 24, m as u32, s)
}

/// 弧度 → `±DD°MM′SS.sss″`
fn dms(rad: f64) -> String {
    let sign = if rad < 0.0 { '-' } else { '+' };
    let total = (rad.abs().to_degrees() * 3600.0 * 1e3).round() / 1e3;
    let d = (total / 3600.0).floor();
    let m = ((total - d * 3600.0) / 60.0).floor();
    let s = total - d * 3600.0 - m * 60.0;
    format!("{sign}{:02}°{:02}′{:06.3}″", d as u32, m as u32, s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn angle_formatting() {
        assert_eq!(hms(0.0), "00h00m00.0000s");
        assert_eq!(hms(std::f64::consts::PI), "12h00m00.0000s");
        assert_eq!(
            hms((15.0f64 * (1.0 + 1.0 / 60.0 + 59.99999 / 3600.0)).to_radians()),
            "01h02m00.0000s"
        );
        assert_eq!(
            dms((-(10.0f64 + 30.0 / 60.0)).to_radians()),
            "-10°30′00.000″"
        );
        assert_eq!(dms(0.0), "+00°00′00.000″");
    }
}
