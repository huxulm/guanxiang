//! M6：卫星与太阳、月球接近的时刻和角距，与 Skyfield 对比。
//!
//! 对照数据由 `tools/skyfield/gen_sat_transits.py` 生成，两边使用同一份 CelesTrak OMM
//! （`tests/fixtures/satellite/omm_iss_css.json`）和同一 ΔT。Skyfield 的卫星方向不含光行时和
//! 周日光行差，本库包含，角距差 < 0.4″、时刻差 < 0.01 秒。
//!
//! 注意 SGP4 必须用 WGS72 常数（与 python-sgp4 默认一致）；sgp4 crate 的 `from_elements` 默认 WGS84，
//! 一周后差到百米级（见 `satellite.rs`）。

mod common;

use std::collections::BTreeMap;
use std::path::PathBuf;

use common::*;
use guanxiang_core::events::Span;
use guanxiang_core::events::sat_transit;
use guanxiang_core::satellite::Satellite;
use guanxiang_core::{Body, Observer};

fn satellites() -> Vec<Satellite> {
    let path =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/satellite/omm_iss_css.json");
    Satellite::from_omm_json(&std::fs::read_to_string(path).unwrap()).unwrap()
}

#[test]
fn approaches_match_skyfield() {
    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "sat_approaches.csv");
    assert!(rows.len() >= 10, "至少 10 个事件");
    let sats = satellites();

    let mut table = MaxTable::new(&["时刻差 s", "角距差″"]);
    let mut missing = Vec::new();
    // (卫星, 测站, 目标) 分组，每组用第一个事件的 ΔT 搜索 7 天（ΔT 在 7 天内变化 < 1 ms）
    let mut groups: BTreeMap<(String, String, String), Vec<&Vec<String>>> = BTreeMap::new();
    for r in &rows {
        groups
            .entry((r[0].clone(), r[1].clone(), r[5].clone()))
            .or_default()
            .push(r);
    }
    for ((norad, site, body), expected) in &groups {
        let sat = sats
            .iter()
            .find(|s| s.norad_id.to_string() == *norad)
            .unwrap();
        let r0 = expected[0];
        let obs = Observer::from_degrees(num(&r0[2]), num(&r0[3]), num(&r0[4])).unwrap();
        let body: Body = body.parse().unwrap();
        let span = Span::new(sat.epoch, sat.epoch.add_seconds(7.0 * 86_400.0)).unwrap();
        let found = sat_transit::search(
            &eph,
            sat,
            &[body],
            span,
            &obs,
            10f64.to_radians(),
            Some(num(&r0[8])),
        )
        .unwrap();
        for r in expected {
            let jd = num(&r[6]);
            match found
                .iter()
                .find(|e| (e.closest.tt_jd() - jd).abs() * 86_400.0 < 5.0)
            {
                Some(e) => table.add(
                    &format!("{norad}/{site}/{body}"),
                    &[
                        (e.closest.tt_jd() - jd) * 86_400.0,
                        (e.min_separation.to_degrees() - num(&r[7])) * ARCSEC_PER_DEG,
                    ],
                ),
                None => missing.push(format!("{norad}/{site}/{body} JD {jd} 角距 {}°", r[7])),
            }
        }
    }
    table.print(&format!("卫星接近，对比 Skyfield（{} 次）", rows.len()));
    for m in &missing {
        println!("  漏掉：{m}");
    }
    assert!(missing.is_empty());
    // 剩余差异来自本库额外计入的光行时和周日光行差（Skyfield 不计）
    assert!(table.max("时刻差 s") <= 0.02);
    assert!(table.max("角距差″") <= 1.0);
}
