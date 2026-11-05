//! 地面观测者。

use std::str::FromStr;

use crate::error::{Error, Result};

/// 地面观测者，WGS84 大地坐标。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Observer {
    /// 大地纬度（弧度，北正）
    pub latitude: f64,
    /// 经度（弧度，东正）
    pub longitude: f64,
    /// 椭球高（米）
    pub height: f64,
}

impl Observer {
    pub fn from_degrees(latitude_deg: f64, longitude_deg: f64, height_m: f64) -> Result<Self> {
        if !(-90.0..=90.0).contains(&latitude_deg) {
            return Err(Error::InvalidObserver(format!(
                "纬度 {latitude_deg}° 超出 [-90, 90]"
            )));
        }
        if !(-180.0..=360.0).contains(&longitude_deg) {
            return Err(Error::InvalidObserver(format!(
                "经度 {longitude_deg}° 超出 [-180, 360]"
            )));
        }
        if !(-500.0..=10_000.0).contains(&height_m) {
            return Err(Error::InvalidObserver(format!(
                "高度 {height_m} m 超出 [-500, 10000]"
            )));
        }
        let lon = if longitude_deg > 180.0 {
            longitude_deg - 360.0
        } else {
            longitude_deg
        };
        Ok(Self {
            latitude: latitude_deg.to_radians(),
            longitude: lon.to_radians(),
            height: height_m,
        })
    }

    pub fn latitude_deg(&self) -> f64 {
        self.latitude.to_degrees()
    }

    pub fn longitude_deg(&self) -> f64 {
        self.longitude.to_degrees()
    }
}

impl FromStr for Observer {
    type Err = Error;

    /// `纬度,经度[,高度米]`，单位为度。例如 `43.4711,87.1778,2080`。
    fn from_str(s: &str) -> Result<Self> {
        let bad = || Error::InvalidObserver(format!("应为 纬度,经度[,高度米]：{s}"));
        let parts: Vec<f64> = s
            .split(',')
            .map(|p| p.trim().parse::<f64>().map_err(|_| bad()))
            .collect::<Result<_>>()?;
        match parts[..] {
            [lat, lon] => Observer::from_degrees(lat, lon, 0.0),
            [lat, lon, h] => Observer::from_degrees(lat, lon, h),
            _ => Err(bad()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse() {
        let o: Observer = "43.4711, 87.1778, 2080".parse().unwrap();
        assert!((o.latitude_deg() - 43.4711).abs() < 1e-12);
        assert!((o.longitude_deg() - 87.1778).abs() < 1e-12);
        assert_eq!(o.height, 2080.0);
        let o: Observer = "-33.9,270".parse().unwrap();
        assert!((o.longitude_deg() - -90.0).abs() < 1e-12);
        assert!("91,0".parse::<Observer>().is_err());
        assert!("1,2,3,4".parse::<Observer>().is_err());
        assert!("a,b".parse::<Observer>().is_err());
    }
}
