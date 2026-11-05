//! 与 JPL Horizons 对比。
//!
//! 对照数据由 `tools/horizons/fetch_fixtures.py` 生成。Horizons 用 DE441，本库用 DE440s。
//!
//! - 天体测量位置（只改正光行时，ICRF）不涉及岁差章动模型，是 M1 星历与光行时的验收依据。
//! - 视位置：Horizons 用 IAU76/80 加 IERS 改正，本库用 IAU 2006/2000A。
//!   EOP 实测期内两者天极一致，只差约 0.05″ 的春分点零点（纯赤经）；Horizons 的 EOP 预报
//!   截止后（2027 年起）其岁差模型误差会逐渐累积，到 2100 年约 0.2″。
//!   视位置的 0.1″ 验收见 `skyfield.rs`。
//! - 地平坐标：Horizons 计入极移，本库忽略极移，方位角差约 0.3″·sec(纬度)。

mod common;

use common::*;
use guanxiang_core::astrometry::{self, AU_KM};
use guanxiang_core::{Body, DateTime, Observer, Time};

/// Horizons 的 EOP 预报截止（2027-01-30），此前为实测或短期预报。
const EOP_END_JD: f64 = 2_461_435.5;

#[test]
fn geocentric_matches_horizons() {
    let Some(eph) = ephemeris() else { return };
    let rows = fixture("horizons", "geocentric.csv");
    assert!(rows.len() >= 100, "M1 要求至少 100 个采样点");

    let mut table = MaxTable::new(&["测量″", "视位置″", "EOP内Δδ″", "EOP内Δα″", "距离km"]);
    for r in &rows {
        let body: Body = r[0].parse().unwrap();
        let jd = num(&r[1]);
        let p = astrometry::geocentric(&eph, body, &Time::from_tt_jd(jd)).unwrap();
        let (ra, dec) = (p.apparent.ra.to_degrees(), p.apparent.dec.to_degrees());
        let in_eop = jd < EOP_END_JD;
        table.add(
            &r[0],
            &[
                sep_arcsec(
                    p.astrometric.ra.to_degrees(),
                    p.astrometric.dec.to_degrees(),
                    num(&r[2]),
                    num(&r[3]),
                ),
                sep_arcsec(ra, dec, num(&r[4]), num(&r[5])),
                if in_eop {
                    (dec - num(&r[5])) * ARCSEC_PER_DEG
                } else {
                    0.0
                },
                if in_eop {
                    dra_arcsec(ra, num(&r[4]), dec)
                } else {
                    0.0
                },
                p.distance_km - num(&r[6]) * AU_KM,
            ],
        );
    }
    table.print("地心，对比 Horizons（2000–2100）");

    // 星历 + 光行时：M1 验收（≤ 0.1″），实际在 0.01″ 以内
    assert!(
        table.max("测量″") <= 0.01,
        "天体测量位置差 {:.4}″",
        table.max("测量″")
    );
    assert!(
        table.max("距离km") <= 0.05,
        "距离差 {:.4} km",
        table.max("距离km")
    );
    // 视位置：EOP 实测期内天极一致，赤经只差春分点零点
    assert!(
        table.max("EOP内Δδ″") <= 0.005,
        "EOP 期内赤纬差 {:.4}″",
        table.max("EOP内Δδ″")
    );
    assert!(
        table.max("EOP内Δα″") <= 0.06,
        "EOP 期内赤经差 {:.4}″",
        table.max("EOP内Δα″")
    );
    // 全时段：受 Horizons 岁差章动模型限制
    assert!(
        table.max("视位置″") <= 0.25,
        "视位置差 {:.4}″",
        table.max("视位置″")
    );
}

#[test]
fn topocentric_matches_horizons() {
    let Some(eph) = ephemeris() else { return };
    let rows = fixture("horizons", "topocentric.csv");

    let mut table = MaxTable::new(&["测量″", "Δδ″", "Δα″", "方位″", "高度″", "距离km"]);
    let mut az_limit = Vec::new();
    for r in &rows {
        let obs = Observer::from_degrees(num(&r[1]), num(&r[2]), num(&r[3])).unwrap();
        let body: Body = r[4].parse().unwrap();
        let utc: DateTime = r[5].parse().unwrap();
        let t = Time::from_utc(&utc).unwrap();
        let p = astrometry::topocentric(&eph, body, &t, &obs).unwrap();
        let pl = &p.place;
        let (ra, dec) = (pl.apparent.ra.to_degrees(), pl.apparent.dec.to_degrees());
        let alt = num(&r[11]);
        let group = format!("{}/{}", r[0], r[4]);
        table.add(
            &group,
            &[
                sep_arcsec(
                    pl.astrometric.ra.to_degrees(),
                    pl.astrometric.dec.to_degrees(),
                    num(&r[6]),
                    num(&r[7]),
                ),
                (dec - num(&r[9])) * ARCSEC_PER_DEG,
                dra_arcsec(ra, num(&r[8]), dec),
                daz_arcsec(p.horizontal.azimuth.to_degrees(), num(&r[10]), alt),
                (p.horizontal.altitude.to_degrees() - alt) * ARCSEC_PER_DEG,
                pl.distance_km - num(&r[12]) * AU_KM,
            ],
        );
        // 极移（≲ 0.6″）造成的方位角差随 sec(纬度) 放大
        az_limit.push((group, 0.6 / obs.latitude.cos()));
    }
    table.print("站心，对比 Horizons（1975–2026，ΔT 用 IERS 实测表）");

    assert!(
        table.max("测量″") <= 0.02,
        "天体测量位置差 {:.4}″",
        table.max("测量″")
    );
    // 月球对测站位置敏感，极移造成的测站偏移（约 10 m）带来几 mas 的差
    assert!(table.max("Δδ″") <= 0.015, "赤纬差 {:.4}″", table.max("Δδ″"));
    assert!(table.max("Δα″") <= 0.07, "赤经差 {:.4}″", table.max("Δα″"));
    assert!(
        table.max("高度″") <= 0.6,
        "高度角差 {:.4}″",
        table.max("高度″")
    );
    let az = table.column("方位″");
    for (g, vals) in table.groups() {
        let limit = az_limit.iter().find(|(n, _)| n == g).unwrap().1;
        assert!(
            vals[az] <= limit,
            "{g} 方位角差 {:.4}″ > {limit:.2}″",
            vals[az]
        );
    }
    assert!(
        table.max("距离km") <= 0.05,
        "距离差 {:.4} km",
        table.max("距离km")
    );
}
