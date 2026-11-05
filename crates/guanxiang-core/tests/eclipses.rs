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
