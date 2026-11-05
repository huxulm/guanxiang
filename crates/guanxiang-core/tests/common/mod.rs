//! 集成测试的公共工具。
#![allow(dead_code)]

use std::collections::BTreeMap;
use std::path::PathBuf;

use guanxiang_core::AniseEphemeris;

pub const ARCSEC_PER_DEG: f64 = 3600.0;

/// 加载 de440s。路径取 `GUANXIANG_EPHEM`，否则为仓库根目录的 `data/de440s.bsp`；找不到时返回 None（测试跳过）。
pub fn ephemeris() -> Option<AniseEphemeris> {
    let path = std::env::var_os("GUANXIANG_EPHEM")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../data/de440s.bsp"));
    if !path.exists() {
        eprintln!("跳过：找不到 {}", path.display());
        return None;
    }
    Some(AniseEphemeris::from_path(&path).expect("加载 de440s"))
}

/// 读取 `tests/fixtures/<dir>/<name>`，跳过表头和 `#` 注释行。
pub fn fixture(dir: &str, name: &str) -> Vec<Vec<String>> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(dir)
        .join(name);
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    text.lines()
        .filter(|l| !l.trim().is_empty() && !l.starts_with('#'))
        .skip(1)
        .map(|l| l.split(',').map(|c| c.trim().to_string()).collect())
        .collect()
}

pub fn num(s: &str) -> f64 {
    s.parse().unwrap_or_else(|_| panic!("不是数字：{s}"))
}

fn unit(ra_deg: f64, dec_deg: f64) -> [f64; 3] {
    let (ra, dec) = (ra_deg.to_radians(), dec_deg.to_radians());
    [dec.cos() * ra.cos(), dec.cos() * ra.sin(), dec.sin()]
}

/// 两个方向之间的角距（角秒），输入为度。
pub fn sep_arcsec(ra1: f64, dec1: f64, ra2: f64, dec2: f64) -> f64 {
    let (a, b) = (unit(ra1, dec1), unit(ra2, dec2));
    let cross = [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ];
    let c = (cross[0].powi(2) + cross[1].powi(2) + cross[2].powi(2)).sqrt();
    let d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    c.atan2(d).to_degrees() * ARCSEC_PER_DEG
}

/// 赤经差 × cos(赤纬)（角秒），自动处理 0/360 跨越。
pub fn dra_arcsec(ra1: f64, ra2: f64, dec: f64) -> f64 {
    let mut d = (ra1 - ra2).rem_euclid(360.0);
    if d > 180.0 {
        d -= 360.0;
    }
    d * dec.to_radians().cos() * ARCSEC_PER_DEG
}

/// 方位角差换算到天球上的角距（角秒）。
pub fn daz_arcsec(az1: f64, az2: f64, alt: f64) -> f64 {
    dra_arcsec(az1, az2, alt).abs()
}

/// 按分组记录多列误差的最大值，并打印成表。
#[derive(Default)]
pub struct MaxTable {
    columns: Vec<&'static str>,
    rows: BTreeMap<String, (usize, Vec<f64>)>,
}

impl MaxTable {
    pub fn new(columns: &[&'static str]) -> Self {
        Self {
            columns: columns.to_vec(),
            rows: BTreeMap::new(),
        }
    }

    pub fn add(&mut self, group: &str, values: &[f64]) {
        let n = self.columns.len();
        let row = self
            .rows
            .entry(group.to_string())
            .or_insert_with(|| (0, vec![0.0; n]));
        row.0 += 1;
        for (slot, v) in row.1.iter_mut().zip(values) {
            *slot = slot.max(v.abs());
        }
    }

    pub fn print(&self, title: &str) {
        println!("\n{title}");
        print!("{:<18} {:>4}", "分组", "n");
        for c in &self.columns {
            print!(" {c:>12}");
        }
        println!();
        for (g, (n, vals)) in &self.rows {
            print!("{g:<18} {n:>4}");
            for v in vals {
                print!(" {v:>12.5}");
            }
            println!();
        }
    }

    /// 某列在所有分组中的最大值。
    pub fn max(&self, column: &str) -> f64 {
        let i = self
            .columns
            .iter()
            .position(|c| *c == column)
            .expect("列名");
        self.rows.values().map(|(_, v)| v[i]).fold(0.0, f64::max)
    }

    pub fn groups(&self) -> impl Iterator<Item = (&String, &[f64])> {
        self.rows.iter().map(|(g, (_, v))| (g, v.as_slice()))
    }

    pub fn column(&self, column: &str) -> usize {
        self.columns
            .iter()
            .position(|c| *c == column)
            .expect("列名")
    }
}
