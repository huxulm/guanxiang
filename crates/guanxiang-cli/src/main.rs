use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use guanxiang_core::{AniseEphemeris, Body, Ephemeris, Tdb};

const AU_KM: f64 = 149_597_870.7;

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
    }
    Ok(())
}
