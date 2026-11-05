//! 预计算星表的二进制格式（第 8 节“预计算星表格式”的决定）。
//!
//! 选择自定义的定长记录而不是 SQLite：SQLite 需要编译 C 代码（违背 M0 的“无原生依赖”），
//! 而全球事件表只是几千到几万条只读记录，按时间排序后二分查找即可。
//!
//! 布局（小端）：
//!
//! ```text
//! 头部 16 字节：magic "GXEV" | version u16 | record_size u16 | count u32 | reserved u32
//! 记录 48 字节：kind u8 | body_a u8 | body_b u8 | flags u8 | reserved u32 | tt f64 | values [f64; 4]
//! ```
//!
//! `tt` 为 J2000.0 TT 起算的秒数。`values` 的含义由 `kind` 决定，不用的槽位为 NaN。
//! 版本号变化时旧文件拒绝读取，由应用重新下载或重新生成。

use crate::body::Body;
use crate::error::{Error, Result};

const MAGIC: &[u8; 4] = b"GXEV";
pub const VERSION: u16 = 1;
const HEADER_SIZE: usize = 16;
pub const RECORD_SIZE: usize = 48;

/// 事件类型编码。新增类型只能追加，不能改已有编号。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Kind {
    /// values = [角距, 黄纬差, -, -]
    Conjunction = 1,
    /// values = [角距, 黄纬和, -, -]
    Opposition = 2,
    /// values = [角距, -, -, -]
    SeparationMinimum = 3,
    /// tt = 凌甚；values = [接触 I, II, III, IV 的 tt]
    Transit = 4,
}

impl Kind {
    fn from_u8(v: u8) -> Result<Self> {
        Ok(match v {
            1 => Kind::Conjunction,
            2 => Kind::Opposition,
            3 => Kind::SeparationMinimum,
            4 => Kind::Transit,
            _ => return Err(Error::Catalog(format!("未知事件类型 {v}"))),
        })
    }
}

/// 一条记录。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Record {
    pub kind: Kind,
    pub a: Body,
    pub b: Body,
    pub flags: u8,
    pub tt: f64,
    pub values: [f64; 4],
}

fn body_code(b: Body) -> u8 {
    b.naif_id().clamp(0, 255) as u8 // 只用于本库支持的天体
}

fn body_from_code(c: u8) -> Result<Body> {
    // 月球 301、地球 399 超出 u8，单独编码
    match c {
        0 => Ok(Body::SolarSystemBarycenter),
        1 => Ok(Body::Mercury),
        2 => Ok(Body::Venus),
        4 => Ok(Body::Mars),
        5 => Ok(Body::Jupiter),
        6 => Ok(Body::Saturn),
        7 => Ok(Body::Uranus),
        8 => Ok(Body::Neptune),
        10 => Ok(Body::Sun),
        30 => Ok(Body::Moon),
        39 => Ok(Body::Earth),
        _ => Err(Error::Catalog(format!("未知天体编码 {c}"))),
    }
}

fn encode_body(b: Body) -> u8 {
    match b {
        Body::Moon => 30,
        Body::Earth => 39,
        other => body_code(other),
    }
}

/// 编码。记录按 `tt` 排序后写入。
pub fn encode(records: &[Record]) -> Vec<u8> {
    let mut sorted = records.to_vec();
    sorted.sort_by(|x, y| x.tt.total_cmp(&y.tt));
    let mut out = Vec::with_capacity(HEADER_SIZE + RECORD_SIZE * sorted.len());
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&VERSION.to_le_bytes());
    out.extend_from_slice(&(RECORD_SIZE as u16).to_le_bytes());
    out.extend_from_slice(&(sorted.len() as u32).to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    for r in &sorted {
        out.push(r.kind as u8);
        out.push(encode_body(r.a));
        out.push(encode_body(r.b));
        out.push(r.flags);
        out.extend_from_slice(&0u32.to_le_bytes());
        out.extend_from_slice(&r.tt.to_le_bytes());
        for v in r.values {
            out.extend_from_slice(&v.to_le_bytes());
        }
    }
    out
}

/// 解码并校验。
pub fn decode(bytes: &[u8]) -> Result<Vec<Record>> {
    let err = |m: &str| Error::Catalog(m.to_string());
    if bytes.len() < HEADER_SIZE || &bytes[0..4] != MAGIC {
        return Err(err("不是观象星表文件"));
    }
    let u16_at = |i: usize| u16::from_le_bytes([bytes[i], bytes[i + 1]]);
    let u32_at = |i: usize| u32::from_le_bytes(bytes[i..i + 4].try_into().unwrap());
    let f64_at = |i: usize| f64::from_le_bytes(bytes[i..i + 8].try_into().unwrap());

    let version = u16_at(4);
    if version != VERSION {
        return Err(Error::Catalog(format!(
            "星表版本 {version}，本程序只支持 {VERSION}"
        )));
    }
    if usize::from(u16_at(6)) != RECORD_SIZE {
        return Err(err("记录长度不符"));
    }
    let count = u32_at(8) as usize;
    if bytes.len() != HEADER_SIZE + count * RECORD_SIZE {
        return Err(err("文件长度与记录数不符"));
    }
    (0..count)
        .map(|i| {
            let o = HEADER_SIZE + i * RECORD_SIZE;
            Ok(Record {
                kind: Kind::from_u8(bytes[o])?,
                a: body_from_code(bytes[o + 1])?,
                b: body_from_code(bytes[o + 2])?,
                flags: bytes[o + 3],
                tt: f64_at(o + 8),
                values: [
                    f64_at(o + 16),
                    f64_at(o + 24),
                    f64_at(o + 32),
                    f64_at(o + 40),
                ],
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let recs = vec![
            Record {
                kind: Kind::Transit,
                a: Body::Mercury,
                b: Body::Sun,
                flags: 1,
                tt: 6.0e8,
                values: [1.0, f64::NAN, f64::NAN, 4.0],
            },
            Record {
                kind: Kind::Conjunction,
                a: Body::Moon,
                b: Body::Jupiter,
                flags: 0,
                tt: -3.0e8,
                values: [0.01, -0.02, f64::NAN, f64::NAN],
            },
        ];
        let bytes = encode(&recs);
        assert_eq!(bytes.len(), HEADER_SIZE + 2 * RECORD_SIZE);
        let back = decode(&bytes).unwrap();
        // 按时间排序
        assert_eq!(back[0].a, Body::Moon);
        assert_eq!(back[1].kind, Kind::Transit);
        assert_eq!(back[1].values[0], 1.0);
        assert!(back[1].values[1].is_nan());
        for b in Body::ALL {
            assert_eq!(body_from_code(encode_body(b)).unwrap(), b);
        }
    }

    #[test]
    fn rejects_bad_input() {
        assert!(decode(b"nope").is_err());
        let mut bytes = encode(&[]);
        bytes[4] = 99;
        assert!(decode(&bytes).is_err());
        let mut bytes = encode(&[]);
        bytes.push(0);
        assert!(decode(&bytes).is_err());
    }
}
