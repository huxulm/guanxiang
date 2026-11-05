use std::fmt;
use std::str::FromStr;

use crate::error::Error;

/// 第一版支持的天体。行星用系统质心（DE440s 只含质心，水星、金星的质心即行星本身）。
///
/// `SolarSystemBarycenter` 只作为计算中心使用，不在 [`Body::ALL`] 中。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Body {
    Sun,
    Mercury,
    Venus,
    Earth,
    Moon,
    Mars,
    Jupiter,
    Saturn,
    Uranus,
    Neptune,
    SolarSystemBarycenter,
}

impl Body {
    pub const ALL: [Body; 10] = [
        Body::Sun,
        Body::Mercury,
        Body::Venus,
        Body::Earth,
        Body::Moon,
        Body::Mars,
        Body::Jupiter,
        Body::Saturn,
        Body::Uranus,
        Body::Neptune,
    ];

    /// NAIF ID。外行星用系统质心 ID，DE440s 中没有行星本体的段。
    pub const fn naif_id(self) -> i32 {
        match self {
            Body::Sun => 10,
            Body::Mercury => 1,
            Body::Venus => 2,
            Body::Earth => 399,
            Body::Moon => 301,
            Body::Mars => 4,
            Body::Jupiter => 5,
            Body::Saturn => 6,
            Body::Uranus => 7,
            Body::Neptune => 8,
            Body::SolarSystemBarycenter => 0,
        }
    }

    pub const fn name(self) -> &'static str {
        match self {
            Body::Sun => "sun",
            Body::Mercury => "mercury",
            Body::Venus => "venus",
            Body::Earth => "earth",
            Body::Moon => "moon",
            Body::Mars => "mars",
            Body::Jupiter => "jupiter",
            Body::Saturn => "saturn",
            Body::Uranus => "uranus",
            Body::Neptune => "neptune",
            Body::SolarSystemBarycenter => "ssb",
        }
    }

    pub const fn name_zh(self) -> &'static str {
        match self {
            Body::Sun => "太阳",
            Body::Mercury => "水星",
            Body::Venus => "金星",
            Body::Earth => "地球",
            Body::Moon => "月球",
            Body::Mars => "火星",
            Body::Jupiter => "木星",
            Body::Saturn => "土星",
            Body::Uranus => "天王星",
            Body::Neptune => "海王星",
            Body::SolarSystemBarycenter => "太阳系质心",
        }
    }
}

impl fmt::Display for Body {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

impl FromStr for Body {
    type Err = Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let s = s.trim();
        Body::ALL
            .into_iter()
            .find(|b| b.name().eq_ignore_ascii_case(s) || b.name_zh() == s)
            .ok_or_else(|| Error::UnknownBody(s.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_round_trip() {
        for b in Body::ALL {
            assert_eq!(b.name().parse::<Body>().unwrap(), b);
            assert_eq!(b.name_zh().parse::<Body>().unwrap(), b);
        }
        assert_eq!("MOON".parse::<Body>().unwrap(), Body::Moon);
        assert!("pluto".parse::<Body>().is_err());
    }
}
