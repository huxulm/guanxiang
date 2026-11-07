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

/// 日月出没、晨昏蒙影：按相同定义（34′ 折射 + 视半径；−6°/−12°/−18°）与 Skyfield 对比。
/// 对照数据由 `tools/skyfield/gen_almanac.py` 生成，使用 Skyfield 的 ΔT。
#[test]
fn rise_set_twilight_match_skyfield() {
    use guanxiang_core::events::Span;
    use guanxiang_core::events::almanac::{self, SkyEventKind};

    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "almanac_events.csv");
    assert!(rows.len() > 1000);

    let kind = |s: &str| match s {
        "sunrise" => SkyEventKind::Sunrise,
        "sunset" => SkyEventKind::Sunset,
        "civil_dawn" => SkyEventKind::CivilDawn,
        "civil_dusk" => SkyEventKind::CivilDusk,
        "nautical_dawn" => SkyEventKind::NauticalDawn,
        "nautical_dusk" => SkyEventKind::NauticalDusk,
        "astronomical_dawn" => SkyEventKind::AstronomicalDawn,
        "astronomical_dusk" => SkyEventKind::AstronomicalDusk,
        "moonrise" => SkyEventKind::Moonrise,
        "moonset" => SkyEventKind::Moonset,
        _ => panic!("未知事件 {s}"),
    };

    // 按（地点, 窗口）分组
    let mut windows: Vec<(&[String], Vec<&Vec<String>>)> = Vec::new();
    for r in &rows {
        match windows.last_mut() {
            Some((k, v)) if k[0] == r[0] && k[4] == r[4] => v.push(r),
            _ => windows.push((&r[..], vec![r])),
        }
    }

    let mut table = MaxTable::new(&["时刻差s"]);
    let mut count = 0;
    for (k, expected) in &windows {
        let obs = Observer::from_degrees(num(&k[1]), num(&k[2]), num(&k[3])).unwrap();
        let dt = num(&k[6]);
        let span = Span::new(
            Time::from_tt_jd(num(&k[4])).with_delta_t(dt),
            Time::from_tt_jd(num(&k[5])).with_delta_t(dt),
        )
        .unwrap();
        let found = almanac::rise_set_twilight(&eph, &obs, span, Some(dt)).unwrap();
        for r in expected {
            let jd = num(&r[8]);
            let want = kind(&r[7]);
            let best = found
                .iter()
                .filter(|e| e.kind == want)
                .map(|e| (e.time.tt_jd() - jd) * 86_400.0)
                .min_by(|a, b| a.abs().total_cmp(&b.abs()))
                .unwrap_or_else(|| panic!("{} {} {jd} 没有找到", k[0], r[7]));
            table.add(&format!("{:<10} {}", k[0], r[7]), &[best]);
            count += 1;
        }
        // 不能多出 Skyfield 没有的事件
        assert_eq!(
            found.len(),
            expected.len(),
            "{} 窗口 {}：事件数不同",
            k[0],
            k[4]
        );
    }
    table.print(&format!(
        "日月出没与晨昏，对比 Skyfield（2026 年，{count} 个事件）"
    ));
    assert!(
        table.max("时刻差s") <= 0.1,
        "时刻差 {:.3} s",
        table.max("时刻差s")
    );
}

/// 月相：照亮比例、日月视黄经差与 Skyfield 的 `fraction_illuminated`、`moon_phase` 对比。
#[test]
fn moon_phase_matches_skyfield() {
    use guanxiang_core::events::almanac;

    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "moon_phase.csv");
    let mut table = MaxTable::new(&["照亮比例", "黄经差″"]);
    for r in &rows {
        let p = almanac::moon_phase(&eph, &Time::from_tt_jd(num(&r[0]))).unwrap();
        let mut dl = p.longitude_difference.to_degrees() - num(&r[2]);
        dl -= 360.0 * (dl / 360.0).round();
        table.add("moon", &[p.illuminated_fraction - num(&r[1]), dl * 3600.0]);
    }
    table.print("月相，对比 Skyfield（2026 年）");
    assert!(table.max("照亮比例") <= 1e-4);
    assert!(table.max("黄经差″") <= 0.1);
}

#[test]
fn sublunar_point_matches_skyfield() {
    let Some(eph) = ephemeris() else { return };
    let rows = fixture("skyfield", "sublunar.csv");
    let mut table = MaxTable::new(&["纬度″", "经度×cos纬度″"]);
    for r in &rows {
        let t = Time::from_tt_jd(num(&r[0])).with_delta_t(num(&r[1]));
        let (lat, lon) = astrometry::sub_body_point(&eph, Body::Moon, &t).unwrap();
        assert!(
            lon > -std::f64::consts::PI && lon <= std::f64::consts::PI,
            "{lon}"
        );
        let mut dlon = lon.to_degrees() - num(&r[3]);
        dlon -= 360.0 * (dlon / 360.0).round();
        table.add(
            "moon",
            &[
                (lat.to_degrees() - num(&r[2])) * 3600.0,
                dlon * lat.cos() * 3600.0,
            ],
        );
    }
    table.print("月下点，对比 Skyfield");
    assert!(table.max("纬度″") <= 0.01);
    assert!(table.max("经度×cos纬度″") <= 0.01);
}
