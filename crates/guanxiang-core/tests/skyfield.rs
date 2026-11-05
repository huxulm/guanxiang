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
