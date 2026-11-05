//! M5 验收：月掩星时刻与 Skyfield 对比（至少 20 次，掩始、掩终差 ≤ 5 秒）。
//!
//! 对照数据由 `tools/skyfield/gen_occultations.py` 生成，恒星参数与本库相同，
//! 每个事件使用 Skyfield 记录的 ΔT。

mod common;

use std::collections::BTreeMap;

use common::*;
use guanxiang_core::events::Span;
use guanxiang_core::events::occultation::{self, Target};
use guanxiang_core::{Body, Observer, Time, stars};

fn target(name: &str) -> Target {
    match name.strip_prefix("HIP ") {
        Some(_) => Target::Star(stars::find(name).unwrap()),
        None => Target::Planet(name.parse::<Body>().unwrap()),
    }
}

#[test]
fn occultations_match_skyfield() {
    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "occultations.csv");
    assert!(rows.len() >= 20, "M5 要求至少 20 个事件");
    let span = Span::new(Time::from_tt_jd(2_460_310.5), Time::from_tt_jd(2_462_867.5)).unwrap();

    // (测站, 目标) → 行
    let mut groups: BTreeMap<(String, String), Vec<&Vec<String>>> = BTreeMap::new();
    for r in &rows {
        groups
            .entry((r[0].clone(), r[4].clone()))
            .or_default()
            .push(r);
    }

    let mut table = MaxTable::new(&["掩始差 s", "掩终差 s"]);
    let mut count_issues = Vec::new();
    // 所有测站共用一份地心候选
    let mut cand_cache: BTreeMap<String, Vec<occultation::Candidate>> = BTreeMap::new();
    for ((site, name), expected) in &groups {
        let r0 = expected[0];
        let obs = Observer::from_degrees(num(&r0[1]), num(&r0[2]), num(&r0[3])).unwrap();
        let cands = cand_cache
            .entry(name.clone())
            .or_insert_with(|| occultation::candidates(&eph, target(name), span).unwrap());

        // 用本库 ΔT 模型统计次数，应与 Skyfield 一致
        let ours: Vec<_> = cands
            .iter()
            .filter_map(|c| occultation::local(&eph, c, &obs, None).unwrap())
            .collect();
        if ours.len() != expected.len() {
            count_issues.push(format!(
                "{site}/{name}：本库 {} 次，Skyfield {} 次",
                ours.len(),
                expected.len()
            ));
        }

        for r in expected {
            let jd_d = num(&r[5]);
            let c = cands
                .iter()
                .find(|c| (c.time.tt_jd() - jd_d).abs() < 1.0)
                .unwrap_or_else(|| panic!("{site}/{name} 缺少 JD {jd_d} 附近的候选"));
            let o = occultation::local(&eph, c, &obs, Some(num(&r[7])))
                .unwrap()
                .unwrap_or_else(|| panic!("{site}/{name} JD {jd_d}：本库没有掩星"));
            table.add(
                &format!("{site}/{name}"),
                &[
                    (o.disappearance.tt_jd() - jd_d) * 86_400.0,
                    (o.reappearance.tt_jd() - num(&r[6])) * 86_400.0,
                ],
            );
        }
    }
    table.print(&format!("月掩星，对比 Skyfield（{} 次）", rows.len()));
    for m in &count_issues {
        println!("  {m}");
    }
    assert!(table.max("掩始差 s") <= 5.0);
    assert!(table.max("掩终差 s") <= 5.0);
    assert!(count_issues.is_empty(), "{count_issues:?}");
}

/// 全星表批量搜索与逐颗搜索结果一致。
#[test]
fn all_star_candidates_match_single_star() {
    let Some(eph) = ephemeris() else { return };
    let span = Span::new(Time::from_tt_jd(2_460_310.5), Time::from_tt_jd(2_461_406.5)).unwrap();
    let all = occultation::candidates_all_stars(&eph, span).unwrap();
    assert!(
        all.windows(2)
            .all(|w| w[0].time.tt_seconds() <= w[1].time.tt_seconds())
    );
    for key in ["角宿一", "心宿二", "轩辕十四"] {
        let star = stars::find(key).unwrap();
        let single = occultation::candidates(&eph, Target::Star(star), span).unwrap();
        let batch: Vec<_> = all
            .iter()
            .filter(|c| matches!(c.target, Target::Star(s) if s.hip == star.hip))
            .collect();
        assert_eq!(single.len(), batch.len(), "{key}");
        for (a, b) in single.iter().zip(batch) {
            assert!(
                (a.time.tt_seconds() - b.time.tt_seconds()).abs() < 2.0,
                "{key}"
            );
        }
    }
}
