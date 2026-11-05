//! 恒星（月掩星用的精简星表）。
//!
//! 星表来自 Hipparcos 主星表（V < 6.0，黄纬 |β| < 6.6°），由 `tools/stars/gen_occultation_stars.py` 生成。
//! 自行按线性外推（天球切平面），不计视向速度；对 1900–2100 年月掩星时刻的影响远小于 1 秒。

use crate::geometry::Vec3;
use crate::stars_table::STARS;

/// Hipparcos 历元 J1991.25 的 TT 儒略日。
const HIPPARCOS_EPOCH_JD: f64 = 2_448_349.062_5;
const MAS: f64 = std::f64::consts::PI / 180.0 / 3_600_000.0;

/// 一颗恒星（ICRS，历元 J1991.25）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Star {
    pub hip: u32,
    pub name: Option<&'static str>,
    pub vmag: f32,
    pub ra_deg: f64,
    pub dec_deg: f64,
    pub parallax_mas: f64,
    /// 赤经自行 μα*（含 cos δ），mas/年
    pub pm_ra_mas: f64,
    pub pm_dec_mas: f64,
}

impl Star {
    /// 显示名：中文名或“HIP 编号”。
    pub fn label(&self) -> String {
        match self.name {
            Some(n) => n.to_string(),
            None => format!("HIP {}", self.hip),
        }
    }

    /// `t` 时刻相对太阳系质心的单位方向（ICRS），已加自行。
    pub fn barycentric_direction(&self, t: crate::time::Tdb) -> Vec3 {
        let years = (t.to_jd() - HIPPARCOS_EPOCH_JD) / 365.25;
        let (ra, dec) = (self.ra_deg.to_radians(), self.dec_deg.to_radians());
        let (sr, cr) = ra.sin_cos();
        let (sd, cd) = dec.sin_cos();
        let u = Vec3::new(cd * cr, cd * sr, sd);
        // 切平面上指向东、北的单位向量
        let east = Vec3::new(-sr, cr, 0.0);
        let north = Vec3::new(-sd * cr, -sd * sr, cd);
        let shift = east * (self.pm_ra_mas * MAS * years) + north * (self.pm_dec_mas * MAS * years);
        (u + shift).unit()
    }

    /// 距离（km）。视差无效时视为无穷远（返回 None）。
    pub fn distance_km(&self) -> Option<f64> {
        (self.parallax_mas > 0.0).then(|| crate::astrometry::AU_KM / (self.parallax_mas * MAS))
    }
}

/// 精简星表。
pub fn catalog() -> &'static [Star] {
    &STARS
}

/// 按 HIP 编号或中文名查找。
pub fn find(key: &str) -> Option<&'static Star> {
    let key = key.trim();
    let hip = key
        .trim_start_matches(|c: char| c.is_ascii_alphabetic() || c.is_whitespace())
        .parse::<u32>()
        .ok();
    STARS
        .iter()
        .find(|s| Some(s.hip) == hip || s.name == Some(key))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::time::Tdb;

    #[test]
    fn lookup() {
        assert_eq!(find("毕宿五").unwrap().hip, 21421);
        assert_eq!(find("HIP 65474").unwrap().name, Some("角宿一"));
        assert_eq!(find("80763").unwrap().name, Some("心宿二"));
        assert!(find("HIP 1").is_none());
        assert!(catalog().len() > 500);
    }

    #[test]
    fn proper_motion() {
        // 毕宿五自行约 0.2″/年：35 年约 7″
        let s = find("毕宿五").unwrap();
        let a = s.barycentric_direction(Tdb::from_jd(HIPPARCOS_EPOCH_JD));
        let b = s.barycentric_direction(Tdb::from_jd(HIPPARCOS_EPOCH_JD + 35.0 * 365.25));
        let moved = a.angle_to(b).to_degrees() * 3600.0;
        let expect = (s.pm_ra_mas.hypot(s.pm_dec_mas)) * 35.0 / 1000.0;
        assert!((moved - expect).abs() < 0.01, "{moved} vs {expect}");
    }
}
