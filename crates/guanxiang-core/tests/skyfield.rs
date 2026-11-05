//! 与 Skyfield（IAU 2006 岁差 + IAU 2000A 章动，同一份 de440s）对比，M1 视位置验收。
//!
//! 对照数据由 `tools/skyfield/gen_fixtures.py` 生成。站心样本使用 Skyfield 记录的 ΔT，
//! 以排除 ΔT 模型的差异；两边都不含极移。

mod common;

use common::*;
use guanxiang_core::astrometry;
use guanxiang_core::{Body, Observer, Time};

#[test]
fn geocentric_apparent_matches_skyfield() {
    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "geocentric.csv");
    assert!(rows.len() >= 100, "M1 要求至少 100 个采样点");

    let mut table = MaxTable::new(&["视位置″", "距离km"]);
    for r in &rows {
        let body: Body = r[0].parse().unwrap();
        let p = astrometry::geocentric(&eph, body, &Time::from_tt_jd(num(&r[1]))).unwrap();
        table.add(
            &r[0],
            &[
                sep_arcsec(
                    p.apparent.ra.to_degrees(),
                    p.apparent.dec.to_degrees(),
                    num(&r[2]),
                    num(&r[3]),
                ),
                p.distance_km - num(&r[4]),
            ],
        );
    }
    table.print("地心视位置，对比 Skyfield（2000–2100）");

    // M1 验收：地心视位置差 ≤ 0.1″
    assert!(
        table.max("视位置″") <= 0.1,
        "视位置差 {:.4}″",
        table.max("视位置″")
    );
    assert!(
        table.max("距离km") <= 0.05,
        "距离差 {:.4} km",
        table.max("距离km")
    );
}

#[test]
fn topocentric_matches_skyfield() {
    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "topocentric.csv");

    let mut table = MaxTable::new(&["视位置″", "方位″", "高度″", "距离km"]);
    for r in &rows {
        let obs = Observer::from_degrees(num(&r[1]), num(&r[2]), num(&r[3])).unwrap();
        let body: Body = r[4].parse().unwrap();
        let t = Time::from_tt_jd(num(&r[5])).with_delta_t(num(&r[6]));
        let p = astrometry::topocentric(&eph, body, &t, &obs).unwrap();
        let pl = &p.place;
        let alt = num(&r[10]);
        table.add(
            &format!("{}/{}", r[0], r[4]),
            &[
                sep_arcsec(
                    pl.apparent.ra.to_degrees(),
                    pl.apparent.dec.to_degrees(),
                    num(&r[7]),
                    num(&r[8]),
                ),
                daz_arcsec(p.horizontal.azimuth.to_degrees(), num(&r[9]), alt),
                (p.horizontal.altitude.to_degrees() - alt) * ARCSEC_PER_DEG,
                pl.distance_km - num(&r[11]),
            ],
        );
    }
    table.print("站心，对比 Skyfield（2000–2100，同一 ΔT）");

    assert!(
        table.max("视位置″") <= 0.1,
        "站心视位置差 {:.4}″",
        table.max("视位置″")
    );
    assert!(
        table.max("方位″") <= 0.1,
        "方位角差 {:.4}″",
        table.max("方位″")
    );
    assert!(
        table.max("高度″") <= 0.1,
        "高度角差 {:.4}″",
        table.max("高度″")
    );
    assert!(
        table.max("距离km") <= 0.05,
        "距离差 {:.4} km",
        table.max("距离km")
    );
}

