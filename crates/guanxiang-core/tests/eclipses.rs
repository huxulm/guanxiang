//! M4 验收：21 世纪日月食与 NASA 五千年星表（Espenak & Meeus）对比。
//!
//! 对照数据由 `tools/nasa/parse_catalog.py` 生成。NASA 用 VSOP87/ELP-2000-82，本库用 DE440s，
//! 食甚时刻（TD）的秒级差异来自星历和模型差异，与 ΔT 无关（地心几何只依赖 TT）。

mod common;

use common::*;
use guanxiang_core::events::Span;
use guanxiang_core::events::lunar_eclipse::{self, LunarEclipseKind, ShadowModel};
use guanxiang_core::events::solar_eclipse::{self, SolarEclipseKind};
use guanxiang_core::{DateTime, Time};

fn tt(date: &str, time: &str) -> Time {
    // NASA 的时刻是 TD（= TT）；借用 UTC 解析器得到日历日期，再按 TT 构造
    let d: DateTime = format!("{date}T{time}").parse().unwrap();
    let (a, b) = sofars::cal::cal2jd(d.year, d.month as i32, d.day as i32).unwrap();
    let frac = (f64::from(d.hour) * 3600.0 + f64::from(d.minute) * 60.0 + d.second) / 86_400.0;
    Time::from_tt_jd(a + b + frac)
}

fn century21() -> Span {
    Span::new(Time::from_tt_jd(2_451_910.5), Time::from_tt_jd(2_488_434.5)).unwrap()
}

fn lunar_kind(code: &str) -> LunarEclipseKind {
    match &code[..1] {
        "N" => LunarEclipseKind::Penumbral,
        "P" => LunarEclipseKind::Partial,
        "T" => LunarEclipseKind::Total,
        other => panic!("未知月食类型 {other}"),
    }
}

fn check_lunar(model: ShadowModel) -> (usize, Vec<String>, MaxTable) {
    let eph = ephemeris().unwrap();
    let rows = fixture("nasa", "lunar_2001_2100.csv");
    let found = lunar_eclipse::search(&eph, century21(), model).unwrap();

    let mut table = MaxTable::new(&["食甚差 s", "γ 差", "半影食分差", "本影食分差"]);
    let mut mismatches = Vec::new();
    let mut matched = 0;
    for r in &rows {
        let t = tt(&r[0], &r[1]);
        let Some(e) = found
            .iter()
            .find(|e| (e.greatest.tt_seconds() - t.tt_seconds()).abs() < 3.0 * 3600.0)
        else {
            mismatches.push(format!("{} 漏掉（NASA {}，本影食分 {}）", r[0], r[3], r[6]));
            continue;
        };
        matched += 1;
        if e.kind != lunar_kind(&r[3]) {
            mismatches.push(format!(
                "{} 类型不同：NASA {}（本影 {}、半影 {}），本库 {:?}（本影 {:.4}、半影 {:.4}）",
                r[0], r[3], r[6], r[5], e.kind, e.umbral_magnitude, e.penumbral_magnitude
            ));
        }
        table.add(
            &r[3][..1],
            &[
                e.greatest.tt_seconds() - t.tt_seconds(),
                e.gamma - num(&r[4]),
                e.penumbral_magnitude - num(&r[5]),
                e.umbral_magnitude - num(&r[6]),
            ],
        );
    }
    let extra = found.len() as isize - matched as isize;
    if extra > 0 {
        mismatches.push(format!("本库多出 {extra} 次"));
    }
    (found.len(), mismatches, table)
}

#[test]
fn lunar_eclipses_match_nasa() {
    if ephemeris().is_none() {
        return;
    }
    for model in [ShadowModel::Danjon, ShadowModel::Chauvenet] {
        let (n, mismatches, table) = check_lunar(model);
        table.print(&format!("月食，{model:?} 模型，对比 NASA：本库 {n} 次"));
        for m in &mismatches {
            println!("  {m}");
        }
    }
    let (n, mismatches, table) = check_lunar(ShadowModel::default());
    assert_eq!(n, 228, "21 世纪月食次数");
    assert!(mismatches.is_empty(), "{mismatches:?}");
    assert!(table.max("食甚差 s") <= 10.0);
}

