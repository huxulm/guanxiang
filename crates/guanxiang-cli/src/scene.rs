//! `guanxiang scene`：导出供 Manim 等演示动画工具使用的结构化场景 JSON。
//!
//! 场景的计算和 JSON 格式在 `guanxiang-view` 的 `scene` 模块（浏览器版共用），这里只负责参数和输出。

use std::fs;
use std::path::PathBuf;

use clap::{Args, Subcommand};
use guanxiang_core::{AniseEphemeris, Body, DateTime, Error, Observer, Result};
use guanxiang_view::scene::{
    build_ephem_track_json, build_lunar_eclipse_json, build_solar_eclipse_json,
};
use serde_json::Value;

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
