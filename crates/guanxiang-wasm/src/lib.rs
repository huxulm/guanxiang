//! 观象的 WebAssembly 接口：浏览器版在 Web Worker 里调用。
//!
//! 浏览器里没有文件系统：星历由 JS 下载或读取后整块传进来，用 [`AniseEphemeris::from_vec`] 加载。
//! 计算和 JSON 格式都在 `guanxiang-view`（与 CLI `scene` 共用），这里只做 JS 绑定。
//! 结果以 JSON 字符串返回，JS 端 `JSON.parse`；字段名统一为 snake_case，与场景 JSON 一致。
//!
//! 用法（JS）：
//!
//! ```js
//! const engine = new Engine(bspBytes);
//! const list = JSON.parse(engine.lunarEclipses(2025, 2026));   // 前端按年分块调用，好显示进度、取消
//! const ecl = engine.lunarEclipse("2025-09-07");               // 找当天前后 3 天内最近的一次
//! const scene = JSON.parse(ecl.scene(engine, 39.9, 116.4, 50, 60));
//! const frame = JSON.parse(ecl.stateAt(engine, -1800, 39.9, 116.4, 50)); // 食甚前 30 分钟
//! ```
//!
//! 观测地参数（纬度、经度为度，东经、北纬为正；高度为米）都可以省略（传 `undefined`），省略纬度或经度时不算本地情况。

use guanxiang_core::events::lunar_eclipse::LunarEclipse;
use guanxiang_core::events::solar_eclipse::SolarEclipse;
use guanxiang_core::{AniseEphemeris, DateTime, Observer};
use guanxiang_view::{list, scene, state};
use wasm_bindgen::prelude::*;

/// 已加载星历的计算引擎。
#[wasm_bindgen]
pub struct Engine {
    eph: AniseEphemeris,
}

fn to_js(e: guanxiang_core::Error) -> JsError {
    JsError::new(&e.to_string())
}

fn parse_date(date: &str) -> Result<DateTime, JsError> {
    date.parse::<DateTime>()
        .map_err(|e| JsError::new(&format!("日期格式不对（{date}）：{e}")))
}

/// 由可选的纬度、经度、高度组成观测地；纬度或经度缺一个时为 None。
fn observer(
    lat_deg: Option<f64>,
    lon_deg: Option<f64>,
    height_m: Option<f64>,
) -> Result<Option<Observer>, JsError> {
    match (lat_deg, lon_deg) {
        (Some(lat), Some(lon)) => Observer::from_degrees(lat, lon, height_m.unwrap_or(0.0))
            .map(Some)
            .map_err(to_js),
        _ => Ok(None),
    }
}

#[wasm_bindgen]
impl Engine {
    /// 用 SPK 星历（如 de440s_1900_2100.bsp）的全部字节创建引擎。
    #[wasm_bindgen(constructor)]
    pub fn new(bytes: Vec<u8>) -> Result<Engine, JsError> {
        let eph = AniseEphemeris::from_vec(bytes).map_err(to_js)?;
        Ok(Engine { eph })
    }

    /// `from_year` 年初到 `to_year` 年初（UTC）之间的月食，JSON 数组（格式见 `guanxiang_view::list`）。
    #[wasm_bindgen(js_name = lunarEclipses)]
    pub fn lunar_eclipses(&self, from_year: i32, to_year: i32) -> Result<String, JsError> {
        let val = list::lunar_eclipses_json(&self.eph, from_year, to_year).map_err(to_js)?;
        Ok(val.to_string())
    }

    /// `from_year` 年初到 `to_year` 年初（UTC）之间的日食，JSON 数组。
    #[wasm_bindgen(js_name = solarEclipses)]
    pub fn solar_eclipses(&self, from_year: i32, to_year: i32) -> Result<String, JsError> {
        let val = list::solar_eclipses_json(&self.eph, from_year, to_year).map_err(to_js)?;
        Ok(val.to_string())
    }

    /// `date`（UTC，如 `2025-09-07` 或 `2025-09-07T18:00`）前后 3 天内食甚最近的月食。
    #[wasm_bindgen(js_name = lunarEclipse)]
    pub fn lunar_eclipse(&self, date: &str) -> Result<LunarEclipseHandle, JsError> {
        let e = guanxiang_view::find_lunar_eclipse(&self.eph, &parse_date(date)?).map_err(to_js)?;
        Ok(LunarEclipseHandle { e })
    }

    /// `date`（UTC）前后 3 天内食甚最近的日食。
    #[wasm_bindgen(js_name = solarEclipse)]
    pub fn solar_eclipse(&self, date: &str) -> Result<SolarEclipseHandle, JsError> {
        let e = guanxiang_view::find_solar_eclipse(&self.eph, &parse_date(date)?).map_err(to_js)?;
        Ok(SolarEclipseHandle { e })
    }
}

/// 选定的一次月食。逐帧求值不必每次重新搜索。
#[wasm_bindgen]
pub struct LunarEclipseHandle {
    e: LunarEclipse,
}

#[wasm_bindgen]
impl LunarEclipseHandle {
    /// 食甚的 TT 秒数（J2000.0 起算）；`stateAt` 的时间相对于它。
    #[wasm_bindgen(getter, js_name = greatestTt)]
    pub fn greatest_tt(&self) -> f64 {
        self.e.greatest.tt_seconds()
    }