fn solar_kind(code: &str) -> (SolarEclipseKind, bool) {
    // NASA 类型码第二个字符为 + 或 - 表示非中心食
    let central = !matches!(code.chars().nth(1), Some('+') | Some('-'));
    let kind = match &code[..1] {
        "P" => SolarEclipseKind::Partial,
        "A" => SolarEclipseKind::Annular,
        "T" => SolarEclipseKind::Total,
        "H" => SolarEclipseKind::Hybrid,
        other => panic!("未知日食类型 {other}"),
    };
    (kind, central || kind == SolarEclipseKind::Partial)
}

#[test]
fn solar_eclipses_match_nasa() {
    let Some(eph) = ephemeris() else { return };
    let rows = fixture("nasa", "solar_2001_2100.csv");
    let found = solar_eclipse::search(&eph, century21()).unwrap();

    let mut table = MaxTable::new(&["食甚差 s", "γ 差", "食分差"]);
    let mut mismatches = Vec::new();
    for r in &rows {
        let t = tt(&r[0], &r[1]);
        let Some(e) = found
            .iter()
            .find(|e| (e.greatest.tt_seconds() - t.tt_seconds()).abs() < 3.0 * 3600.0)
        else {
            mismatches.push(format!("{} 漏掉（NASA {}）", r[0], r[3]));
            continue;
        };
        let (kind, central) = solar_kind(&r[3]);
        let ours_central = e.central || e.kind == SolarEclipseKind::Partial;
        if e.kind != kind || ours_central != central {
            mismatches.push(format!(
                "{} 类型不同：NASA {}（γ {}，食分 {}），本库 {:?}{}（γ {:.4}，食分 {:.4}）",
                r[0],
                r[3],
                r[4],
                r[5],
                e.kind,
                if e.central { "" } else { "（非中心）" },
                e.gamma,
                e.magnitude
            ));
        }
        table.add(
            &r[3][..1],
            &[
                e.greatest.tt_seconds() - t.tt_seconds(),
                e.gamma - num(&r[4]),
                e.magnitude - num(&r[5]),
            ],
        );
    }
    table.print(&format!("日食，对比 NASA：本库 {} 次", found.len()));
    for m in &mismatches {
        println!("  {m}");
    }
    assert_eq!(found.len(), 224, "21 世纪日食次数");
    assert!(mismatches.is_empty(), "{mismatches:?}");
    assert!(table.max("食甚差 s") <= 10.0);
}

/// 中心食的食甚点、太阳高度、食带宽度与 NASA 对比（用 NASA 的 ΔT；NASA 经纬度取整到 1°）。
#[test]
fn solar_greatest_points_match_nasa() {
    let Some(eph) = ephemeris() else { return };
    let rows = fixture("nasa", "solar_2001_2100.csv");
    let found = solar_eclipse::search(&eph, century21()).unwrap();

    let mut table = MaxTable::new(&["纬度差°", "经度差°", "高度差°", "宽度超差 km"]);
    for r in rows.iter().filter(|r| !r[9].is_empty()) {
        let t = tt(&r[0], &r[1]);
        let e = found
            .iter()
            .find(|e| (e.greatest.tt_seconds() - t.tt_seconds()).abs() < 3.0 * 3600.0)
            .unwrap();
        let p = e
            .greatest_point_with_delta_t(&eph, num(&r[2]))
            .unwrap()
            .unwrap_or_else(|| panic!("{} 应有中心线", r[0]));
        let dlon = solar_eclipse::normalize_longitude_deg(p.longitude_deg - num(&r[7]));
        table.add(
            &r[3][..1],
            &[
                p.latitude_deg - num(&r[6]),
                dlon * num(&r[6]).to_radians().cos(),
                p.sun_altitude_deg - num(&r[8]),
                // 超出“1% + 1 km（NASA 取整）”的部分
                ((p.path_width_km - num(&r[9])).abs() - 0.01 * num(&r[9]) - 1.0).max(0.0),
            ],
        );
    }
    table.print("中心食食甚点，对比 NASA（NASA 经纬度、高度取整到 1°，宽度取整到 1 km）");
    assert!(table.max("纬度差°") <= 0.6);
    assert!(table.max("经度差°") <= 0.6);
    assert!(table.max("高度差°") <= 1.0);
    assert!(table.max("宽度超差 km") <= 0.0, "食带宽度差超过 1% + 1 km");
}

