//! 星历接口（D1、D2）。
//!
//! [`Ephemeris`] 只返回几何位置（不含光行时、光行差），坐标轴为 ICRF，单位 km。
//! 视位置的修正在 M1 由本库自己完成，不依赖 anise 的 aberration 选项，
//! 这样换后端时结果一致。

use std::path::Path;

use anise::almanac::Almanac;
use anise::constants::orientations::ICRS;
use anise::prelude::Frame;
use anise::time::Epoch;

use crate::body::Body;
use crate::error::{Error, Result};
use crate::geometry::Vec3;
use crate::time::Tdb;

/// 星历后端。实现必须是线程安全的，以便搜索时并行查询。
pub trait Ephemeris: Send + Sync {
    /// `target` 相对 `center` 的几何位置，ICRF 轴，km。
    fn position(&self, target: Body, center: Body, t: Tdb) -> Result<Vec3>;

    /// `target` 相对 `center` 的几何位置和速度（km、km/s）。
    fn state(&self, target: Body, center: Body, t: Tdb) -> Result<(Vec3, Vec3)>;
}

/// 基于 anise 的 SPK 星历（读取 de440s.bsp 等）。
#[derive(Clone)]
pub struct AniseEphemeris {
    almanac: Almanac,
}

impl AniseEphemeris {
    /// 从文件加载 SPK。
    pub fn from_path(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        let path_str = path.to_str().ok_or_else(|| {
            Error::EphemerisLoad(format!("路径不是合法 UTF-8：{}", path.display()))
        })?;
        let almanac = Almanac::default()
            .load(path_str)
            .map_err(|e| Error::EphemerisLoad(format!("{}：{e}", path.display())))?;
        Ok(Self { almanac })
    }

    /// 从内存加载 SPK（Android 上从 asset 读取后使用）。
    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        let almanac = Almanac::default()
            .load_from_bytes(bytes::BytesMut::from(bytes))
            .map_err(|e| Error::EphemerisLoad(e.to_string()))?;
        Ok(Self { almanac })
    }

    /// 某个天体的星历覆盖范围（TDB）。
    pub fn coverage(&self, body: Body) -> Result<(Tdb, Tdb)> {
        let (start, end) =
            self.almanac
                .spk_domain(body.naif_id())
                .map_err(|e| Error::EphemerisQuery {
                    target: body,
                    center: body,
                    message: e.to_string(),
                })?;
        Ok((Tdb(start.to_et_seconds()), Tdb(end.to_et_seconds())))
    }

    fn translate(&self, target: Body, center: Body, t: Tdb) -> Result<(Vec3, Vec3)> {
        let state = self
            .almanac
            .translate(
                frame(target),
                frame(center),
                Epoch::from_et_seconds(t.0),
                None,
            )
            .map_err(|e| Error::EphemerisQuery {
                target,
                center,
                message: e.to_string(),
            })?;
        let r = state.radius_km;
        let v = state.velocity_km_s;
        Ok((Vec3::new(r[0], r[1], r[2]), Vec3::new(v[0], v[1], v[2])))
    }
}

impl Ephemeris for AniseEphemeris {
    fn position(&self, target: Body, center: Body, t: Tdb) -> Result<Vec3> {
        self.translate(target, center, t).map(|(r, _)| r)
    }

    fn state(&self, target: Body, center: Body, t: Tdb) -> Result<(Vec3, Vec3)> {
        self.translate(target, center, t)
    }
}

const fn frame(body: Body) -> Frame {
    Frame::new(body.naif_id(), ICRS)
}
