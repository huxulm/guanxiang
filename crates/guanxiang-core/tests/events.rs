//! M2 事件搜索验收：21 世纪凌日次数，以及若干合、冲、角距极小的基本性质。

mod common;

use common::*;
use guanxiang_core::events::longitude::{self, Aspect};
use guanxiang_core::events::{Span, separation, transit};
use guanxiang_core::{Body, DateTime, Time};

fn utc(s: &str) -> Time {
    Time::from_utc(&s.parse::<DateTime>().unwrap()).unwrap()
}

fn century21() -> Span {
    Span::new(utc("2001-01-01"), utc("2101-01-01")).unwrap()
}

/// NASA 凌日星表（Espenak）：21 世纪的凌甚日期（UT）。
const MERCURY_TRANSITS: [&str; 14] = [
    "2003-05-07",
    "2006-11-08",
    "2016-05-09",
    "2019-11-11",
    "2032-11-13",
    "2039-11-07",
    "2049-05-07",
    "2052-11-09",
    "2062-05-10",
    "2065-11-11",
    "2078-11-14",
    "2085-11-07",
    "2095-05-08",
    "2098-11-10",
];
const VENUS_TRANSITS: [&str; 2] = ["2004-06-08", "2012-06-06"];

fn check_transits(planet: Body, expected: &[&str]) {
    let Some(eph) = ephemeris() else { return };
    let found = transit::search(&eph, planet, century21()).unwrap();
    for t in &found {
        let c: Vec<String> = t
            .contacts
            .iter()
            .map(|c| {
                c.map_or("-".into(), |c| {
                    c.to_utc().unwrap().to_string()[11..19].to_string()
                })
            })
            .collect();
        println!(
            "{planet} 凌甚 {}  角距 {:6.1}″  日半径 {:6.1}″  接触 {}",
            t.greatest.to_utc().unwrap(),
            t.min_separation.to_degrees() * 3600.0,
            t.sun_semidiameter.to_degrees() * 3600.0,
            c.join(" ")
        );
    }
    let dates: Vec<String> = found
        .iter()
        .map(|t| t.greatest.to_utc().unwrap().to_string()[..10].to_string())
        .collect();
    assert_eq!(dates, expected, "{planet} 凌日日期");
    // 接触时刻有序
    for t in &found {
        let times: Vec<f64> = t
            .contacts
            .iter()
            .flatten()
            .map(|c| c.tt_seconds())
            .collect();
        assert!(times.windows(2).all(|w| w[0] < w[1]));
        assert!(t.contacts[0].unwrap().tt_seconds() < t.greatest.tt_seconds());
        assert!(t.greatest.tt_seconds() < t.contacts[3].unwrap().tt_seconds());
    }
}

#[test]
fn mercury_transits_21st_century() {
    check_transits(Body::Mercury, &MERCURY_TRANSITS);
}

#[test]
fn venus_transits_21st_century() {
    check_transits(Body::Venus, &VENUS_TRANSITS);
}

#[test]
fn venus_conjunctions_alternate() {
    let Some(eph) = ephemeris() else { return };
    let span = Span::new(utc("2020-01-01"), utc("2030-01-01")).unwrap();
    let evs =
        longitude::search(&eph, Body::Venus, Body::Sun, Aspect::Conjunction, span, 2.0).unwrap();
    // 金星会合周期 584 天：10 年内 12 或 13 次合，上合、下合交替
    assert!((12..=13).contains(&evs.len()), "{}", evs.len());
    let inferior: Vec<bool> = evs
        .iter()
        .map(|e| e.distance_a_km < e.distance_b_km)
        .collect();
    assert!(inferior.windows(2).all(|w| w[0] != w[1]), "{inferior:?}");
    for e in &evs {
        // 合时黄经差为 0，角距等于黄纬差
        assert!((e.separation - e.latitude_difference.abs()).abs() < 1e-6);
    }
}

#[test]
fn mars_oppositions() {
    let Some(eph) = ephemeris() else { return };
    let span = Span::new(utc("2018-01-01"), utc("2028-01-01")).unwrap();
    let evs =
        longitude::search(&eph, Body::Mars, Body::Sun, Aspect::Opposition, span, 2.0).unwrap();
    let dates: Vec<String> = evs
        .iter()
        .map(|e| e.time.to_utc().unwrap().to_string()[..10].to_string())
        .collect();
    // 火星冲日：2018-07-27、2020-10-13、2022-12-08、2025-01-16、2027-02-19
    assert_eq!(
        dates,
        [
            "2018-07-27",
            "2020-10-13",
            "2022-12-08",
            "2025-01-16",
            "2027-02-19"
        ]
    );
}

#[test]
fn moon_jupiter_conjunctions_and_minima() {
    let Some(eph) = ephemeris() else { return };
    let span = Span::new(utc("2026-01-01"), utc("2027-01-01")).unwrap();
    let conj = longitude::search(
        &eph,
        Body::Moon,
        Body::Jupiter,
        Aspect::Conjunction,
        span,
        1.0,
    )
    .unwrap();
    // 一年约 13 次
    assert!((12..=14).contains(&conj.len()), "{}", conj.len());
    let minima = separation::search(
        &eph,
        Body::Moon,
        Body::Jupiter,
        span,
        separation::default_step_days(Body::Moon, Body::Jupiter),
        10f64.to_radians(),
    )
    .unwrap();
    assert_eq!(minima.len(), conj.len());
    for (c, m) in conj.iter().zip(&minima) {
        // 角距极小与黄经合相差不到半天，且不大于合时角距
        assert!((c.time.tt_seconds() - m.time.tt_seconds()).abs() < 43_200.0);
        assert!(m.separation <= c.separation + 1e-9);
    }
}