/// 本地情况：在食甚点上，本地类型、食分应与全球结果一致，全食/环食持续时间与 NASA 的
/// “中心持续时间”一致（NASA 取整到 1 秒）。
#[test]
fn local_circumstances_at_greatest_point_match_nasa() {
    use guanxiang_core::Observer;
    use guanxiang_core::events::local_eclipse::{self, LocalSolarKind};

    let Some(eph) = ephemeris() else { return };
    let rows = fixture("nasa", "solar_2001_2100.csv");
    let found = solar_eclipse::search(&eph, century21()).unwrap();

    let mut table = MaxTable::new(&["持续时间差 s", "食分差", "食甚差 s"]);
    for r in rows
        .iter()
        .filter(|r| !r[9].is_empty() && !r[10].is_empty())
    {
        let t = tt(&r[0], &r[1]);
        let dt = num(&r[2]);
        let e = found
            .iter()
            .find(|e| (e.greatest.tt_seconds() - t.tt_seconds()).abs() < 3.0 * 3600.0)
            .unwrap();
        let p = e.greatest_point_with_delta_t(&eph, dt).unwrap().unwrap();
        let obs = Observer::from_degrees(p.latitude_deg, p.longitude_deg, 0.0).unwrap();
        let local = local_eclipse::local_solar(&eph, e, &obs, Some(dt))
            .unwrap()
            .unwrap();
        let expect = if num(&r[5]) >= 1.0 {
            LocalSolarKind::Total
        } else {
            LocalSolarKind::Annular
        };
        assert_eq!(local.kind, expect, "{} 本地类型", r[0]);
        assert!(local.is_visible());
        table.add(
            &r[3][..1],
            &[
                local.central_duration_s().unwrap() - num(&r[10]),
                local.magnitude - e.magnitude,
                local.maximum.tt_seconds() - e.greatest.tt_seconds(),
            ],
        );
    }
    table.print("食甚点的本地情况，对比 NASA 中心持续时间");
    assert!(table.max("持续时间差 s") <= 2.0);
    assert!(table.max("食分差") <= 0.001);
}

/// 示意图数据的几何自洽：月心到影轴的距离在食甚等于搜索得到的 γ 角距，
/// 在各接触时刻等于影子半径 ± 月球半径；日食影轴在食甚离地心 |γ|，轨迹两端在半影之外。
#[test]
fn eclipse_diagrams_are_consistent() {
    let Some(eph) = ephemeris() else { return };
    // 2025-09-07 月全食、2027-08-02 日全食
    let span = Span::new(Time::from_tt_jd(2_460_920.5), Time::from_tt_jd(2_461_660.5)).unwrap();

    let lunar = lunar_eclipse::search(&eph, span, ShadowModel::Danjon).unwrap();
    let total = lunar
        .iter()
        .find(|e| e.kind == LunarEclipseKind::Total)
        .expect("2025-09-07 月全食");
    let d = lunar_eclipse::diagram(&eph, total, ShadowModel::Danjon, 300.0).unwrap();
    let r = |p: &lunar_eclipse::ShadowPoint| p.x_deg.hypot(p.y_deg);
    // γ（地球半径）→ 角距：只检查量级一致，精确值由接触点检查
    assert!(
        r(&d.greatest) < d.umbra_deg - d.moon_semidiameter_deg,
        "全食时月球整个在本影里"
    );
    let expect = [
        d.penumbra_deg + d.moon_semidiameter_deg,
        d.umbra_deg + d.moon_semidiameter_deg,
        d.umbra_deg - d.moon_semidiameter_deg,
        d.umbra_deg - d.moon_semidiameter_deg,
        d.umbra_deg + d.moon_semidiameter_deg,
        d.penumbra_deg + d.moon_semidiameter_deg,
    ];
    for (i, c) in d.contacts.iter().enumerate() {
        let c = c.as_ref().unwrap();
        // 影子半径在几小时内变化很小，用食甚时的值，容差 0.002°（约 7″）
        assert!(
            (r(c) - expect[i]).abs() < 0.002,
            "接触 {i}：{:.4}° vs {:.4}°",
            r(c),
            expect[i]
        );
    }
    // 月球自西向东穿过地影：x 递增
    assert!(d.path.first().unwrap().x_deg < d.path.last().unwrap().x_deg);
    println!(
        "月全食示意图：{} 个点，半影 {:.3}°，本影 {:.3}°，月球 {:.3}°",
        d.path.len(),
        d.penumbra_deg,
        d.umbra_deg,
        d.moon_semidiameter_deg
    );

    let solar = solar_eclipse::search(&eph, span).unwrap();
    let e = solar
        .iter()
        .find(|e| e.kind == SolarEclipseKind::Total)
        .expect("2027-08-02 日全食");
    let s = e.diagram(&eph, 300.0).unwrap();
    let g = s.greatest.x.hypot(s.greatest.y);
    assert!((g - e.gamma.abs()).abs() < 1e-3, "{g} vs {}", e.gamma);
    assert!(s.l2 < 0.0, "全食的本影半径为负");
    for p in [s.track.first().unwrap(), s.track.last().unwrap()] {
        assert!(p.x.hypot(p.y) > 1.0 + s.l1 - 0.02);
    }
    // 影子自西向东扫过：x 递增
    assert!(s.track.first().unwrap().x < s.track.last().unwrap().x);
    println!(
        "日全食示意图：{} 个点，γ {:.4}，l1 {:.4}，l2 {:.4}",
        s.track.len(),
        e.gamma,
        s.l1,
        s.l2
    );
}

