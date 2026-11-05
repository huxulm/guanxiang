//! `guanxiang eclipse`：日月食搜索与预计算星表。

use std::path::PathBuf;
use std::time::Instant;

use clap::{Args, ValueEnum};
use guanxiang_core::events::Span;
use guanxiang_core::events::catalog::{self, Kind, Record};
use guanxiang_core::events::local_eclipse::{self, LocalSolarKind};
use guanxiang_core::events::lunar_eclipse::{self, LunarEclipseKind, ShadowModel};
use guanxiang_core::events::solar_eclipse::{self, SolarEclipseKind};
use guanxiang_core::{AniseEphemeris, Body, DateTime, Error, Observer, Result, Time};

#[derive(Clone, Copy, Debug, ValueEnum, PartialEq, Eq)]
pub enum Which {
    Solar,
    Lunar,
    All,
}

#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum Model {
    Danjon,
    Chauvenet,
}

#[derive(Args)]
pub struct EclipseArgs {
    /// 开始年份（含，UTC 1 月 1 日）或日期
    #[arg(long)]
    from: String,
    /// 结束年份（不含）或日期
    #[arg(long)]
    to: String,
    /// 日食、月食或全部
    #[arg(long, value_enum, default_value = "all")]
    kind: Which,
    /// 月食地影放大模型
    #[arg(long, value_enum, default_value = "danjon")]
    model: Model,
    /// 给出测站时计算本地情况，只列出可见的食：纬度,经度[,高度米]
    #[arg(long, value_name = "LAT,LON[,H]", allow_hyphen_values = true)]
    at: Option<Observer>,
    /// 中心食额外计算食甚点和中心持续时间（稍慢）
    #[arg(long)]
    details: bool,
    /// 写入预计算星表文件（.gxev）
    #[arg(long)]
    out: Option<PathBuf>,
}

fn parse_time(s: &str) -> Result<Time> {
    let text = if s.len() == 4 && s.chars().all(|c| c.is_ascii_digit()) {
        format!("{s}-01-01")
    } else {
        s.to_string()
    };
    Time::from_utc(&text.parse::<DateTime>()?)
}

fn utc(t: &Time) -> String {
    t.to_utc()
        .map(|d| d.to_string()[..19].replace('T', " "))
        .unwrap_or_else(|_| format!("TT JD {:.5}", t.tt_jd()))
}

fn hms(t: &Option<Time>) -> String {
    t.map_or("        ".into(), |t| utc(&t)[11..19].to_string())
}

fn solar_code(e: &solar_eclipse::SolarEclipse) -> (&'static str, u8) {
    let (name, code) = match e.kind {
        SolarEclipseKind::Partial => ("日偏食", 1),
        SolarEclipseKind::Annular => ("日环食", 2),
        SolarEclipseKind::Total => ("日全食", 3),
        SolarEclipseKind::Hybrid => ("全环食", 4),
    };
    let non_central = e.kind != SolarEclipseKind::Partial && !e.central;
    (name, code | if non_central { 0x10 } else { 0 })
}

