//! `guanxiang search`：事件搜索。

use std::path::PathBuf;

use clap::{Args, ValueEnum};
use guanxiang_core::events::catalog::{self, Kind, Record};
use guanxiang_core::events::longitude::{self, Aspect};
use guanxiang_core::events::visibility::{VisibilityFilter, apparent_altitude};
use guanxiang_core::events::{Span, separation, transit};
use guanxiang_core::{AniseEphemeris, Body, DateTime, Error, Observer, Result, Time};

#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum EventKind {
    /// 合（黄经相同）
    Conjunction,
    /// 冲（黄经差 180°）
    Opposition,
    /// 角距极小（需 --bodies）
    Appulse,
    /// 水星、金星凌日
    Transit,
}

#[derive(Args)]
pub struct SearchArgs {
    /// 事件类型
    #[arg(long, value_enum)]
    kind: EventKind,
    /// 开始时间（UTC）：年份或日期，如 2000、2026-11-05
    #[arg(long)]
    from: String,
    /// 结束时间（UTC），格式同 --from
    #[arg(long)]
    to: String,
    /// 天体对，如 moon,jupiter；凌日时为 mercury 或 venus。默认：合 = 各行星与太阳，冲 = 外行星与太阳，凌日 = 水星和金星
    #[arg(long, value_delimiter = ',')]
    bodies: Vec<Body>,
    /// 角距极小的上限（度）
    #[arg(long, default_value_t = 5.0)]
    max_sep: f64,
    /// 只保留在此测站可见的事件：纬度,经度[,高度米]
    #[arg(long, value_name = "LAT,LON[,H]", allow_hyphen_values = true)]
    at: Option<Observer>,
    /// 可见性：目标最低视高度角（度）
    #[arg(long, default_value_t = 0.0, allow_hyphen_values = true)]
    min_alt: f64,
    /// 可见性：太阳最高视高度角（度），凌日不使用
    #[arg(long, default_value_t = -6.0, allow_hyphen_values = true)]
    max_sun_alt: f64,
    /// 把结果写入预计算星表文件（.gxev）
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

fn fmt_time(t: &Time) -> String {
    t.to_utc()
        .map(|d| d.to_string()[..19].replace('T', " "))
        .unwrap_or_else(|_| format!("TT JD {:.5}", t.tt_jd()))
}

fn arcsec(rad: f64) -> f64 {
    rad.to_degrees() * 3600.0
}

const PLANETS: [Body; 7] = [
    Body::Mercury,
    Body::Venus,
    Body::Mars,
    Body::Jupiter,
    Body::Saturn,
    Body::Uranus,
    Body::Neptune,
];

fn pairs(args: &SearchArgs) -> Result<Vec<(Body, Body)>> {
    match (args.kind, args.bodies.as_slice()) {
        (EventKind::Transit, _) => Ok(vec![]),
        (_, [a, b]) => Ok(vec![(*a, *b)]),
        (EventKind::Conjunction, []) => Ok(PLANETS.iter().map(|&p| (p, Body::Sun)).collect()),
        (EventKind::Opposition, []) => Ok(PLANETS[2..].iter().map(|&p| (p, Body::Sun)).collect()),
        _ => Err(Error::Unsupported("--bodies 需要两个天体，如 moon,jupiter")),
    }
}

pub fn run(eph: &AniseEphemeris, args: &SearchArgs) -> Result<()> {
    let span = Span::new(parse_time(&args.from)?, parse_time(&args.to)?)?;
    let filter = args.at.map(|observer| VisibilityFilter {
        observer,
        min_altitude: args.min_alt.to_radians(),
        max_sun_altitude: Some(args.max_sun_alt.to_radians()),
    });
    let mut records = Vec::new();

    match args.kind {
        EventKind::Conjunction | EventKind::Opposition => {
            let aspect = if matches!(args.kind, EventKind::Conjunction) {
                Aspect::Conjunction
            } else {
                Aspect::Opposition
            };
            println!(
                "{:<20} {:<16} {:>10} {:>10}",
                "时间（UTC）", "天体", "角距", "黄纬差"
            );
            for (a, b) in pairs(args)? {
                let step = longitude::default_step_days(a, b);
                for e in longitude::search(eph, a, b, aspect, span, step)? {
                    if let Some(f) = &filter
                        && !f.is_visible(eph, &[a, b], &e.time)?
                    {
                        continue;
                    }
                    let note = if a != Body::Moon && b == Body::Sun && aspect == Aspect::Conjunction
                    {
                        if e.distance_a_km < e.distance_b_km {
                            "  下合"
                        } else {
                            "  上合"
                        }
                    } else {
                        ""
                    };
                    println!(
                        "{:<20} {:<16} {:>9.4}° {:>9.4}°{note}",
                        fmt_time(&e.time),
                        format!("{}-{}", a.name_zh(), b.name_zh()),
                        e.separation.to_degrees(),
                        e.latitude_difference.to_degrees()
                    );
                    records.push(Record {
                        kind: if aspect == Aspect::Conjunction {
                            Kind::Conjunction
                        } else {
                            Kind::Opposition
                        },
                        a,
                        b,
                        flags: 0,
                        tt: e.time.tt_seconds(),
                        values: [e.separation, e.latitude_difference, f64::NAN, f64::NAN],
                    });
                }
            }
        }
        EventKind::Appulse => {
            let max = args.max_sep.to_radians();
            println!("{:<20} {:<16} {:>10}", "时间（UTC）", "天体", "角距");
            for (a, b) in pairs(args)? {
                let step = separation::default_step_days(a, b);
                for m in separation::search(eph, a, b, span, step, max)? {
                    if let Some(f) = &filter
                        && !f.is_visible(eph, &[a, b], &m.time)?
                    {
                        continue;
                    }
                    println!(
                        "{:<20} {:<16} {:>9.4}°",
                        fmt_time(&m.time),
                        format!("{}-{}", a.name_zh(), b.name_zh()),
                        m.separation.to_degrees()
                    );
                    records.push(Record {
                        kind: Kind::SeparationMinimum,
                        a,
                        b,
                        flags: 0,
                        tt: m.time.tt_seconds(),
                        values: [m.separation, f64::NAN, f64::NAN, f64::NAN],
                    });
                }
            }
        }
        EventKind::Transit => {
            let planets: Vec<Body> = if args.bodies.is_empty() {
                vec![Body::Mercury, Body::Venus]
            } else {
                args.bodies.clone()
            };
            for p in planets {
                for t in transit::search(eph, p, span)? {
                    // 本地可见：任一接触或凌甚时太阳在地平线上
                    let mut sun_alt = None;
                    if let Some(f) = &filter {
                        let moments = t
                            .contacts
                            .iter()
                            .flatten()
                            .chain(std::iter::once(&t.greatest));
                        let mut best = f64::NEG_INFINITY;
                        for m in moments {
                            best = best.max(apparent_altitude(eph, Body::Sun, m, &f.observer)?);
                        }
                        if best < 0.0 {
                            continue;
                        }
                        sun_alt =
                            Some(apparent_altitude(eph, Body::Sun, &t.greatest, &f.observer)?);
                    }
                    println!(
                        "{}凌日  凌甚 {}  角距 {:.1}″（日半径 {:.1}″）{}",
                        p.name_zh(),
                        fmt_time(&t.greatest),
                        arcsec(t.min_separation),
                        arcsec(t.sun_semidiameter),
                        if t.is_full() { "" } else { "  掠凌" }
                    );
                    let names = ["外切入 I ", "内切入 II", "内切出 III", "外切出 IV"];
                    for (name, c) in names.iter().zip(&t.contacts) {
                        if let Some(c) = c {
                            println!("    {name}  {}", fmt_time(c));
                        }
                    }
                    if let Some(h) = sun_alt {
                        println!("    凌甚时太阳高度 {:.1}°", h.to_degrees());
                    }
                    let tt = |c: &Option<Time>| c.map_or(f64::NAN, |c| c.tt_seconds());
                    records.push(Record {
                        kind: Kind::Transit,
                        a: p,
                        b: Body::Sun,
                        flags: u8::from(t.is_full()),
                        tt: t.greatest.tt_seconds(),
                        values: [
                            tt(&t.contacts[0]),
                            tt(&t.contacts[1]),
                            tt(&t.contacts[2]),
                            tt(&t.contacts[3]),
                        ],
                    });
                }
            }
        }
    }

    println!("共 {} 个事件", records.len());
    if let Some(path) = &args.out {
        std::fs::write(path, catalog::encode(&records))
            .map_err(|e| Error::Catalog(format!("{}：{e}", path.display())))?;
        println!("已写入 {}", path.display());
    }
    Ok(())
}