#[test]
fn lunar_saros_and_durations_match_nasa() {
    use guanxiang_core::events::saros;

    let Some(eph) = ephemeris() else { return };
    let rows = fixture("nasa", "lunar_2001_2100.csv");
    let found = lunar_eclipse::search(&eph, century21(), ShadowModel::Danjon).unwrap();

    let mut table = MaxTable::new(&["半影食 min", "本影食 min", "全食 min"]);
    for r in &rows {
        let t = tt(&r[0], &r[1]);
        let e = found
            .iter()
            .find(|e| (e.greatest.tt_seconds() - t.tt_seconds()).abs() < 3.0 * 3600.0)
            .unwrap();
        assert_eq!(
            saros::full_moon_lunation(&e.greatest),
            num(&r[7]) as i32,
            "{}",
            r[0]
        );
        let s = saros::lunar_saros(&e.greatest).unwrap_or_else(|| panic!("{} 没有沙罗序列", r[0]));
        assert_eq!(f64::from(s.series), num(&r[8]), "{}", r[0]);

        // 持续时间（分钟）：P1–P4、U1–U4、U2–U3；NASA 没有的留空
        let span = |a: usize, b: usize| match (e.contacts[a], e.contacts[b]) {
            (Some(x), Some(y)) => Some((y.tt_seconds() - x.tt_seconds()) / 60.0),
            _ => None,
        };
        let mut diffs = [0.0; 3];
        for (i, (ours, nasa)) in [span(0, 5), span(1, 4), span(2, 3)]
            .into_iter()
            .zip(&r[9..12])
            .enumerate()
        {
            match (ours, nasa.is_empty()) {
                (Some(m), false) => diffs[i] = m - num(nasa),
                (None, true) => {}
                _ => panic!(
                    "{} 第 {i} 段持续时间有无不一致：本库 {ours:?}，NASA {nasa:?}",
                    r[0]
                ),
            }
        }
        table.add(&r[3][..1], &diffs);
    }
    table.print("月食持续时间，对比 NASA（Danjon）");
    // NASA 的持续时间保留 0.1 分钟；全食很短时接触角度掠射，时刻对模型差异更敏感（最大约 0.33 分钟）
    for c in ["半影食 min", "本影食 min", "全食 min"] {
        assert!(table.max(c) <= 0.5, "{c}");
    }
}

#[test]
fn solar_saros_matches_nasa() {
    use guanxiang_core::events::saros;

    let Some(eph) = ephemeris() else { return };
    let rows = fixture("nasa", "solar_2001_2100.csv");
    let found = solar_eclipse::search(&eph, century21()).unwrap();
    for r in &rows {
        let t = tt(&r[0], &r[1]);
        let e = found
            .iter()
            .find(|e| (e.greatest.tt_seconds() - t.tt_seconds()).abs() < 3.0 * 3600.0)
            .unwrap();
        assert_eq!(
            saros::new_moon_lunation(&e.greatest),
            num(&r[11]) as i32,
            "{}",
            r[0]
        );
        let s = saros::solar_saros(&e.greatest).unwrap_or_else(|| panic!("{} 没有沙罗序列", r[0]));
        assert_eq!(f64::from(s.series), num(&r[12]), "{}", r[0]);
    }
}

