//! 观象的 WebAssembly 接口（Web 应用 P0 技术验证）。
//!
//! 浏览器里没有文件系统：星历由 JS 下载或读取后整块传进来，用 [`AniseEphemeris::from_vec`] 加载。
//! 计算结果先用 JSON 字符串返回，JS 端 `JSON.parse`；接口稳定后再换成带 TS 类型的结构体。
//! 计算部分写成普通 Rust 函数（[`lunar_eclipses_json`]），本机 `cargo test` 就能测，不依赖 JS 环境。

use guanxiang_core::events::Span;
use guanxiang_core::events::lunar_eclipse::{self, LunarEclipseKind, ShadowModel};
use guanxiang_core::{AniseEphemeris, DateTime, Ephemeris, Time};
use serde_json::{Value, json};
use wasm_bindgen::prelude::*;

/// 已加载星历的计算引擎。
#[wasm_bindgen]
pub struct Engine {
    eph: AniseEphemeris,
}

#[wasm_bindgen]
impl Engine {
    /// 用 SPK 星历（如 de440s_1900_2100.bsp）的全部字节创建引擎。
    #[wasm_bindgen(constructor)]
    pub fn new(bytes: Vec<u8>) -> Result<Engine, JsError> {
        let eph = AniseEphemeris::from_vec(bytes).map_err(to_js)?;
        Ok(Engine { eph })
    }

    /// 搜索 `from_year` 年初到 `to_year` 年初（UTC）之间的月食，返回 JSON 数组字符串。
    #[wasm_bindgen(js_name = lunarEclipses)]
    pub fn lunar_eclipses(&self, from_year: i32, to_year: i32) -> Result<String, JsError> {
        let val = lunar_eclipses_json(&self.eph, from_year, to_year).map_err(to_js)?;
        Ok(val.to_string())
    }
}

fn to_js(e: guanxiang_core::Error) -> JsError {
    JsError::new(&e.to_string())
}

/// 某年 1 月 1 日 0 时（UTC）。
fn year_start(year: i32) -> guanxiang_core::Result<Time> {
    Time::from_utc(&DateTime::new(year, 1, 1, 0, 0, 0.0)?)
}

/// UTC 时间，精确到毫秒，如 `2025-09-07T18:11:48.123Z`。
/// `to_utc` 已经把秒舍入到毫秒并处理了进位，这里只做格式化。
fn utc_iso(t: &Time) -> guanxiang_core::Result<String> {
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

/// 一个时刻：UTC 字符串（显示用）和 J2000.0 起算的 TT 秒数（精确比对用）。
fn time_json(t: &Time) -> guanxiang_core::Result<Value> {
    Ok(json!({ "utc": utc_iso(t)?, "tt": t.tt_seconds() }))
}

/// 搜索 `[from_year, to_year)` 内的月食（Danjon 地影放大，与 App 默认一致）。
///
/// 每条记录：`kind`（penumbral / partial / total）、`greatest`、`gamma`、
/// `penumbralMagnitude`、`umbralMagnitude`、`contacts`（P1、U1、U2、U3、U4、P4，没有的为 null）。
pub fn lunar_eclipses_json(
    eph: &dyn Ephemeris,
    from_year: i32,
    to_year: i32,
) -> guanxiang_core::Result<Value> {
    let span = Span::new(year_start(from_year)?, year_start(to_year)?)?;
    let mut out = Vec::new();
    for e in lunar_eclipse::search(eph, span, ShadowModel::Danjon)? {
        let kind = match e.kind {
            LunarEclipseKind::Penumbral => "penumbral",
            LunarEclipseKind::Partial => "partial",
            LunarEclipseKind::Total => "total",
        };
        let contacts = e
            .contacts
            .iter()
            .map(|c| c.as_ref().map(time_json).transpose())
            .collect::<guanxiang_core::Result<Vec<_>>>()?;
        out.push(json!({
            "kind": kind,
            "greatest": time_json(&e.greatest)?,
            "gamma": e.gamma,
            "penumbralMagnitude": e.penumbral_magnitude,
            "umbralMagnitude": e.umbral_magnitude,
            "contacts": contacts,
        }));
    }
    Ok(Value::Array(out))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    /// 用 `from_vec` 加载星历（和浏览器里同一条路径）；找不到文件时返回 None，测试跳过。
    fn ephemeris() -> Option<AniseEphemeris> {
        let path = std::env::var_os("GUANXIANG_EPHEM")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../data/de440s.bsp")
            });
        let bytes = std::fs::read(&path).ok()?;
        Some(AniseEphemeris::from_vec(bytes).expect("加载星历"))
    }

    #[test]
    fn lunar_eclipses_2025() {
        let Some(eph) = ephemeris() else {
            eprintln!("找不到星历，跳过");
            return;
        };
        let val = lunar_eclipses_json(&eph, 2025, 2026).unwrap();
        let list = val.as_array().unwrap();
        // 2025 年有两次月全食：3 月 14 日、9 月 7 日
        assert_eq!(list.len(), 2);
        for (e, date) in list.iter().zip(["2025-03-14", "2025-09-07"]) {
            assert_eq!(e["kind"], "total");
            assert!(e["greatest"]["utc"].as_str().unwrap().starts_with(date));
            assert_eq!(e["contacts"].as_array().unwrap().len(), 6);
            assert!(
                e["contacts"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .all(|c| c.is_object())
            );
        }
    }

    /// 设置 `GUANXIANG_DUMP=<文件>` 时，把 2025–2035 年的月食写成 JSON，
    /// 供 Node 里的 wasm 结果逐项比对（本机与 wasm 应当一致）。
    #[test]
    fn dump_for_wasm_check() {
        let Some(out) = std::env::var_os("GUANXIANG_DUMP") else {
            return;
        };
        let eph = ephemeris().expect("比对需要星历");
        let val = lunar_eclipses_json(&eph, 2025, 2035).unwrap();
        std::fs::write(out, val.to_string()).unwrap();
    }

    #[test]
    fn utc_iso_carries_into_next_minute() {
        let t = Time::from_utc(&DateTime::new(2025, 9, 7, 18, 11, 59.9996).unwrap()).unwrap();
        assert_eq!(utc_iso(&t).unwrap(), "2025-09-07T18:12:00.000Z");
        let t = Time::from_utc(&DateTime::new(2025, 9, 7, 18, 11, 48.1234).unwrap()).unwrap();
        assert_eq!(utc_iso(&t).unwrap(), "2025-09-07T18:11:48.123Z");
    }
}