    /// 完整场景（与 `guanxiang scene lunar-eclipse` 相同），轨迹每 `step_s` 秒一个点。
    pub fn scene(
        &self,
        engine: &Engine,
        lat_deg: Option<f64>,
        lon_deg: Option<f64>,
        height_m: Option<f64>,
        step_s: f64,
    ) -> Result<String, JsError> {
        let obs = observer(lat_deg, lon_deg, height_m)?;
        let val = scene::lunar_eclipse_scene(&engine.eph, &self.e, obs.as_ref(), step_s)
            .map_err(to_js)?;
        Ok(val.to_string())
    }

    /// 食甚后 `t_rel_s` 秒（TT，之前为负）的状态（格式见 `guanxiang_view::state::lunar_state_json`）。
    #[wasm_bindgen(js_name = stateAt)]
    pub fn state_at(
        &self,
        engine: &Engine,
        t_rel_s: f64,
        lat_deg: Option<f64>,
        lon_deg: Option<f64>,
        height_m: Option<f64>,
    ) -> Result<String, JsError> {
        let obs = observer(lat_deg, lon_deg, height_m)?;
        let val =
            state::lunar_state_json(&engine.eph, &self.e, t_rel_s, obs.as_ref()).map_err(to_js)?;
        Ok(val.to_string())
    }
}

/// 选定的一次日食。
#[wasm_bindgen]
pub struct SolarEclipseHandle {
    e: SolarEclipse,
}

#[wasm_bindgen]
impl SolarEclipseHandle {
    /// 食甚的 TT 秒数（J2000.0 起算）；`stateAt` 的时间相对于它。
    #[wasm_bindgen(getter, js_name = greatestTt)]
    pub fn greatest_tt(&self) -> f64 {
        self.e.greatest.tt_seconds()
    }

    /// 完整场景（与 `guanxiang scene solar-eclipse` 相同），轨迹和中心线每 `step_s` 秒一个点。
    pub fn scene(
        &self,
        engine: &Engine,
        lat_deg: Option<f64>,
        lon_deg: Option<f64>,
        height_m: Option<f64>,
        step_s: f64,
    ) -> Result<String, JsError> {
        let obs = observer(lat_deg, lon_deg, height_m)?;
        let val = scene::solar_eclipse_scene(&engine.eph, &self.e, obs.as_ref(), step_s)
            .map_err(to_js)?;
        Ok(val.to_string())
    }

    /// 食甚后 `t_rel_s` 秒（TT）的状态（格式见 `guanxiang_view::state::solar_state_json`）。
    #[wasm_bindgen(js_name = stateAt)]
    pub fn state_at(
        &self,
        engine: &Engine,
        t_rel_s: f64,
        lat_deg: Option<f64>,
        lon_deg: Option<f64>,
        height_m: Option<f64>,
    ) -> Result<String, JsError> {
        let obs = observer(lat_deg, lon_deg, height_m)?;
        let val =
            state::solar_state_json(&engine.eph, &self.e, t_rel_s, obs.as_ref()).map_err(to_js)?;
        Ok(val.to_string())
    }
}

#[cfg(test)]
mod tests {
    use guanxiang_core::AniseEphemeris;
    use guanxiang_view::{list, scene, state};
    use std::path::PathBuf;

    /// 设置 `GUANXIANG_DUMP=<目录>` 时，把本机算出的结果写成 JSON，供 Node 里的 wasm 结果逐项比对。
    /// 用 `from_vec` 加载星历（和浏览器里同一条路径）。
    #[test]
    fn dump_for_wasm_check() {
        let Some(dir) = std::env::var_os("GUANXIANG_DUMP").map(PathBuf::from) else {
            return;
        };
        let path = std::env::var_os("GUANXIANG_EPHEM").expect("比对需要 GUANXIANG_EPHEM");
        let eph = AniseEphemeris::from_vec(std::fs::read(path).unwrap()).unwrap();
        let write = |name: &str, v: serde_json::Value| {
            std::fs::write(dir.join(name), v.to_string()).unwrap();
        };
        write(
            "lunar_list.json",
            list::lunar_eclipses_json(&eph, 2025, 2035).unwrap(),
        );
        write(
            "solar_list.json",
            list::solar_eclipses_json(&eph, 2025, 2035).unwrap(),
        );

        let obs = guanxiang_core::Observer::from_degrees(39.9, 116.4, 50.0).unwrap();
        let le = guanxiang_view::find_lunar_eclipse(&eph, &"2025-09-07".parse().unwrap()).unwrap();
        write(
            "lunar_scene.json",
            scene::lunar_eclipse_scene(&eph, &le, Some(&obs), 60.0).unwrap(),
        );
        let frames: Vec<_> = (-120..=120)
            .map(|i| state::lunar_state_json(&eph, &le, i as f64 * 60.0, Some(&obs)).unwrap())
            .collect();
        write("lunar_states.json", serde_json::Value::Array(frames));

        let obs = guanxiang_core::Observer::from_degrees(25.687, 32.640, 80.0).unwrap();
        let se = guanxiang_view::find_solar_eclipse(&eph, &"2027-08-02".parse().unwrap()).unwrap();
        write(
            "solar_scene.json",
            scene::solar_eclipse_scene(&eph, &se, Some(&obs), 60.0).unwrap(),
        );
        let frames: Vec<_> = (-120..=120)
            .map(|i| state::solar_state_json(&eph, &se, i as f64 * 60.0, Some(&obs)).unwrap())
            .collect();
        write("solar_states.json", serde_json::Value::Array(frames));
    }
}
