//! 需要 de440s.bsp 的端到端测试。
//!
//! 文件路径取 `GUANXIANG_EPHEM`，否则用仓库根目录的 `data/de440s.bsp`。
//! 文件不存在时跳过（CI 会先下载它）。

use std::path::PathBuf;

use guanxiang_core::{AniseEphemeris, Body, Ephemeris, Tdb};

fn ephemeris() -> Option<AniseEphemeris> {
    let path = std::env::var_os("GUANXIANG_EPHEM")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../data/de440s.bsp"));
    if !path.exists() {
        eprintln!("跳过：找不到 {}", path.display());
        return None;
    }
    Some(AniseEphemeris::from_path(&path).expect("加载 de440s"))
}

/// 第一个端到端测试：J2000 时刻的地月几何距离。
#[test]
fn earth_moon_distance_at_j2000() {
    let Some(eph) = ephemeris() else { return };
    let r = eph.position(Body::Moon, Body::Earth, Tdb::J2000).unwrap();
    let d = r.norm();
    println!("J2000 TDB 地月距离 = {d:.3} km, r = {r:?}");
    // 参考值：402 448.6 km（2000-01-01 12:00 TDB，几何距离，JPL Horizons）
    assert!((d - 402_448.6).abs() < 0.5, "d = {d}");
}

#[test]
fn earth_sun_distance_is_about_one_au() {
    let Some(eph) = ephemeris() else { return };
    let d = eph
        .position(Body::Sun, Body::Earth, Tdb::J2000)
        .unwrap()
        .norm();
    // 1 月初近日点附近，约 0.983 AU
    let au = d / 149_597_870.7;
    assert!((0.98..0.99).contains(&au), "au = {au}");
}

#[test]
fn coverage_includes_1900_2100() {
    let Some(eph) = ephemeris() else { return };
    let (start, end) = eph.coverage(Body::Moon).unwrap();
    assert!(start.to_jd() < 2_415_020.5, "start = {}", start.to_jd()); // 1900-01-01
    assert!(end.to_jd() > 2_488_069.5, "end = {}", end.to_jd()); // 2100-01-01
}

#[test]
fn every_body_is_queryable() {
    let Some(eph) = ephemeris() else { return };
    for b in Body::ALL {
        if b == Body::Earth {
            continue;
        }
        let d = eph.position(b, Body::Earth, Tdb::J2000).unwrap().norm();
        assert!(d.is_finite() && d > 0.0, "{b}: {d}");
    }
}