pub fn run(eph: &AniseEphemeris, args: &EclipseArgs) -> Result<()> {
    let span = Span::new(parse_time(&args.from)?, parse_time(&args.to)?)?;
    let started = Instant::now();
    let mut records = Vec::new();

    if args.kind != Which::Lunar {
        println!("日食（时刻 UTC；γ 和食分为全球值）");
        for e in solar_eclipse::search(eph, span)? {
            let (name, flags) = solar_code(&e);
            let mut line = format!(
                "  {}  {}{}  γ {:+.4}  食分 {:.4}",
                utc(&e.greatest),
                name,
                if flags & 0x10 != 0 {
                    "（非中心）"
                } else {
                    ""
                },
                e.gamma,
                e.magnitude
            );
            let point = e.greatest_point;
            if args.details {
                if let Some(p) = point {
                    let obs = Observer::from_degrees(p.latitude_deg, p.longitude_deg, 0.0)?;
                    let dur = local_eclipse::local_solar(eph, &e, &obs, None)?
                        .and_then(|l| l.central_duration_s());
                    line.push_str(&format!(
                        "  食甚点 {:.1}°, {:.1}°  太阳高度 {:.0}°  带宽 {:.0} km",
                        p.latitude_deg, p.longitude_deg, p.sun_altitude_deg, p.path_width_km
                    ));
                    if let Some(d) = dur {
                        line.push_str(&format!("  持续 {}m{:02.0}s", (d / 60.0).floor(), d % 60.0));
                    }
                }
            }
            if let Some(obs) = &args.at {
                match local_eclipse::local_solar(eph, &e, obs, None)? {
                    Some(l) if l.is_visible() => {
                        let k = match l.kind {
                            LocalSolarKind::Partial => "偏食",
                            LocalSolarKind::Annular => "环食",
                            LocalSolarKind::Total => "全食",
                        };
                        println!("{line}");
                        println!(
                            "      本地{k}  食甚 {}  食分 {:.3}  食面积 {:.1}%  初亏 {} 食既 {} 生光 {} 复圆 {}  太阳高度 {:.0}°/{:.0}°/{:.0}°",
                            utc(&l.maximum),
                            l.magnitude,
                            l.obscuration * 100.0,
                            hms(&l.contacts[0]),
                            hms(&l.contacts[1]),
                            hms(&l.contacts[2]),
                            hms(&l.contacts[3]),
                            l.sun_altitude_deg[0],
                            l.sun_altitude_deg[1],
                            l.sun_altitude_deg[2]
                        );
                    }
                    _ => continue,
                }
            } else {
                println!("{line}");
            }
            let (lat, lon) =
                point.map_or((f64::NAN, f64::NAN), |p| (p.latitude_deg, p.longitude_deg));
            records.push(Record {
                kind: Kind::SolarEclipse,
                a: Body::Moon,
                b: Body::Sun,
                flags,
                tt: e.greatest.tt_seconds(),
                values: [e.gamma, e.magnitude, lat, lon],
            });
        }
    }

    if args.kind != Which::Solar {
        let model = match args.model {
            Model::Danjon => ShadowModel::Danjon,
            Model::Chauvenet => ShadowModel::Chauvenet,
        };
        println!("月食（时刻 UTC）");
        for e in lunar_eclipse::search(eph, span, model)? {
            let (name, code) = match e.kind {
                LunarEclipseKind::Penumbral => ("半影月食", 1),
                LunarEclipseKind::Partial => ("月偏食", 2),
                LunarEclipseKind::Total => ("月全食", 3),
            };
            let line = format!(
                "  {}  {name}  γ {:+.4}  半影食分 {:.4}  本影食分 {:.4}",
                utc(&e.greatest),
                e.gamma,
                e.penumbral_magnitude,
                e.umbral_magnitude
            );
            if let Some(obs) = &args.at {
                let alt = local_eclipse::lunar_altitudes(eph, &e, obs)?;
                if !alt.iter().any(|h| *h > 0.0) {
                    continue;
                }
                println!("{line}");
                let c = &e.contacts;
                println!(
                    "      P1 {} U1 {} U2 {} U3 {} U4 {} P4 {}  食甚月亮高度 {:.0}°",
                    hms(&c[0]),
                    hms(&c[1]),
                    hms(&c[2]),
                    hms(&c[3]),
                    hms(&c[4]),
                    hms(&c[5]),
                    alt[3]
                );
            } else {
                println!("{line}");
            }
            records.push(Record {
                kind: Kind::LunarEclipse,
                a: Body::Moon,
                b: Body::Earth,
                flags: code,
                tt: e.greatest.tt_seconds(),
                values: [e.gamma, e.penumbral_magnitude, e.umbral_magnitude, f64::NAN],
            });
        }
    }

    println!(
        "共 {} 次，用时 {:.2} s",
        records.len(),
        started.elapsed().as_secs_f64()
    );
    if let Some(path) = &args.out {
        std::fs::write(path, catalog::encode(&records))
            .map_err(|e| Error::Catalog(format!("{}：{e}", path.display())))?;
        println!("已写入 {}", path.display());
    }
    Ok(())
}
