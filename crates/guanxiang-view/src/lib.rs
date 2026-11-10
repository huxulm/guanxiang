//! 观象的展示数据层：把 guanxiang-core 的计算结果整理成带物理单位的 JSON。
//!
//! CLI（`guanxiang scene`，供 Manim 使用）和 WebAssembly（浏览器版）共用这里的代码，
//! 保证两边结果一致。这里不含界面文案（只有给动画脚本用的中文标签），也不依赖 frb、clap、wasm-bindgen。
//!
//! - [`list`]：按年份搜索日月食，给列表页用。
//! - [`scene`]：单次日月食的完整时间序列（轨迹、接触时刻、观测地情况），格式与 `guanxiang scene` 相同。
//! - [`state`]：任意时刻的几何状态，动画逐帧调用。

pub mod list;
pub mod scene;
pub mod state;

use guanxiang_core::events::Span;
use guanxiang_core::events::lunar_eclipse::{self, LunarEclipse, ShadowModel};
use guanxiang_core::events::solar_eclipse::{self, SolarEclipse};
use guanxiang_core::{DateTime, Ephemeris, Error, Observer, Result, Time};
use serde_json::{Value, json};

/// 月食统一用 Danjon 地影放大（D16），与 App、NASA 星表一致。
pub const SHADOW_MODEL: ShadowModel = ShadowModel::Danjon;

/// UTC 时间，精确到秒，如 `2025-09-07 18:11:48`（`guanxiang scene` 的格式）。
pub fn utc_str(t: &Time) -> String {
    t.to_utc()
        .map(|d| d.to_string()[..19].replace('T', " "))
        .unwrap_or_else(|_| format!("TT JD {:.5}", t.tt_jd()))
}

/// UTC 时间，ISO 8601，精确到毫秒，如 `2025-09-07T18:11:48.123Z`。
/// `to_utc` 已经把秒舍入到毫秒并处理了进位，这里只做格式化。
pub fn utc_iso(t: &Time) -> Result<String> {
    let d = t.to_utc()?;
    let ms = (d.second * 1000.0).round() as u64;
    Ok(format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:03}Z",
        d.year,
        d.month,
        d.day,
        d.hour,
        d.minute,
        ms / 1000,
        ms % 1000
    ))
}

/// 一个时刻：UTC 字符串（显示用）和 J2000.0 起算的 TT 秒数（精确计算、比对用）。
pub fn time_json(t: &Time) -> Result<Value> {
    Ok(json!({ "utc": utc_iso(t)?, "tt": t.tt_seconds() }))
}

/// 观测地，格式与 `guanxiang scene` 相同。
pub fn observer_json(o: &Observer) -> Value {
    json!({
        "lat_deg": o.latitude_deg(),
        "lon_deg": o.longitude_deg(),
        "height_m": o.height,
    })
}

/// 某天前后 3 天内的时间段。
fn span_around(center: &Time) -> Result<Span> {
    Span::new(
        center.add_seconds(-3.0 * 86_400.0),
        center.add_seconds(3.0 * 86_400.0),
    )
}

/// 食甚离 `center` 最近的一项。
fn nearest<T>(items: Vec<T>, center: &Time, greatest: impl Fn(&T) -> Time) -> Option<T> {
    let tc = center.tt_seconds();
    items.into_iter().min_by(|a, b| {
        (greatest(a).tt_seconds() - tc)
            .abs()
            .total_cmp(&(greatest(b).tt_seconds() - tc).abs())
    })
}

/// 找 `date`（UTC）前后 3 天内食甚最近的月食。
pub fn find_lunar_eclipse(eph: &dyn Ephemeris, date: &DateTime) -> Result<LunarEclipse> {
    let center = Time::from_utc(date)?;
    let found = lunar_eclipse::search(eph, span_around(&center)?, SHADOW_MODEL)?;
    nearest(found, &center, |e| e.greatest)
        .ok_or_else(|| Error::InvalidTime(format!("在 {date} 前后 3 天内未找到月食")))
}

/// 找 `date`（UTC）前后 3 天内食甚最近的日食。
pub fn find_solar_eclipse(eph: &dyn Ephemeris, date: &DateTime) -> Result<SolarEclipse> {
    let center = Time::from_utc(date)?;
    let found = solar_eclipse::search(eph, span_around(&center)?)?;
    nearest(found, &center, |e| e.greatest)
        .ok_or_else(|| Error::InvalidTime(format!("在 {date} 前后 3 天内未找到日食")))
}

/// 测试用：加载星历。路径取 `GUANXIANG_EPHEM`，否则为仓库根目录的 `data/de440s.bsp`；找不到时返回 None（测试跳过）。
#[cfg(test)]
pub(crate) fn test_ephemeris() -> Option<guanxiang_core::AniseEphemeris> {
    let path = std::env::var_os("GUANXIANG_EPHEM")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../data/de440s.bsp")
        });
    if !path.exists() {
        return None;
    }
    Some(guanxiang_core::AniseEphemeris::from_path(&path).expect("加载星历"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utc_iso_carries_into_next_minute() {
        let t = Time::from_utc(&DateTime::new(2025, 9, 7, 18, 11, 59.9996).unwrap()).unwrap();
        assert_eq!(utc_iso(&t).unwrap(), "2025-09-07T18:12:00.000Z");
        let t = Time::from_utc(&DateTime::new(2025, 9, 7, 18, 11, 48.1234).unwrap()).unwrap();
        assert_eq!(utc_iso(&t).unwrap(), "2025-09-07T18:11:48.123Z");
    }
}
