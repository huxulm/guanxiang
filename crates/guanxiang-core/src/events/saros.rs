//! 沙罗序列。
//!
//! 同一沙罗序列里相邻两次日食（或月食）相隔 223 个朔望月（约 18 年 11 天）。序列表由
//! `tools/nasa/gen_saros_table.py` 从 NASA 日月食沙罗目录生成，只收 1899–2101 年间有食的序列，
//! 与 App 打包的星历范围一致；超出范围时返回 None。

mod table;

use crate::time::Time;

/// 一次日月食在沙罗序列中的位置。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Saros {
    /// 序列号（NASA 编号）
    pub series: u16,
    /// 第几次（从 1 开始）
    pub member: u16,
    /// 序列中的日食（或月食）总数
    pub count: u16,
}

/// Meeus 49.1：k = 0 的平朔（2000-01-06，TT 儒略日）和朔望月平均长度
const JDE0: f64 = 2_451_550.097_66;
const SYNODIC_DAYS: f64 = 29.530_588_861;
/// 一个沙罗周期的朔望月数
const SAROS_LUNATIONS: i32 = 223;

/// 望月所在的朔望月序号，与 NASA 星表的 Luna Num 相同（2000-01-06 的朔为 0）。
/// 真望与平望相差不到一天，取整不会出错。
pub fn full_moon_lunation(t: &Time) -> i32 {
    ((t.tt_jd() - JDE0) / SYNODIC_DAYS - 0.5).round() as i32
}

/// 朔所在的朔望月序号（NASA Luna Num）。
pub fn new_moon_lunation(t: &Time) -> i32 {
    ((t.tt_jd() - JDE0) / SYNODIC_DAYS).round() as i32
}

/// 月食（以食甚时刻表示）所在的沙罗序列。
pub fn lunar_saros(greatest: &Time) -> Option<Saros> {
    find(table::LUNAR, full_moon_lunation(greatest))
}

/// 日食（以食甚时刻表示）所在的沙罗序列。
pub fn solar_saros(greatest: &Time) -> Option<Saros> {
    find(table::SOLAR, new_moon_lunation(greatest))
}

fn find(table: &[(u16, i32, u16)], n: i32) -> Option<Saros> {
    table.iter().find_map(|&(series, first, count)| {
        let d = n - first;
        (d >= 0 && d % SAROS_LUNATIONS == 0 && d / SAROS_LUNATIONS < i32::from(count)).then(|| {
            Saros {
                series,
                member: (d / SAROS_LUNATIONS + 1) as u16,
                count,
            }
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lunation_numbers() {
        // 2001-01-09 20:21:40 TD，NASA Luna Num 12；2025-09-07 18:12:58 TD，317
        assert_eq!(full_moon_lunation(&Time::from_tt_jd(2_451_919.348_38)), 12);
        assert_eq!(full_moon_lunation(&Time::from_tt_jd(2_460_926.259_01)), 317);
    }

    #[test]
    fn saros_128_member_41() {
        let s = lunar_saros(&Time::from_tt_jd(2_460_926.259_01)).unwrap();
        assert_eq!(
            s,
            Saros {
                series: 128,
                member: 41,
                count: 71
            }
        );
    }

    #[test]
    fn saros_136_member_38() {
        // 2027-08-02 10:07:50 TD 日全食，NASA Luna Num 341
        let t = Time::from_tt_jd(2_461_619.922_11);
        assert_eq!(new_moon_lunation(&t), 341);
        assert_eq!(
            solar_saros(&t),
            Some(Saros {
                series: 136,
                member: 38,
                count: 71
            })
        );
    }

    #[test]
    fn tables_have_no_overlaps() {
        // 同一个朔望月不能属于两个序列
        for t in [table::LUNAR, table::SOLAR] {
            let mut seen = std::collections::HashSet::new();
            for &(_, first, count) in t {
                for i in 0..i32::from(count) {
                    assert!(seen.insert(first + SAROS_LUNATIONS * i));
                }
            }
        }
    }
}
