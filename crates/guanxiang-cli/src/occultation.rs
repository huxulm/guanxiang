//! `guanxiang occultation`：月掩星。

use std::time::Instant;

use clap::Args;
use guanxiang_core::events::Span;
use guanxiang_core::events::occultation::{self, Candidate, Target};
use guanxiang_core::{AniseEphemeris, Body, DateTime, Error, Observer, Result, Time, stars};

#[derive(Args)]
pub struct OccultationArgs {
    /// 目标：行星（venus、火星…）、星名（角宿一）、HIP 编号（HIP 65474），
    /// 或 stars（星表全部 550 颗亮星）、planets（全部行星）、all
    #[arg(long)]
    target: String,
    /// 开始年份（含）或日期（UTC）
    #[arg(long)]
    from: String,
    /// 结束年份（不含）或日期（UTC）
    #[arg(long)]
    to: String,
    /// 测站：纬度,经度[,高度米]。不给时只列出地心候选（地球上某处可能看到）
    #[arg(long, value_name = "LAT,LON[,H]", allow_hyphen_values = true)]
    at: Option<Observer>,
    /// 测站模式下也列出月球在地平线下的掩星
    #[arg(long)]
    include_below_horizon: bool,
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

const PLANETS: [Body; 7] = [
    Body::Mercury,
    Body::Venus,
    Body::Mars,
    Body::Jupiter,
    Body::Saturn,
    Body::Uranus,
    Body::Neptune,
];

fn collect_candidates(eph: &AniseEphemeris, key: &str, span: Span) -> Result<Vec<Candidate>> {
    let mut out = Vec::new();
    let want_planets = matches!(key, "planets" | "all");
    let want_stars = matches!(key, "stars" | "all");
    if want_planets {
        for p in PLANETS {
            out.extend(occultation::candidates(eph, Target::Planet(p), span)?);
        }
    }
    if want_stars {
        out.extend(occultation::candidates_all_stars(eph, span)?);
    }
    if !want_planets && !want_stars {
        let target = if let Ok(b) = key.parse::<Body>() {
            Target::Planet(b)
        } else {
            Target::Star(stars::find(key).ok_or(Error::Unsupported(
                "星表中找不到这颗星（V < 6.0、黄纬 6.6° 以内）",
            ))?)
        };
        out.extend(occultation::candidates(eph, target, span)?);
    }
    out.sort_by(|a, b| a.time.tt_seconds().total_cmp(&b.time.tt_seconds()));
    Ok(out)
}

fn vmag(t: &Target) -> String {
    match t {
        Target::Star(s) => format!("{:.1} 等", s.vmag),
        Target::Planet(_) => "行星".into(),
    }
}

pub fn run(eph: &AniseEphemeris, args: &OccultationArgs) -> Result<()> {
    let span = Span::new(parse_time(&args.from)?, parse_time(&args.to)?)?;
    let started = Instant::now();
    let cands = collect_candidates(eph, args.target.trim(), span)?;

    let mut n = 0;
    match &args.at {
        None => {
            println!("地心候选（月心与目标几何角距小于 1.6°，地球上某处可能看到掩星）");
            for c in &cands {
                println!(
                    "  {}  {:<10} {:<6}  地心角距 {:.3}°",
                    utc(&c.time),
                    c.target.label(),
                    vmag(&c.target),
                    c.separation.to_degrees()
                );
                n += 1;
            }
        }
        Some(obs) => {
            println!("本地月掩星（时刻 UTC；高度含折射）");
            for c in &cands {
                let Some(o) = occultation::local(eph, c, obs, None)? else {
                    continue;
                };
                if !args.include_below_horizon && !o.moon_above_horizon() {
                    continue;
                }
                let day = if o.sun_altitude_deg.iter().all(|&h| h > -6.0) {
                    "  白天"
                } else {
                    ""
                };
                println!(
                    "  {:<10} {:<6}  掩始 {}  掩终 {}  月亮高度 {:.0}°/{:.0}°  太阳高度 {:.0}°/{:.0}°{day}",
                    o.target.label(),
                    vmag(&o.target),
                    utc(&o.disappearance),
                    &utc(&o.reappearance)[11..],
                    o.moon_altitude_deg[0],
                    o.moon_altitude_deg[1],
                    o.sun_altitude_deg[0],
                    o.sun_altitude_deg[1]
                );
                n += 1;
            }
        }
    }
    println!("共 {n} 次，用时 {:.2} s", started.elapsed().as_secs_f64());
    Ok(())
}