/// 合、冲时刻与 Skyfield 对比（M2 验收：≤ 5 秒），并检查数量一一对应。
#[test]
fn longitude_events_match_skyfield() {
    use guanxiang_core::events::Span;
    use guanxiang_core::events::longitude::{self, Aspect};
    use std::collections::BTreeMap;

    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "longitude_events.csv");

    // (kind, a, b) → Skyfield 时刻（TT 儒略日）
    let mut groups: BTreeMap<(String, String, String), Vec<f64>> = BTreeMap::new();
    for r in &rows {
        groups
            .entry((r[0].clone(), r[1].clone(), r[2].clone()))
            .or_default()
            .push(num(&r[3]));
    }

    let mut table = MaxTable::new(&["时刻差 s"]);
    for ((kind, a, b), expected) in &groups {
        let (a_body, b_body): (Body, Body) = (a.parse().unwrap(), b.parse().unwrap());
        let aspect = if kind == "conjunction" {
            Aspect::Conjunction
        } else {
            Aspect::Opposition
        };
        let (from, to) = if a == "moon" {
            (2_460_310.5, 2_461_771.5)
        } else {
            (2_451_544.5, 2_488_069.5)
        };
        let span = Span::new(Time::from_tt_jd(from), Time::from_tt_jd(to)).unwrap();
        let step = longitude::default_step_days(a_body, b_body);
        let found = longitude::search(&eph, a_body, b_body, aspect, span, step).unwrap();
        let group = format!("{kind} {a}-{b}");
        assert_eq!(found.len(), expected.len(), "{group}：数量不同");
        for (ev, jd) in found.iter().zip(expected) {
            let dt = (ev.time.tt_jd() - jd) * 86_400.0;
            table.add(&group, &[dt]);
        }
    }
    table.print("合、冲时刻，对比 Skyfield");
    assert!(
        table.max("时刻差 s") <= 5.0,
        "时刻差 {:.3} s",
        table.max("时刻差 s")
    );
}

/// 凌甚时刻和最小角距与 Skyfield 对比。
#[test]
fn transits_match_skyfield() {
    use guanxiang_core::events::{Span, transit};

    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "transits.csv");
    let span = Span::new(Time::from_tt_jd(2_451_910.5), Time::from_tt_jd(2_488_434.5)).unwrap(); // 2001–2100
    let mut found = transit::search(&eph, Body::Mercury, span).unwrap();
    found.extend(transit::search(&eph, Body::Venus, span).unwrap());
    assert_eq!(found.len(), rows.len());

    let mut table = MaxTable::new(&["凌甚差 s", "角距差″"]);
    for r in &rows {
        let jd = num(&r[1]);
        let t = found
            .iter()
            .min_by(|x, y| {
                (x.greatest.tt_jd() - jd)
                    .abs()
                    .total_cmp(&(y.greatest.tt_jd() - jd).abs())
            })
            .unwrap();
        table.add(
            &r[0],
            &[
                (t.greatest.tt_jd() - jd) * 86_400.0,
                t.min_separation.to_degrees() * ARCSEC_PER_DEG - num(&r[2]),
            ],
        );
    }
    table.print("凌甚，对比 Skyfield");
    assert!(table.max("凌甚差 s") <= 5.0);
    assert!(table.max("角距差″") <= 0.01);
}

/// 角距极小与 Skyfield 对比：数量一致，时刻差 ≤ 5 秒（实际为毫秒级），角距差 ≤ 0.01″。
#[test]
fn separation_minima_match_skyfield() {
    use guanxiang_core::events::{Span, separation};

    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "separation_minima.csv");
    let span = Span::new(Time::from_tt_jd(2_460_310.5), Time::from_tt_jd(2_461_406.5)).unwrap(); // 2024–2026

    let mut table = MaxTable::new(&["时刻差 s", "角距差″"]);
    for name in ["venus", "saturn"] {
        let b: Body = name.parse().unwrap();
        let expected: Vec<&Vec<String>> = rows.iter().filter(|r| r[1] == name).collect();
        let step = separation::default_step_days(Body::Moon, b);
        let found = separation::search(&eph, Body::Moon, b, span, step, 5f64.to_radians()).unwrap();
        assert_eq!(found.len(), expected.len(), "moon-{name} 数量");
        for (m, r) in found.iter().zip(&expected) {
            table.add(
                &format!("moon-{name}"),
                &[
                    (m.time.tt_jd() - num(&r[2])) * 86_400.0,
                    (m.separation.to_degrees() - num(&r[3])) * ARCSEC_PER_DEG,
                ],
            );
        }
    }
    table.print("角距极小，对比 Skyfield");
    assert!(table.max("时刻差 s") <= 5.0);
    assert!(table.max("角距差″") <= 0.01);
}