/// 全球最大食分栅格（贝塞尔根数）与本地情况（站心视位置，独立算法）对照：2027-08-02 日全食。
#[test]
fn magnitude_grid_matches_local_circumstances() {
    use guanxiang_core::Observer;
    use guanxiang_core::events::local_eclipse;

    let Some(eph) = ephemeris() else { return };
    let span = Span::new(Time::from_tt_jd(2_461_619.0), Time::from_tt_jd(2_461_621.0)).unwrap();
    let e = &solar_eclipse::search(&eph, span).unwrap()[0];

    let mut table = MaxTable::new(&["食分差"]);
    for (name, lat, lon) in [
        ("madrid", 40.4168, -3.7038),
        ("london", 51.5074, -0.1278),
        ("cairo", 30.0444, 31.2357),
        ("athens", 37.9838, 23.7275),
        ("nairobi", -1.2921, 36.8219),
    ] {
        let obs = Observer::from_degrees(lat, lon, 0.0).unwrap();
        let local = local_eclipse::local_solar(&eph, e, &obs, None)
            .unwrap()
            .unwrap_or_else(|| panic!("{name} 应能看到偏食"));
        assert_eq!(local.kind, local_eclipse::LocalSolarKind::Partial, "{name}");
        let ours = e.max_magnitude_at(&eph, lat, lon, 20.0).unwrap();
        println!("{name}: 栅格 {ours:.4}，本地 {:.4}", local.magnitude);
        table.add(name, &[ours - local.magnitude]);
    }
    table.print("最大食分，贝塞尔根数对比站心计算（2027-08-02）");
    assert!(table.max("食分差") <= 0.002);

    // 北京看不到；中心线上的食甚点食分 > 1
    assert_eq!(e.max_magnitude_at(&eph, 39.9, 116.4, 60.0).unwrap(), 0.0);
    let g = e.greatest_point.unwrap();
    assert!(
        e.max_magnitude_at(&eph, g.latitude_deg, g.longitude_deg, 20.0)
            .unwrap()
            > 1.0
    );

    let started = std::time::Instant::now();
    let grid = e.max_magnitude_grid(&eph, 2.0, 120.0).unwrap();
    println!("2° 栅格用时 {:?}", started.elapsed());
    assert_eq!((grid.rows, grid.cols), (90, 180));
    assert!(grid.values.iter().all(|v| (0.0..1.2).contains(v)));
    let lit = grid.values.iter().filter(|v| **v > 0.0).count();
    // 偏食区约占地球表面的三分之一左右
    assert!(lit > 2000 && lit < 9000, "{lit}");
}

/// 日食模拟用的日月圆面：本地食甚时的食面积与 local_solar 一致，C1、C4 时两圆外切，
/// 全食时月面盖住日面。
#[test]
fn solar_disk_views_are_consistent() {
    use guanxiang_core::Observer;
    use guanxiang_core::events::local_eclipse;

    let Some(eph) = ephemeris() else { return };
    let span = Span::new(Time::from_tt_jd(2_461_619.0), Time::from_tt_jd(2_461_621.0)).unwrap();
    let e = &solar_eclipse::search(&eph, span).unwrap()[0];
    for (name, lat, lon) in [("madrid", 40.4168, -3.7038), ("luxor", 25.6872, 32.6396)] {
        let obs = Observer::from_degrees(lat, lon, 0.0).unwrap();
        let l = local_eclipse::local_solar(&eph, e, &obs, None)
            .unwrap()
            .unwrap();
        let c = l.contacts;
        let times = [c[0].unwrap(), l.maximum, c[3].unwrap()];
        let v = local_eclipse::solar_disk_views(&eph, &obs, &times).unwrap();
        let gap = |d: &local_eclipse::SolarDiskView| {
            (d.x.hypot(d.y) - d.sun_radius - d.moon_radius).to_degrees() * 3600.0
        };
        assert!(gap(&v[0]).abs() < 0.05, "{name} C1 {}″", gap(&v[0]));
        assert!(gap(&v[2]).abs() < 0.05, "{name} C4 {}″", gap(&v[2]));
        assert!((v[1].obscuration - l.obscuration).abs() < 1e-6, "{name}");
        assert!(
            (v[1].sun_altitude_deg - l.sun_altitude_deg[1]).abs() < 1e-6,
            "{name}"
        );
        // 天顶位置角在 (−π, π]
        assert!(
            v.iter()
                .all(|d| d.zenith_angle.abs() <= std::f64::consts::PI)
        );
    }
}
