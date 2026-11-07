//! Flutter 调用的 API。
//!
//! 桥接层保持很薄（D6）：只把 core 的结果整理成适合界面显示的结构，并负责进度回传和取消。
//! 搜索按年分块执行，每块结束后回传进度、检查取消标志，core 不需要知道进度和取消。
//! 显示文字按 [`Lang`] 输出中文或英文（M7）。

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use flutter_rust_bridge::frb;
use guanxiang_core::events::almanac::{self, SkyEventKind};
use guanxiang_core::events::local_eclipse::{self, LocalSolarKind};
use guanxiang_core::events::longitude::{self, Aspect};
use guanxiang_core::events::lunar_eclipse::{self, LunarEclipse, LunarEclipseKind, ShadowModel};
use guanxiang_core::events::occultation::{self, Target};
use guanxiang_core::events::saros;
use guanxiang_core::events::sat_transit::{self, SatTransit};
use guanxiang_core::events::solar_eclipse::{self, SolarEclipse, SolarEclipseKind};
use guanxiang_core::events::visibility::{apparent_altitude, VisibilityFilter};
use guanxiang_core::events::{separation, transit, Span};
use guanxiang_core::satellite::Satellite;
use guanxiang_core::stars::Star;
use guanxiang_core::{astrometry, stars, AniseEphemeris, Body, DateTime, Observer, Time};

use crate::frb_generated::StreamSink;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// 显示语言。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lang {
    Zh,
    En,
}

impl Lang {
    /// 按语言选一段固定文字。
    fn s(self, zh: &'static str, en: &'static str) -> &'static str {
        match self {
            Lang::Zh => zh,
            Lang::En => en,
        }
    }

    fn body(self, b: Body) -> String {
        match self {
            Lang::Zh => b.name_zh().to_string(),
            Lang::En => {
                let n = b.name();
                let mut c = n.chars();
                c.next()
                    .map(|f| f.to_uppercase().collect::<String>() + c.as_str())
                    .unwrap_or_default()
            }
        }
    }

    fn star(self, s: &Star) -> String {
        match self {
            Lang::Zh => s.label(),
            Lang::En => star_name_en(s.hip)
                .map(str::to_string)
                .unwrap_or_else(|| format!("HIP {}", s.hip)),
        }
    }

    fn target(self, t: &Target) -> String {
        match t {
            Target::Planet(b) => self.body(*b),
            Target::Star(s) => self.star(s),
        }
    }
}

/// 有中文名的恒星对应的英文名（IAU 星名或拜耳名），与 core 星表的中文名一一对应。
fn star_name_en(hip: u32) -> Option<&'static str> {
    Some(match hip {
        17499 => "Electra",
        17531 => "Taygeta",
        17573 => "Maia",
        17608 => "Merope",
        17702 => "Alcyone",
        17847 => "Atlas",
        20205 => "γ Tau",
        21421 => "Aldebaran",
        25428 => "Elnath",
        42911 => "Asellus Australis",
        49669 => "Regulus",
        61941 => "Porrima",
        65474 => "Spica",
        72622 => "Zubenelgenubi",
        78401 => "Dschubba",
        78820 => "Acrab",
        80763 => "Antares",
        92855 => "Nunki",
        _ => return None,
    })
}

/// 已加载星历的计算引擎。
#[frb(opaque)]
pub struct Engine {
    eph: AniseEphemeris,
}

impl Engine {
    /// 从内存加载 SPK 星历（Flutter asset 读出的字节）。
    pub fn from_bytes(bytes: Vec<u8>) -> anyhow::Result<Engine> {
        Ok(Engine {
            eph: AniseEphemeris::from_bytes(&bytes)?,
        })
    }

    /// 可搜索的年份范围 `[起始, 结束)`（取月球的覆盖范围，去掉首尾不完整的年份）。
    #[frb(sync)]
    pub fn coverage_years(&self) -> anyhow::Result<Vec<i32>> {
        let (start, end) = self.eph.coverage(Body::Moon)?;
        let year = |t: guanxiang_core::Tdb| -> anyhow::Result<i32> {
            Ok(Time::from_tdb(t).to_utc()?.year)
        };
        Ok(vec![year(start)? + 1, year(end)?])
    }
}

/// 取消标志。Dart 端调用 `cancel()` 后，搜索在当前年份块结束时停止。
#[frb(opaque)]
pub struct CancelToken {
    flag: Arc<AtomicBool>,
}

impl CancelToken {
    #[frb(sync)]
    pub fn new() -> CancelToken {
        CancelToken {
            flag: Arc::new(AtomicBool::new(false)),
        }
    }

    #[frb(sync)]
    pub fn cancel(&self) {
        self.flag.store(true, Ordering::Relaxed);
    }

    fn is_cancelled(&self) -> bool {
        self.flag.load(Ordering::Relaxed)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventKind {
    Transit,
    Conjunction,
    Opposition,
    Appulse,
    SolarEclipse,
    LunarEclipse,
    Occultation,
}

/// 测站与可见性条件。
#[derive(Debug, Clone)]
pub struct ObserverInput {
    pub latitude_deg: f64,
    pub longitude_deg: f64,
    pub height_m: f64,
    /// 目标最低视高度（度）
    pub min_altitude_deg: f64,
    /// 太阳最高视高度（度），凌日不使用
    pub max_sun_altitude_deg: f64,
}

#[derive(Debug, Clone)]
pub struct SearchRequest {
    pub kind: EventKind,
    /// 天体英文名，如 "moon"。凌日时只用 `body_a`（"mercury"、"venus" 或空 = 两者）
    pub body_a: String,
    pub body_b: String,
    /// 起始年份（含），UTC 1 月 1 日
    pub from_year: i32,
    /// 结束年份（不含）
    pub to_year: i32,
    /// 角距极小的上限（度）
    pub max_separation_deg: f64,
    pub observer: Option<ObserverInput>,
    pub lang: Lang,
}

#[derive(Debug, Clone)]
pub struct Detail {
    pub label: String,
    pub value: String,
}

/// 一个事件，已整理成界面显示用的文字。
#[derive(Debug, Clone)]
pub struct EventItem {
    pub kind: EventKind,
    pub title: String,
    /// 主时刻（UTC），如 "2019-11-11 15:19:47"
    pub utc: String,
    pub tt_jd: f64,
    pub summary: String,
    pub details: Vec<Detail>,
    /// 肉眼几乎看不出（目前只有半影月食），看板等处默认不列出
    pub subtle: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UpdateKind {
    Progress,
    Found,
    Finished,
}

/// 搜索过程中的一条回传。用普通结构体而不是带数据的枚举，Dart 端不需要 freezed。
#[derive(Debug, Clone)]
pub struct SearchUpdate {
    pub kind: UpdateKind,
    /// Progress：已完成比例 0–1
    pub fraction: f64,
    /// Found：找到的事件
    pub item: Option<EventItem>,
    /// Finished：事件总数
    pub count: u32,
    /// Finished：是否被取消
    pub cancelled: bool,
    /// Finished：耗时（毫秒）
    pub elapsed_ms: u64,
}

impl SearchUpdate {
    fn progress(fraction: f64) -> Self {
        Self::blank(UpdateKind::Progress, fraction)
    }

    fn found(item: EventItem) -> Self {
        Self {
            item: Some(item),
            ..Self::blank(UpdateKind::Found, 0.0)
        }
    }

    fn finished(count: u32, cancelled: bool, elapsed_ms: u64) -> Self {
        Self {
            count,
            cancelled,
            elapsed_ms,
            ..Self::blank(UpdateKind::Finished, 1.0)
        }
    }

    fn blank(kind: UpdateKind, fraction: f64) -> Self {
        Self {
            kind,
            fraction,
            item: None,
            count: 0,
            cancelled: false,
            elapsed_ms: 0,
        }
    }
}

/// 支持的天体，供界面列出：label = 英文键名（传回 Rust 用），value = 显示名。
#[frb(sync)]
pub fn body_names(lang: Lang) -> Vec<Detail> {
    Body::ALL
        .iter()
        .filter(|b| **b != Body::Earth)
        .map(|b| Detail {
            label: b.name().to_string(),
            value: lang.body(*b),
        })
        .collect()
}

/// 执行搜索，结果和进度通过 `sink` 回传。
pub fn search(
    engine: &Engine,
    request: SearchRequest,
    token: &CancelToken,
    sink: StreamSink<SearchUpdate>,
) -> anyhow::Result<()> {
    let started = Instant::now();
    let lang = request.lang;
    anyhow::ensure!(
        request.to_year > request.from_year,
        "{}",
        lang.s(
            "结束年份必须晚于起始年份",
            "The end year must be after the start year"
        )
    );
    let filter = request
        .observer
        .as_ref()
        .map(|o| -> anyhow::Result<VisibilityFilter> {
            Ok(VisibilityFilter {
                observer: Observer::from_degrees(o.latitude_deg, o.longitude_deg, o.height_m)?,
                min_altitude: o.min_altitude_deg.to_radians(),
                max_sun_altitude: Some(o.max_sun_altitude_deg.to_radians()),
            })
        })
        .transpose()?;

    let years = request.to_year - request.from_year;
    let mut count = 0u32;
    let mut cancelled = false;
    for (i, year) in (request.from_year..request.to_year).enumerate() {
        if token.is_cancelled() {
            cancelled = true;
            break;
        }
        let span = Span::new(year_start(year)?, year_start(year + 1)?)?;
        for item in search_span(&engine.eph, &request, filter.as_ref(), span)? {
            count += 1;
            send(&sink, SearchUpdate::found(item))?;
        }
        send(&sink, SearchUpdate::progress((i + 1) as f64 / years as f64))?;
    }
    send(
        &sink,
        SearchUpdate::finished(count, cancelled, started.elapsed().as_millis() as u64),
    )
}

fn send(sink: &StreamSink<SearchUpdate>, update: SearchUpdate) -> anyhow::Result<()> {
    sink.add(update)
        .map_err(|e| anyhow::anyhow!("回传结果失败 / failed to send result: {e:?}"))
}

fn year_start(year: i32) -> anyhow::Result<Time> {
    Ok(Time::from_utc(&DateTime::new(year, 1, 1, 0, 0, 0.0)?)?)
}

fn body(name: &str) -> anyhow::Result<Body> {
    Ok(name.parse::<Body>()?)
}

fn utc(t: &Time) -> String {
    t.to_utc()
        .map(|d| d.to_string()[..19].replace('T', " "))
        .unwrap_or_else(|_| format!("TT JD {:.5}", t.tt_jd()))
}

/// 经纬度写成 “31.30°S 48.48°W”
fn lat_lon(lat_deg: f64, lon_deg: f64) -> String {
    let ns = if lat_deg >= 0.0 { 'N' } else { 'S' };
    let ew = if lon_deg >= 0.0 { 'E' } else { 'W' };
    format!("{:.2}°{ns} {:.2}°{ew}", lat_deg.abs(), lon_deg.abs())
}

fn detail(label: impl Into<String>, value: String) -> Detail {
    Detail {
        label: label.into(),
        value,
    }
}

fn arcsec(rad: f64) -> f64 {
    rad.to_degrees() * 3600.0
}

fn search_span(
    eph: &AniseEphemeris,
    req: &SearchRequest,
    filter: Option<&VisibilityFilter>,
    span: Span,
) -> anyhow::Result<Vec<EventItem>> {
    let l = req.lang;
    let mut out = Vec::new();
    match req.kind {
        EventKind::Transit => {
            let planets = match req.body_a.as_str() {
                "" => vec![Body::Mercury, Body::Venus],
                name => vec![body(name)?],
            };
            for p in planets {
                for t in transit::search(eph, p, span)? {
                    let mut details = Vec::new();
                    let labels = [
                        l.s("外切入（I）", "First contact (I)"),
                        l.s("内切入（II）", "Second contact (II)"),
                        l.s("内切出（III）", "Third contact (III)"),
                        l.s("外切出（IV）", "Fourth contact (IV)"),
                    ];
                    for (label, c) in labels.iter().zip(&t.contacts) {
                        if let Some(c) = c {
                            details.push(detail(*label, utc(c)));
                        }
                    }
                    details.push(detail(l.s("凌甚", "Greatest transit"), utc(&t.greatest)));
                    details.push(detail(
                        l.s("最小角距", "Minimum separation"),
                        format!("{:.1}″", arcsec(t.min_separation)),
                    ));
                    details.push(detail(
                        l.s("太阳视半径", "Sun semi-diameter"),
                        format!("{:.1}″", arcsec(t.sun_semidiameter)),
                    ));
                    details.push(detail(
                        l.s("行星视半径", "Planet semi-diameter"),
                        format!("{:.2}″", arcsec(t.planet_semidiameter)),
                    ));
                    if let Some(f) = filter {
                        let moments = t
                            .contacts
                            .iter()
                            .flatten()
                            .chain(std::iter::once(&t.greatest));
                        let mut best = f64::NEG_INFINITY;
                        for m in moments {
                            best = best.max(apparent_altitude(eph, Body::Sun, m, &f.observer)?);
                        }
                        if best < 0.0 {
                            continue;
                        }
                        let h = apparent_altitude(eph, Body::Sun, &t.greatest, &f.observer)?;
                        details.push(detail(
                            l.s("凌甚时太阳高度", "Sun altitude at greatest"),
                            format!("{:.1}°", h.to_degrees()),
                        ));
                    }
                    let title = match l {
                        Lang::Zh => format!(
                            "{}凌日{}",
                            p.name_zh(),
                            if t.is_full() { "" } else { "（掠凌）" }
                        ),
                        Lang::En => format!(
                            "{}Transit of {}",
                            if t.is_full() { "" } else { "Grazing " },
                            l.body(p)
                        ),
                    };
                    out.push(EventItem {
                        kind: EventKind::Transit,
                        subtle: false,
                        title,
                        utc: utc(&t.greatest),
                        tt_jd: t.greatest.tt_jd(),
                        summary: format!(
                            "{} {:.1}″",
                            l.s("最小角距", "Min. separation"),
                            arcsec(t.min_separation)
                        ),
                        details,
                    });
                }
            }
        }
        EventKind::Conjunction | EventKind::Opposition => {
            let (a, b) = (body(&req.body_a)?, body(&req.body_b)?);
            let aspect = if req.kind == EventKind::Conjunction {
                Aspect::Conjunction
            } else {
                Aspect::Opposition
            };
            let step = longitude::default_step_days(a, b);
            for e in longitude::search(eph, a, b, aspect, span, step)? {
                if let Some(f) = filter {
                    if !f.is_visible(eph, &[a, b], &e.time)? {
                        continue;
                    }
                }
                let conj = aspect == Aspect::Conjunction;
                // 行星与太阳的合分上合、下合
                let which = (b == Body::Sun && a != Body::Moon && conj)
                    .then_some(e.distance_a_km < e.distance_b_km);
                let title = match l {
                    Lang::Zh => format!(
                        "{}{}{}{}",
                        a.name_zh(),
                        b.name_zh(),
                        if conj { "合" } else { "冲" },
                        match which {
                            Some(true) => "（下合）",
                            Some(false) => "（上合）",
                            None => "",
                        }
                    ),
                    Lang::En => format!(
                        "{}{} {} {}",
                        match which {
                            Some(true) => "Inferior ",
                            Some(false) => "Superior ",
                            None => "",
                        },
                        l.body(a),
                        if conj {
                            "conjunction with"
                        } else {
                            "opposition to"
                        },
                        l.body(b)
                    ),
                };
                out.push(EventItem {
                    kind: req.kind,
                    subtle: false,
                    title,
                    utc: utc(&e.time),
                    tt_jd: e.time.tt_jd(),
                    summary: format!(
                        "{} {:.3}°",
                        l.s("角距", "Separation"),
                        e.separation.to_degrees()
                    ),
                    details: vec![
                        detail(l.s("时刻（UTC）", "Time (UTC)"), utc(&e.time)),
                        detail(
                            l.s("角距", "Separation"),
                            format!("{:.4}°", e.separation.to_degrees()),
                        ),
                        detail(
                            l.s("黄纬差", "Latitude difference"),
                            format!("{:.4}°", e.latitude_difference.to_degrees()),
                        ),
                        detail(distance_label(l, a), format!("{:.0} km", e.distance_a_km)),
                        detail(distance_label(l, b), format!("{:.0} km", e.distance_b_km)),
                    ],
                });
            }
        }
        EventKind::Appulse => {
            let (a, b) = (body(&req.body_a)?, body(&req.body_b)?);
            let step = separation::default_step_days(a, b);
            let max = req.max_separation_deg.to_radians();
            for m in separation::search(eph, a, b, span, step, max)? {
                if let Some(f) = filter {
                    if !f.is_visible(eph, &[a, b], &m.time)? {
                        continue;
                    }
                }
                let title = match l {
                    Lang::Zh => format!("{}与{}相距最近", a.name_zh(), b.name_zh()),
                    Lang::En => format!("{} closest to {}", l.body(a), l.body(b)),
                };
                out.push(EventItem {
                    kind: EventKind::Appulse,
                    subtle: false,
                    title,
                    utc: utc(&m.time),
                    tt_jd: m.time.tt_jd(),
                    summary: format!(
                        "{} {:.3}°",
                        l.s("角距", "Separation"),
                        m.separation.to_degrees()
                    ),
                    details: vec![
                        detail(l.s("时刻（UTC）", "Time (UTC)"), utc(&m.time)),
                        detail(
                            l.s("角距", "Separation"),
                            format!("{:.4}°", m.separation.to_degrees()),
                        ),
                    ],
                });
            }
        }
        EventKind::SolarEclipse => {
            for e in solar_eclipse::search(eph, span)? {
                let name = match e.kind {
                    SolarEclipseKind::Partial => l.s("日偏食", "Partial solar eclipse"),
                    SolarEclipseKind::Annular => l.s("日环食", "Annular solar eclipse"),
                    SolarEclipseKind::Total => l.s("日全食", "Total solar eclipse"),
                    SolarEclipseKind::Hybrid => l.s("全环食", "Hybrid solar eclipse"),
                };
                let non_central = e.kind != SolarEclipseKind::Partial && !e.central;
                let mut details = vec![
                    detail(
                        l.s("食甚（全球，UTC）", "Greatest eclipse (UTC)"),
                        utc(&e.greatest),
                    ),
                    detail(
                        l.s("γ（影轴离地心）", "Gamma (axis offset)"),
                        format!("{:+.4}", e.gamma),
                    ),
                    detail(
                        l.s("食分（全球）", "Magnitude"),
                        format!("{:.4}", e.magnitude),
                    ),
                ];
                if let Some(p) = e.greatest_point {
                    details.push(detail(
                        l.s("食甚点", "Point of greatest eclipse"),
                        lat_lon(p.latitude_deg, p.longitude_deg),
                    ));
                    details.push(detail(
                        l.s("食甚点太阳高度", "Sun altitude there"),
                        format!("{:.0}°", p.sun_altitude_deg),
                    ));
                    details.push(detail(
                        l.s("食带宽度", "Path width"),
                        format!("{:.0} km", p.path_width_km),
                    ));
                }
                if let Some(sr) = saros::solar_saros(&e.greatest) {
                    details.push(detail(l.s("沙罗序列", "Saros series"), saros_label(sr, l)));
                }
                let mut summary = format!("{} {:.3}", l.s("食分", "Magnitude"), e.magnitude);
                if let Some(f) = filter {
                    let Some(lo) = local_eclipse::local_solar(eph, &e, &f.observer, None)? else {
                        continue;
                    };
                    if !lo.is_visible() {
                        continue;
                    }
                    let k = match lo.kind {
                        LocalSolarKind::Partial => l.s("偏食", "partial"),
                        LocalSolarKind::Annular => l.s("环食", "annular"),
                        LocalSolarKind::Total => l.s("全食", "total"),
                    };
                    summary = match l {
                        Lang::Zh => format!("本地{k}，食分 {:.3}", lo.magnitude),
                        Lang::En => format!("Local {k}, magnitude {:.3}", lo.magnitude),
                    };
                    details.push(detail(l.s("本地类型", "Local type"), k.to_string()));
                    details.push(detail(l.s("本地食甚", "Local maximum"), utc(&lo.maximum)));
                    details.push(detail(
                        l.s("本地食分", "Local magnitude"),
                        format!("{:.3}", lo.magnitude),
                    ));
                    details.push(detail(
                        l.s("食面积", "Obscuration"),
                        format!("{:.1}%", lo.obscuration * 100.0),
                    ));
                    let names = [
                        l.s("初亏（C1）", "First contact (C1)"),
                        l.s("食既（C2）", "Second contact (C2)"),
                        l.s("生光（C3）", "Third contact (C3)"),
                        l.s("复圆（C4）", "Fourth contact (C4)"),
                    ];
                    for (label, c) in names.iter().zip(&lo.contacts) {
                        if let Some(c) = c {
                            details.push(detail(*label, utc(c)));
                        }
                    }
                    details.push(detail(
                        l.s("太阳高度（初亏/食甚/复圆）", "Sun altitude (C1 / max / C4)"),
                        format!(
                            "{:.0}° / {:.0}° / {:.0}°",
                            lo.sun_altitude_deg[0], lo.sun_altitude_deg[1], lo.sun_altitude_deg[2]
                        ),
                    ));
                }
                out.push(EventItem {
                    kind: EventKind::SolarEclipse,
                    subtle: false,
                    title: format!(
                        "{name}{}",
                        if non_central {
                            l.s("（非中心）", " (non-central)")
                        } else {
                            ""
                        }
                    ),
                    utc: utc(&e.greatest),
                    tt_jd: e.greatest.tt_jd(),
                    summary,
                    details,
                });
            }
        }
        EventKind::LunarEclipse => {
            for e in lunar_eclipse::search(eph, span, ShadowModel::Danjon)? {
                let name = match e.kind {
                    LunarEclipseKind::Penumbral => l.s("半影月食", "Penumbral lunar eclipse"),
                    LunarEclipseKind::Partial => l.s("月偏食", "Partial lunar eclipse"),
                    LunarEclipseKind::Total => l.s("月全食", "Total lunar eclipse"),
                };
                let labels = [
                    l.s("半影食始（P1）", "Penumbral begins (P1)"),
                    l.s("初亏（U1）", "Partial begins (U1)"),
                    l.s("食既（U2）", "Total begins (U2)"),
                    l.s("生光（U3）", "Total ends (U3)"),
                    l.s("复圆（U4）", "Partial ends (U4)"),
                    l.s("半影食终（P4）", "Penumbral ends (P4)"),
                ];
                let mut details = vec![
                    detail(
                        l.s("食甚（UTC）", "Greatest eclipse (UTC)"),
                        utc(&e.greatest),
                    ),
                    detail(
                        l.s("γ（影轴离地心）", "Gamma (axis offset)"),
                        format!("{:+.4}", e.gamma),
                    ),
                    detail(
                        l.s("半影食分", "Penumbral magnitude"),
                        format!("{:.4}", e.penumbral_magnitude),
                    ),
                    detail(
                        l.s("本影食分", "Umbral magnitude"),
                        format!("{:.4}", e.umbral_magnitude),
                    ),
                ];
                if let Some(sr) = saros::lunar_saros(&e.greatest) {
                    details.push(detail(l.s("沙罗序列", "Saros series"), saros_label(sr, l)));
                }
                for (label, c) in labels.iter().zip(&e.contacts) {
                    if let Some(c) = c {
                        details.push(detail(*label, utc(c)));
                    }
                }
                if let Some(f) = filter {
                    let alt = local_eclipse::lunar_altitudes(eph, &e, &f.observer)?;
                    if !alt.iter().any(|h| *h > 0.0) {
                        continue;
                    }
                    details.push(detail(
                        l.s("食甚时月亮高度", "Moon altitude at greatest"),
                        format!("{:.0}°", alt[3]),
                    ));
                }
                out.push(EventItem {
                    kind: EventKind::LunarEclipse,
                    subtle: e.kind == LunarEclipseKind::Penumbral,
                    title: name.to_string(),
                    utc: utc(&e.greatest),
                    tt_jd: e.greatest.tt_jd(),
                    // 半影月食的本影食分是负数，对读者没有意义，改写半影食分
                    summary: if e.kind == LunarEclipseKind::Penumbral {
                        format!(
                            "{} {:.3}",
                            l.s("半影食分", "Penumbral magnitude"),
                            e.penumbral_magnitude
                        )
                    } else {
                        format!(
                            "{} {:.3}",
                            l.s("本影食分", "Umbral magnitude"),
                            e.umbral_magnitude
                        )
                    },
                    details,
                });
            }
        }
        EventKind::Occultation => {
            const PLANETS: [Body; 7] = [
                Body::Mercury,
                Body::Venus,
                Body::Mars,
                Body::Jupiter,
                Body::Saturn,
                Body::Uranus,
                Body::Neptune,
            ];
            let key = req.body_a.trim();
            let mut cands = Vec::new();
            if matches!(key, "planets" | "all") {
                for p in PLANETS {
                    cands.extend(occultation::candidates(eph, Target::Planet(p), span)?);
                }
            }
            if matches!(key, "stars" | "all") {
                cands.extend(occultation::candidates_all_stars(eph, span)?);
            }
            if !matches!(key, "planets" | "stars" | "all") {
                let target = match key.parse::<Body>() {
                    Ok(b) => Target::Planet(b),
                    Err(_) => Target::Star(stars::find(key).ok_or_else(|| {
                        anyhow::anyhow!(
                            "{} {key}",
                            l.s("星表中找不到", "Not in the star catalogue:")
                        )
                    })?),
                };
                cands.extend(occultation::candidates(eph, target, span)?);
            }
            cands.sort_by(|a, b| a.time.tt_seconds().total_cmp(&b.time.tt_seconds()));
            let mag = |t: &Target| match t {
                Target::Star(s) => match l {
                    Lang::Zh => format!("{:.1} 等", s.vmag),
                    Lang::En => format!("mag {:.1}", s.vmag),
                },
                Target::Planet(_) => l.s("行星", "planet").to_string(),
            };
            for c in cands {
                let label = l.target(&c.target);
                let title = match l {
                    Lang::Zh => format!("月掩{label}"),
                    Lang::En => format!("Lunar occultation of {label}"),
                };
                match filter {
                    None => out.push(EventItem {
                        kind: EventKind::Occultation,
                        subtle: false,
                        title: format!(
                            "{title}{}",
                            l.s("（地心候选）", " (geocentric candidate)")
                        ),
                        utc: utc(&c.time),
                        tt_jd: c.time.tt_jd(),
                        summary: format!(
                            "{} {:.3}°, {}",
                            l.s("地心角距", "Geocentric separation"),
                            c.separation.to_degrees(),
                            mag(&c.target)
                        ),
                        details: vec![
                            detail(
                                l.s("地心最近（UTC）", "Geocentric closest (UTC)"),
                                utc(&c.time),
                            ),
                            detail(
                                l.s("地心几何角距", "Geocentric separation"),
                                format!("{:.3}°", c.separation.to_degrees()),
                            ),
                            detail(
                                l.s("说明", "Note"),
                                l.s(
                                    "打开“只显示本地可见”可得到某地的掩始、掩终",
                                    "Turn on “Visible from my location” for local disappearance and reappearance times",
                                )
                                .to_string(),
                            ),
                        ],
                    }),
                    Some(f) => {
                        let Some(o) = occultation::local(eph, &c, &f.observer, None)? else {
                            continue;
                        };
                        if !o.moon_above_horizon() {
                            continue;
                        }
                        let daytime = o.sun_altitude_deg.iter().all(|&h| h > -6.0);
                        out.push(EventItem {
                            kind: EventKind::Occultation,
                            subtle: false,
                            title,
                            utc: utc(&o.disappearance),
                            tt_jd: o.disappearance.tt_jd(),
                            summary: format!(
                                "{} {}, {}{}",
                                l.s("掩终", "Reappears"),
                                &utc(&o.reappearance)[11..],
                                mag(&o.target),
                                if daytime {
                                    l.s("，白天", ", daytime")
                                } else {
                                    ""
                                }
                            ),
                            details: vec![
                                detail(
                                    l.s("掩始（UTC）", "Disappearance (UTC)"),
                                    utc(&o.disappearance),
                                ),
                                detail(
                                    l.s("掩终（UTC）", "Reappearance (UTC)"),
                                    utc(&o.reappearance),
                                ),
                                detail(l.s("最近（UTC）", "Closest (UTC)"), utc(&o.closest)),
                                detail(
                                    l.s(
                                        "月亮高度（掩始/掩终）",
                                        "Moon altitude (disapp. / reapp.)",
                                    ),
                                    format!(
                                        "{:.0}° / {:.0}°",
                                        o.moon_altitude_deg[0], o.moon_altitude_deg[1]
                                    ),
                                ),
                                detail(
                                    l.s(
                                        "太阳高度（掩始/掩终）",
                                        "Sun altitude (disapp. / reapp.)",
                                    ),
                                    format!(
                                        "{:.0}° / {:.0}°",
                                        o.sun_altitude_deg[0], o.sun_altitude_deg[1]
                                    ),
                                ),
                            ],
                        });
                    }
                }
            }
        }
    }
    Ok(out)
}

fn distance_label(l: Lang, b: Body) -> String {
    match l {
        Lang::Zh => format!("{}距离", b.name_zh()),
        Lang::En => format!("{} distance", l.body(b)),
    }
}

// ---------------------------------------------------------------------------
// 卫星（M6）。按 D5，网络请求在 Dart 端，这里只接收 OMM JSON 字符串。

/// 一组根数的摘要。
#[derive(Debug, Clone)]
pub struct SatelliteInfo {
    pub norad_id: u32,
    pub name: String,
    /// 根数历元（UTC）
    pub epoch_utc: String,
    pub epoch_tt_jd: f64,
}

/// 解析 CelesTrak `FORMAT=JSON` 的 OMM。
#[frb(sync)]
pub fn parse_omm(json: String) -> anyhow::Result<Vec<SatelliteInfo>> {
    Ok(Satellite::from_omm_json(&json)?
        .iter()
        .map(|s| SatelliteInfo {
            norad_id: s.norad_id,
            name: s.name.clone(),
            epoch_utc: utc(&s.epoch),
            epoch_tt_jd: s.epoch.tt_jd(),
        })
        .collect())
}

#[derive(Debug, Clone, Copy)]
pub struct GeoPoint {
    pub latitude_deg: f64,
    pub longitude_deg: f64,
}

/// 一次卫星接近，含地图显示需要的中心线。
#[derive(Debug, Clone)]
pub struct SatTransitItem {
    pub norad_id: u32,
    pub satellite: String,
    /// "sun" 或 "moon"
    pub body: String,
    /// 是否穿过日面（月面）
    pub is_transit: bool,
    pub title: String,
    pub utc: String,
    pub tt_jd: f64,
    pub summary: String,
    pub details: Vec<Detail>,
    pub distance_to_centerline_km: f64,
    pub band_half_width_km: f64,
    pub elements_age_days: f64,
    pub centerline: Vec<GeoPoint>,
    pub centerline_nearest: GeoPoint,
    /// 与旧根数预报相比的时刻变化（秒）；没有旧根数或旧根数里找不到对应事件为 None
    pub previous_shift_s: Option<f64>,
    /// 与旧根数预报相比的中心线横向移动（km）
    pub previous_shift_km: Option<f64>,
    /// 新旧预报差别大，或根数太旧，需要提醒
    pub warning: Option<String>,
}

/// 时刻变化超过此值（秒）时提醒。
const WARN_SHIFT_S: f64 = 1.0;
/// 中心线移动超过此值（km）时提醒。
const WARN_SHIFT_KM: f64 = 1.0;
/// 根数龄期超过此值（天）时提醒。
const WARN_AGE_DAYS: f64 = 3.0;

/// 观测太阳的安全提示，所有涉及太阳的结果都附带，卫星页也显示。
#[frb(sync)]
pub fn sun_safety_notice(lang: Lang) -> String {
    lang.s(
        "观测太阳必须使用合格的太阳滤光膜（ISO 12312-2）。切勿用肉眼、普通墨镜，或未加滤光的望远镜、相机直视太阳。",
        "Never look at the Sun with the naked eye, ordinary sunglasses, or an unfiltered telescope or camera. Always use a certified solar filter (ISO 12312-2).",
    )
    .to_string()
}

/// 示意图上的一点。月食图单位为度（月心相对地影中心，x 向东、y 向北）；
/// 日食图单位为地球赤道半径（影轴在基本面上，x 向东、y 向北）。
#[derive(Debug, Clone)]
pub struct DiagramPoint {
    pub x: f64,
    pub y: f64,
    /// UTC，如 "2025-09-07 18:11:48"
    pub utc: String,
    /// 接触点名称（P1、U1、U2、U3、U4、P4、食甚），轨迹点为空
    pub label: String,
}

/// 月食示意图（NASA 星表的月食图）。
#[derive(Debug, Clone)]
pub struct LunarEclipseDiagram {
    /// 食甚时的半影、本影半径和月球视半径（度）
    pub penumbra_deg: f64,
    pub umbra_deg: f64,
    pub moon_semidiameter_deg: f64,
    /// 月心轨迹（半影食始前 30 分钟到半影食终后 30 分钟，每 5 分钟）
    pub path: Vec<DiagramPoint>,
    /// 食甚和各接触点
    pub marks: Vec<DiagramPoint>,
}

/// 日食示意图：从太阳方向看地球，影轴扫过的轨迹。
#[derive(Debug, Clone)]
pub struct SolarEclipseDiagram {
    /// 影轴轨迹（每 5 分钟）
    pub track: Vec<DiagramPoint>,
    pub greatest: DiagramPoint,
    /// 食甚时半影、本影半径（地球半径）；本影为负表示全食
    pub penumbra_radius: f64,
    pub umbra_radius: f64,
    /// 影轴赤纬（度），决定图上地轴和赤道的倾斜
    pub axis_declination_deg: f64,
}

/// 示意图轨迹的取样间隔（秒）
const DIAGRAM_STEP_S: f64 = 300.0;

/// 找回 `tt_jd` 那次日食或月食所在的一天。
fn eclipse_span(tt_jd: f64) -> anyhow::Result<Span> {
    Ok(Span::new(
        Time::from_tt_jd(tt_jd - 1.0),
        Time::from_tt_jd(tt_jd + 1.0),
    )?)
}

/// 月食示意图。`tt_jd` 为搜索结果里该次月食的食甚（`EventItem.tt_jd`）。
pub fn lunar_eclipse_diagram(
    engine: &Engine,
    tt_jd: f64,
    lang: Lang,
) -> anyhow::Result<LunarEclipseDiagram> {
    let e = find_lunar_eclipse(engine, tt_jd, lang)?;
    lunar_diagram(engine, &e, lang)
}

/// 按食甚的 TT 儒略日找回那次月食。
fn find_lunar_eclipse(engine: &Engine, tt_jd: f64, lang: Lang) -> anyhow::Result<LunarEclipse> {
    lunar_eclipse::search(&engine.eph, eclipse_span(tt_jd)?, ShadowModel::Danjon)?
        .into_iter()
        .min_by(|a, b| {
            (a.greatest.tt_jd() - tt_jd)
                .abs()
                .total_cmp(&(b.greatest.tt_jd() - tt_jd).abs())
        })
        .ok_or_else(|| anyhow::anyhow!("{}", lang.s("找不到这次月食", "Eclipse not found")))
}

fn lunar_diagram(
    engine: &Engine,
    e: &LunarEclipse,
    lang: Lang,
) -> anyhow::Result<LunarEclipseDiagram> {
    let d = lunar_eclipse::diagram(&engine.eph, e, ShadowModel::Danjon, DIAGRAM_STEP_S)?;
    let point = |p: &lunar_eclipse::ShadowPoint, label: &str| DiagramPoint {
        x: p.x_deg,
        y: p.y_deg,
        utc: utc(&p.time),
        label: label.to_string(),
    };
    let names = ["P1", "U1", "U2", "U3", "U4", "P4"];
    let mut marks: Vec<DiagramPoint> = d
        .contacts
        .iter()
        .zip(names)
        .filter_map(|(c, n)| c.as_ref().map(|c| point(c, n)))
        .collect();
    marks.push(point(&d.greatest, lang.s("食甚", "Max")));
    Ok(LunarEclipseDiagram {
        penumbra_deg: d.penumbra_deg,
        umbra_deg: d.umbra_deg,
        moon_semidiameter_deg: d.moon_semidiameter_deg,
        path: d.path.iter().map(|p| point(p, "")).collect(),
        marks,
    })
}

/// 沙罗序列，如“128（第 41 次，共 71 次）”。
fn saros_label(s: saros::Saros, l: Lang) -> String {
    match l {
        Lang::Zh => format!("{}（第 {} 次，共 {} 次）", s.series, s.member, s.count),
        Lang::En => format!("{} ({} of {})", s.series, s.member, s.count),
    }
}

/// 观测地点（只用于本地可见情况，不做可见性过滤）。
#[derive(Debug, Clone, Copy)]
pub struct Site {
    pub latitude_deg: f64,
    pub longitude_deg: f64,
    pub height_m: f64,
}

/// 某一时刻在观测地看到的日月（度；高度含大气折射，方位从北向东量）。
#[derive(Debug, Clone, Copy)]
pub struct HorizonPoint {
    pub moon_altitude_deg: f64,
    pub moon_azimuth_deg: f64,
    pub sun_altitude_deg: f64,
}

/// 月食的一个食相。
#[derive(Debug, Clone)]
pub struct EclipsePhase {
    /// P1、U1、U2、Max、U3、U4、P4
    pub code: String,
    /// 显示名称，如“食既”
    pub name: String,
    pub utc: String,
    /// 月下点：此刻月亮在天顶的地方
    pub sublunar: GeoPoint,
    /// 有观测地点时才有
    pub horizon: Option<HorizonPoint>,
}

/// 在观测地能看到多少（月偏食、月全食按本影食 U1–U4 判断，半影月食按 P1–P4 判断）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LunarVisibility {
    /// 全程月亮都在地平线以上
    Full,
    /// 月出时已在食中
    Rises,
    /// 月落时仍在食中
    Sets,
    /// 食中既有月出又有月落（高纬度才会出现）
    RisesAndSets,
    /// 全程月亮都在地平线以下
    Hidden,
}

/// 观测地的可见情况。
#[derive(Debug, Clone)]
pub struct LocalLunarView {
    pub verdict: LunarVisibility,
    /// 全食阶段能否看到（至少有一部分时间月亮在地平线以上）；没有全食时为 false
    pub totality_visible: bool,
    /// 月亮视高度（度），与 `diagram.path` 逐点对应，滑块用
    pub track_altitude_deg: Vec<f64>,
    /// P1 前 1 小时到 P4 后 1 小时之间的月出、月落
    pub moon_events: Vec<SkyEventItem>,
}

/// 月食详情页的全部数据。
#[derive(Debug, Clone)]
pub struct LunarEclipseDetail {
    pub diagram: LunarEclipseDiagram,
    /// 按时间顺序，没有的接触跳过
    pub phases: Vec<EclipsePhase>,
    /// 半影食（P1–P4）、本影食（U1–U4）、全食（U2–U3）的持续时间（分钟）
    pub penumbral_minutes: f64,
    pub partial_minutes: Option<f64>,
    pub total_minutes: Option<f64>,
    /// 沙罗序列，如“128（第 41 次，共 71 次）”；星历范围外为空
    pub saros: String,
    pub local: Option<LocalLunarView>,
}

/// 月食详情。`tt_jd` 为搜索结果里该次月食的食甚；`site` 为空时不算本地可见情况。
pub fn lunar_eclipse_detail(
    engine: &Engine,
    tt_jd: f64,
    site: Option<Site>,
    lang: Lang,
) -> anyhow::Result<LunarEclipseDetail> {
    let eph = &engine.eph;
    let e = find_lunar_eclipse(engine, tt_jd, lang)?;
    let diagram = lunar_diagram(engine, &e, lang)?;
    let obs = site
        .map(|s| Observer::from_degrees(s.latitude_deg, s.longitude_deg, s.height_m))
        .transpose()?;

    let c = e.contacts;
    let moments = [
        ("P1", l_phase(lang, 0), c[0]),
        ("U1", l_phase(lang, 1), c[1]),
        ("U2", l_phase(lang, 2), c[2]),
        ("Max", l_phase(lang, 3), Some(e.greatest)),
        ("U3", l_phase(lang, 4), c[3]),
        ("U4", l_phase(lang, 5), c[4]),
        ("P4", l_phase(lang, 6), c[5]),
    ];
    let mut phases = Vec::new();
    for (code, name, t) in moments {
        let Some(t) = t else { continue };
        let (lat, lon) = astrometry::sub_body_point(eph, Body::Moon, &t)?;
        let horizon = obs
            .as_ref()
            .map(|o| -> anyhow::Result<HorizonPoint> {
                Ok(HorizonPoint {
                    moon_altitude_deg: apparent_altitude(eph, Body::Moon, &t, o)?.to_degrees(),
                    moon_azimuth_deg: astrometry::topocentric(eph, Body::Moon, &t, o)?
                        .horizontal
                        .azimuth
                        .to_degrees(),
                    sun_altitude_deg: apparent_altitude(eph, Body::Sun, &t, o)?.to_degrees(),
                })
            })
            .transpose()?;
        phases.push(EclipsePhase {
            code: code.to_string(),
            name: name.to_string(),
            utc: utc(&t),
            sublunar: geo((lat.to_degrees(), lon.to_degrees())),
            horizon,
        });
    }

    let minutes = |a: Option<Time>, b: Option<Time>| match (a, b) {
        (Some(a), Some(b)) => Some((b.tt_seconds() - a.tt_seconds()) / 60.0),
        _ => None,
    };
    let local = match &obs {
        Some(o) => Some(local_lunar_view(engine, &e, o)?),
        None => None,
    };
    Ok(LunarEclipseDetail {
        diagram,
        phases,
        penumbral_minutes: minutes(c[0], c[5]).unwrap_or(0.0),
        partial_minutes: minutes(c[1], c[4]),
        total_minutes: minutes(c[2], c[3]),
        saros: saros::lunar_saros(&e.greatest)
            .map(|s| saros_label(s, lang))
            .unwrap_or_default(),
        local,
    })
}

/// 食相名称，顺序：P1、U1、U2、食甚、U3、U4、P4。
fn l_phase(l: Lang, i: usize) -> &'static str {
    const ZH: [&str; 7] = [
        "半影食始",
        "初亏",
        "食既",
        "食甚",
        "生光",
        "复圆",
        "半影食终",
    ];
    const EN: [&str; 7] = [
        "Penumbral begins",
        "Partial begins",
        "Total begins",
        "Greatest",
        "Total ends",
        "Partial ends",
        "Penumbral ends",
    ];
    match l {
        Lang::Zh => ZH[i],
        Lang::En => EN[i],
    }
}

/// 观测地的可见情况：沿示意图的轨迹时刻（每 5 分钟）和各接触时刻取月亮视高度。
fn local_lunar_view(
    engine: &Engine,
    e: &LunarEclipse,
    obs: &Observer,
) -> anyhow::Result<LocalLunarView> {
    let eph = &engine.eph;
    let d = lunar_eclipse::diagram(eph, e, ShadowModel::Danjon, DIAGRAM_STEP_S)?;
    let alt = |t: &Time| -> anyhow::Result<f64> {
        Ok(apparent_altitude(eph, Body::Moon, t, obs)?.to_degrees())
    };
    let track = d
        .path
        .iter()
        .map(|p| alt(&p.time))
        .collect::<anyhow::Result<Vec<_>>>()?;

    // [from, to] 内各取样点的高度（两端用接触时刻本身）
    let c = e.contacts;
    let samples = |from: Time, to: Time| -> anyhow::Result<Vec<f64>> {
        let (a, b) = (from.tt_seconds(), to.tt_seconds());
        let mut v = vec![alt(&from)?];
        for (p, h) in d.path.iter().zip(&track) {
            let t = p.time.tt_seconds();
            if t > a && t < b {
                v.push(*h);
            }
        }
        v.push(alt(&to)?);
        Ok(v)
    };
    let (from, to) = match (c[1], c[4]) {
        (Some(u1), Some(u4)) => (u1, u4),
        _ => (c[0].unwrap_or(e.greatest), c[5].unwrap_or(e.greatest)),
    };
    let window = samples(from, to)?;
    let up: Vec<bool> = window.iter().map(|h| *h > 0.0).collect();
    let verdict = match (
        up.first(),
        up.last(),
        up.iter().any(|u| *u),
        up.iter().all(|u| *u),
    ) {
        (_, _, _, true) => LunarVisibility::Full,
        (_, _, false, _) => LunarVisibility::Hidden,
        (Some(false), Some(true), _, _) => LunarVisibility::Rises,
        (Some(true), Some(false), _, _) => LunarVisibility::Sets,
        _ => LunarVisibility::RisesAndSets,
    };
    let totality_visible = match (c[2], c[3]) {
        (Some(u2), Some(u3)) => samples(u2, u3)?.iter().any(|h| *h > 0.0),
        _ => false,
    };

    let span = Span::new(
        c[0].unwrap_or(e.greatest).add_seconds(-3600.0),
        c[5].unwrap_or(e.greatest).add_seconds(3600.0),
    )?;
    let moon_events = almanac::rise_set_twilight(eph, obs, span, None)?
        .into_iter()
        .filter(|x| matches!(x.kind, SkyEventKind::Moonrise | SkyEventKind::Moonset))
        .map(|x| SkyEventItem {
            kind: x.kind.into(),
            utc: utc(&x.time),
        })
        .collect();
    Ok(LocalLunarView {
        verdict,
        totality_visible,
        track_altitude_deg: track,
        moon_events,
    })
}

/// 日食示意图。`tt_jd` 为搜索结果里该次日食的食甚（`EventItem.tt_jd`）。
pub fn solar_eclipse_diagram(
    engine: &Engine,
    tt_jd: f64,
    lang: Lang,
) -> anyhow::Result<SolarEclipseDiagram> {
    let e = find_solar_eclipse(engine, tt_jd, lang)?;
    solar_diagram(engine, &e, lang)
}

/// 按食甚的 TT 儒略日找回那次日食。
fn find_solar_eclipse(engine: &Engine, tt_jd: f64, lang: Lang) -> anyhow::Result<SolarEclipse> {
    solar_eclipse::search(&engine.eph, eclipse_span(tt_jd)?)?
        .into_iter()
        .min_by(|a, b| {
            (a.greatest.tt_jd() - tt_jd)
                .abs()
                .total_cmp(&(b.greatest.tt_jd() - tt_jd).abs())
        })
        .ok_or_else(|| anyhow::anyhow!("{}", lang.s("找不到这次日食", "Eclipse not found")))
}

fn solar_diagram(
    engine: &Engine,
    e: &SolarEclipse,
    lang: Lang,
) -> anyhow::Result<SolarEclipseDiagram> {
    let d = e.diagram(&engine.eph, DIAGRAM_STEP_S)?;
    let point = |p: &solar_eclipse::PlanePoint, label: &str| DiagramPoint {
        x: p.x,
        y: p.y,
        utc: utc(&p.time),
        label: label.to_string(),
    };
    Ok(SolarEclipseDiagram {
        track: d.track.iter().map(|p| point(p, "")).collect(),
        greatest: point(&d.greatest, lang.s("食甚", "Max")),
        penumbra_radius: d.l1,
        umbra_radius: d.l2,
        axis_declination_deg: d.d.to_degrees(),
    })
}

/// 某一时刻的太阳位置（度；高度含大气折射，方位从北向东量）。
#[derive(Debug, Clone, Copy)]
pub struct SunPoint {
    pub altitude_deg: f64,
    pub azimuth_deg: f64,
}

/// 本地日食的一个食相。
#[derive(Debug, Clone)]
pub struct SolarPhase {
    /// C1、C2、Max、C3、C4
    pub code: String,
    pub name: String,
    pub utc: String,
    pub sun: SunPoint,
}

/// 本地看到的日食类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalEclipseKind {
    Partial,
    Annular,
    Total,
}

/// 在观测地能看到多少（C1–C4 期间太阳是否在地平线上）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SolarVisibility {
    Full,
    /// 日出时已在食中
    Rises,
    /// 日落时仍在食中
    Sets,
    RisesAndSets,
    /// 食发生时太阳在地平线下
    Hidden,
    /// 这里不发生日食
    NoEclipse,
}

/// 太阳面模拟的一个取样点（角分）。偏移 x 向东、y 向北（天球上，抬头看时东在左）。
#[derive(Debug, Clone, Copy)]
pub struct SolarDiskPoint {
    /// 距 `track_start_utc` 的秒数
    pub seconds: f64,
    pub x_arcmin: f64,
    pub y_arcmin: f64,
    pub sun_radius_arcmin: f64,
    pub moon_radius_arcmin: f64,
    pub obscuration: f64,
    pub sun_altitude_deg: f64,
    /// 天顶方向的位置角（度，从北向东量）
    pub zenith_angle_deg: f64,
}

/// 观测地的日食情况。
#[derive(Debug, Clone)]
pub struct LocalSolarView {
    pub verdict: SolarVisibility,
    /// 这里不食时为空
    pub kind: Option<LocalEclipseKind>,
    /// 食分：全食、环食时为月日视直径比，偏食时为太阳直径被遮的比例
    pub magnitude: f64,
    /// 食面积：太阳圆面被遮的比例
    pub obscuration: f64,
    pub phases: Vec<SolarPhase>,
    /// 全食或环食的持续时间（秒）
    pub central_seconds: Option<f64>,
    /// 到中心线最近点的距离（km）和方向（度，从北向东量）；非中心食为空
    pub centerline_distance_km: Option<f64>,
    pub centerline_bearing_deg: Option<f64>,
    /// 太阳面模拟：C1 前 10 分钟到 C4 后 10 分钟，每 30 秒一个点，全食或环食阶段每 2 秒一个点
    pub track_start_utc: String,
    pub track: Vec<SolarDiskPoint>,
}

/// 日食详情页的全部数据。
#[derive(Debug, Clone)]
pub struct SolarEclipseDetail {
    pub diagram: SolarEclipseDiagram,
    /// 沙罗序列，如“136（第 38 次，共 71 次）”；星历范围外为空
    pub saros: String,
    /// 中心线（每分钟一个点）和各点的食带宽度（km）；非中心食为空
    pub central_line: Vec<GeoPoint>,
    pub path_width_km: Vec<f64>,
    pub greatest_point: Option<GeoPoint>,
    /// 全球最大食分栅格：第 0 行中心纬度 90 − step/2，第 0 列中心经度 −180 + step/2
    pub grid_step_deg: f64,
    pub grid_rows: u32,
    pub grid_cols: u32,
    pub grid: Vec<f32>,
    pub local: Option<LocalSolarView>,
}

/// 中心线取样间隔（秒）
const CENTRAL_LINE_STEP_S: f64 = 60.0;
/// 食分栅格的格子边长（度）和时间取样间隔（秒）
const GRID_STEP_DEG: f64 = 2.0;
const GRID_SAMPLE_S: f64 = 120.0;

/// 日食详情。`tt_jd` 为搜索结果里该次日食的食甚；`site` 为空时不算本地情况。
pub fn solar_eclipse_detail(
    engine: &Engine,
    tt_jd: f64,
    site: Option<Site>,
    lang: Lang,
) -> anyhow::Result<SolarEclipseDetail> {
    let eph = &engine.eph;
    let e = find_solar_eclipse(engine, tt_jd, lang)?;
    let diagram = solar_diagram(engine, &e, lang)?;
    let line = e.central_line(eph, CENTRAL_LINE_STEP_S)?;
    let grid = e.max_magnitude_grid(eph, GRID_STEP_DEG, GRID_SAMPLE_S)?;
    let local = match site {
        Some(s) => Some(local_solar_view(engine, &e, &line, s, lang)?),
        None => None,
    };
    Ok(SolarEclipseDetail {
        diagram,
        saros: saros::solar_saros(&e.greatest)
            .map(|s| saros_label(s, lang))
            .unwrap_or_default(),
        central_line: line
            .iter()
            .map(|p| geo((p.latitude_deg, p.longitude_deg)))
            .collect(),
        path_width_km: line.iter().map(|p| p.path_width_km).collect(),
        greatest_point: e
            .greatest_point
            .map(|p| geo((p.latitude_deg, p.longitude_deg))),
        grid_step_deg: grid.step_deg,
        grid_rows: grid.rows as u32,
        grid_cols: grid.cols as u32,
        grid: grid.values,
        local,
    })
}

/// 本地日食的食相名称，顺序：C1、C2、食甚、C3、C4。
fn solar_phase_name(l: Lang, i: usize) -> &'static str {
    const ZH: [&str; 5] = ["初亏", "食既", "食甚", "生光", "复圆"];
    const EN: [&str; 5] = [
        "First contact",
        "Second contact",
        "Maximum",
        "Third contact",
        "Fourth contact",
    ];
    match l {
        Lang::Zh => ZH[i],
        Lang::En => EN[i],
    }
}

/// 从 p 到 q 的初始方位角（度，从北向东量）。
fn bearing_deg(p: (f64, f64), q: (f64, f64)) -> f64 {
    let (la1, la2) = (p.0.to_radians(), q.0.to_radians());
    let dl = (q.1 - p.1).to_radians();
    let y = dl.sin() * la2.cos();
    let x = la1.cos() * la2.sin() - la1.sin() * la2.cos() * dl.cos();
    y.atan2(x).to_degrees().rem_euclid(360.0)
}

fn local_solar_view(
    engine: &Engine,
    e: &SolarEclipse,
    line: &[solar_eclipse::GroundPoint],
    site: Site,
    lang: Lang,
) -> anyhow::Result<LocalSolarView> {
    let eph = &engine.eph;
    let obs = Observer::from_degrees(site.latitude_deg, site.longitude_deg, site.height_m)?;
    let here = (site.latitude_deg, site.longitude_deg);

    // 到中心线最近点
    let pts: Vec<(f64, f64)> = line
        .iter()
        .map(|p| (p.latitude_deg, p.longitude_deg))
        .collect();
    let centerline_distance_km = distance_to_polyline_km(here, &pts);
    let centerline_bearing_deg = pts
        .iter()
        .min_by(|a, b| {
            let d =
                |q: &&(f64, f64)| distance_to_polyline_km(here, &[**q, **q]).unwrap_or(f64::MAX);
            d(a).total_cmp(&d(b))
        })
        .map(|q| bearing_deg(here, *q));

    let Some(lo) = local_eclipse::local_solar(eph, e, &obs, None)? else {
        return Ok(LocalSolarView {
            verdict: SolarVisibility::NoEclipse,
            kind: None,
            magnitude: 0.0,
            obscuration: 0.0,
            phases: Vec::new(),
            central_seconds: None,
            centerline_distance_km,
            centerline_bearing_deg,
            track_start_utc: String::new(),
            track: Vec::new(),
        });
    };
    let c = lo.contacts;
    let moments = [
        ("C1", c[0]),
        ("C2", c[1]),
        ("Max", Some(lo.maximum)),
        ("C3", c[2]),
        ("C4", c[3]),
    ];
    let mut phases = Vec::new();
    for (i, (code, t)) in moments.into_iter().enumerate() {
        let Some(t) = t else { continue };
        phases.push(SolarPhase {
            code: code.to_string(),
            name: solar_phase_name(lang, i).to_string(),
            utc: utc(&t),
            sun: SunPoint {
                altitude_deg: apparent_altitude(eph, Body::Sun, &t, &obs)?.to_degrees(),
                azimuth_deg: astrometry::topocentric(eph, Body::Sun, &t, &obs)?
                    .horizontal
                    .azimuth
                    .to_degrees(),
            },
        });
    }

    // 模拟轨迹的取样时刻
    let start = c[0].unwrap_or(lo.maximum).add_seconds(-600.0);
    let end = c[3].unwrap_or(lo.maximum).add_seconds(600.0);
    let mut secs: Vec<f64> = Vec::new();
    let total = end.tt_seconds() - start.tt_seconds();
    let mut x = 0.0;
    while x <= total {
        secs.push(x);
        x += 30.0;
    }
    if let (Some(a), Some(b)) = (c[1], c[2]) {
        let (a, b) = (
            a.tt_seconds() - start.tt_seconds(),
            b.tt_seconds() - start.tt_seconds(),
        );
        let mut x = a;
        while x < b {
            secs.push(x);
            x += 2.0;
        }
    }
    for t in c.iter().flatten().chain([&lo.maximum]) {
        secs.push(t.tt_seconds() - start.tt_seconds());
    }
    secs.sort_by(f64::total_cmp);
    secs.dedup_by(|a, b| (*a - *b).abs() < 0.5);
    let times: Vec<Time> = secs.iter().map(|s| start.add_seconds(*s)).collect();
    let arcmin = |r: f64| r.to_degrees() * 60.0;
    let track: Vec<SolarDiskPoint> = local_eclipse::solar_disk_views(eph, &obs, &times)?
        .iter()
        .zip(&secs)
        .map(|(v, s)| SolarDiskPoint {
            seconds: *s,
            x_arcmin: arcmin(v.x),
            y_arcmin: arcmin(v.y),
            sun_radius_arcmin: arcmin(v.sun_radius),
            moon_radius_arcmin: arcmin(v.moon_radius),
            obscuration: v.obscuration,
            sun_altitude_deg: v.sun_altitude_deg,
            zenith_angle_deg: v.zenith_angle.to_degrees(),
        })
        .collect();

    // C1–C4 期间太阳在地平线上的情况
    let (a, b) = (
        c[0].map_or(0.0, |t| t.tt_seconds() - start.tt_seconds()),
        c[3].map_or(total, |t| t.tt_seconds() - start.tt_seconds()),
    );
    let up: Vec<bool> = track
        .iter()
        .filter(|p| p.seconds >= a - 0.5 && p.seconds <= b + 0.5)
        .map(|p| p.sun_altitude_deg > 0.0)
        .collect();
    let verdict = match (
        up.first(),
        up.last(),
        up.iter().any(|u| *u),
        up.iter().all(|u| *u),
    ) {
        (_, _, _, true) => SolarVisibility::Full,
        (_, _, false, _) => SolarVisibility::Hidden,
        (Some(false), Some(true), _, _) => SolarVisibility::Rises,
        (Some(true), Some(false), _, _) => SolarVisibility::Sets,
        _ => SolarVisibility::RisesAndSets,
    };
    Ok(LocalSolarView {
        verdict,
        kind: Some(match lo.kind {
            local_eclipse::LocalSolarKind::Partial => LocalEclipseKind::Partial,
            local_eclipse::LocalSolarKind::Annular => LocalEclipseKind::Annular,
            local_eclipse::LocalSolarKind::Total => LocalEclipseKind::Total,
        }),
        magnitude: lo.magnitude,
        obscuration: lo.obscuration,
        phases,
        central_seconds: lo.central_duration_s(),
        centerline_distance_km,
        centerline_bearing_deg,
        track_start_utc: utc_ms(&start),
        track,
    })
}

/// 出没、晨昏事件的类型（与 core 的 `SkyEventKind` 一一对应）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SkyKind {
    AstronomicalDawn,
    NauticalDawn,
    CivilDawn,
    Sunrise,
    Sunset,
    CivilDusk,
    NauticalDusk,
    AstronomicalDusk,
    Moonrise,
    Moonset,
}

impl From<SkyEventKind> for SkyKind {
    fn from(k: SkyEventKind) -> Self {
        match k {
            SkyEventKind::AstronomicalDawn => SkyKind::AstronomicalDawn,
            SkyEventKind::NauticalDawn => SkyKind::NauticalDawn,
            SkyEventKind::CivilDawn => SkyKind::CivilDawn,
            SkyEventKind::Sunrise => SkyKind::Sunrise,
            SkyEventKind::Sunset => SkyKind::Sunset,
            SkyEventKind::CivilDusk => SkyKind::CivilDusk,
            SkyEventKind::NauticalDusk => SkyKind::NauticalDusk,
            SkyEventKind::AstronomicalDusk => SkyKind::AstronomicalDusk,
            SkyEventKind::Moonrise => SkyKind::Moonrise,
            SkyEventKind::Moonset => SkyKind::Moonset,
        }
    }
}

/// 一次出没或晨昏，时刻为 UTC（"2026-11-07 09:12:34"）。
#[derive(Debug, Clone)]
pub struct SkyEventItem {
    pub kind: SkyKind,
    pub utc: String,
}

/// 月相。
#[derive(Debug, Clone)]
pub struct MoonInfo {
    /// 照亮比例 0–1
    pub illuminated_fraction: f64,
    /// 上半月（新月到满月）
    pub waxing: bool,
    /// 月相名称：新月、娥眉月、上弦月、盈凸月、满月、亏凸月、下弦月、残月
    pub phase_name: String,
    /// 下次朔、望（UTC），找不到时为空字符串
    pub next_new_utc: String,
    pub next_full_utc: String,
}

/// 看板“今晚”卡片的数据。
#[derive(Debug, Clone)]
pub struct Tonight {
    /// 时间窗口内的出没和晨昏，按时间排序
    pub events: Vec<SkyEventItem>,
    /// 窗口开始时的太阳中心高度（度）。窗口内没有日出日落时，用它区分极昼（> 0）和极夜
    pub sun_altitude_deg: f64,
    /// 窗口开始时的月相
    pub moon: MoonInfo,
}

/// 月相名称（按日月视黄经差分八段）。
fn moon_phase_name(lon_diff_deg: f64, lang: Lang) -> &'static str {
    let names = [
        ("新月", "New moon"),
        ("娥眉月", "Waxing crescent"),
        ("上弦月", "First quarter"),
        ("盈凸月", "Waxing gibbous"),
        ("满月", "Full moon"),
        ("亏凸月", "Waning gibbous"),
        ("下弦月", "Last quarter"),
        ("残月", "Waning crescent"),
    ];
    let i = (((lon_diff_deg + 22.5).rem_euclid(360.0)) / 45.0) as usize % 8;
    lang.s(names[i].0, names[i].1)
}

/// 某地在 `[start_utc, start_utc + hours]` 内的日月出没、晨昏，以及开始时刻的月相。
///
/// `start_utc` 形如 "2026-11-07T04:00:00"。界面传本地中午对应的 UTC、`hours` = 24，得到“今晚”。
pub fn tonight(
    engine: &Engine,
    latitude_deg: f64,
    longitude_deg: f64,
    height_m: f64,
    start_utc: String,
    hours: f64,
    lang: Lang,
) -> anyhow::Result<Tonight> {
    anyhow::ensure!(hours > 0.0 && hours <= 72.0, "hours = {hours}");
    let obs = Observer::from_degrees(latitude_deg, longitude_deg, height_m)?;
    let start = Time::from_utc(&start_utc.trim().parse::<DateTime>()?)?;
    let span = Span::new(start, start.add_seconds(hours * 3600.0))?;
    let eph = &engine.eph;

    let events = almanac::rise_set_twilight(eph, &obs, span, None)?
        .into_iter()
        .map(|e| SkyEventItem {
            kind: e.kind.into(),
            utc: utc(&e.time),
        })
        .collect();
    let phase = almanac::moon_phase(eph, &start)?;
    let next = |aspect| -> anyhow::Result<String> {
        Ok(almanac::next_lunar_phase(eph, &start, aspect)?
            .map(|t| utc(&t))
            .unwrap_or_default())
    };
    Ok(Tonight {
        events,
        sun_altitude_deg: almanac::sun_altitude(eph, &obs, &start)?.to_degrees(),
        moon: MoonInfo {
            illuminated_fraction: phase.illuminated_fraction,
            waxing: phase.waxing(),
            phase_name: moon_phase_name(phase.longitude_difference.to_degrees(), lang).to_string(),
            next_new_utc: next(Aspect::Conjunction)?,
            next_full_utc: next(Aspect::Opposition)?,
        },
    })
}

/// 范围搜索时，按这个最低卫星距离（km）把半径换算成角距门槛：地面上相距 R 的两点看卫星，
/// 视差约为 R / 距离，距离不会小于卫星高度。取偏低的值，宁可多找候选再按中心线距离筛掉。
const RADIUS_MIN_RANGE_KM: f64 = 300.0;
/// 范围搜索时角距门槛的上限（度）。
const RADIUS_MAX_SEPARATION_DEG: f64 = 15.0;

/// 搜索卫星凌日、凌月。
///
/// `start_utc` 形如 "2026-11-06T12:00:00"，空字符串表示从根数历元开始。
/// `previous_omm_json` 为上一份根数（可为空），用于比较新旧预报。
/// `radius_km` > 0 时做范围搜索：除了在测站角距不超过 `max_separation_deg` 的接近，还返回地面中心线
/// 经过测站 `radius_km` 以内的事件（到中心线上可以看到凌日凌月）。单次最多 14 天，更长的跨度分段调用。
#[allow(clippy::too_many_arguments)]
pub fn satellite_transits(
    engine: &Engine,
    omm_json: String,
    previous_omm_json: Option<String>,
    latitude_deg: f64,
    longitude_deg: f64,
    height_m: f64,
    start_utc: String,
    days: f64,
    max_separation_deg: f64,
    radius_km: f64,
    lang: Lang,
) -> anyhow::Result<Vec<SatTransitItem>> {
    anyhow::ensure!(
        days > 0.0 && days <= 14.0,
        "{}",
        lang.s(
            "搜索天数应在 0–14 天之间",
            "The number of days must be between 0 and 14"
        )
    );
    let obs = Observer::from_degrees(latitude_deg, longitude_deg, height_m)?;
    let sats = Satellite::from_omm_json(&omm_json)?;
    let previous = match previous_omm_json.as_deref() {
        Some(s) if !s.trim().is_empty() => Satellite::from_omm_json(s).unwrap_or_default(),
        _ => Vec::new(),
    };
    anyhow::ensure!(
        (0.0..=500.0).contains(&radius_km),
        "{}",
        lang.s(
            "范围半径应在 0–500 km 之间",
            "The radius must be between 0 and 500 km"
        )
    );
    let bodies = [Body::Sun, Body::Moon];
    let max = max_separation_deg.to_radians();
    // 范围搜索放宽角距门槛，找到候选后再按中心线距离筛选
    let search_max = if radius_km > 0.0 {
        max.max(
            (radius_km / RADIUS_MIN_RANGE_KM)
                .atan()
                .min(RADIUS_MAX_SEPARATION_DEG.to_radians()),
        )
    } else {
        max
    };
    let keep = |e: &SatTransit| {
        e.min_separation <= max || (radius_km > 0.0 && e.distance_to_centerline_km <= radius_km)
    };
    let mut out = Vec::new();
    for sat in &sats {
        let start = if start_utc.trim().is_empty() {
            sat.epoch
        } else {
            Time::from_utc(&start_utc.trim().parse::<DateTime>()?)?
        };
        let span = Span::new(start, start.add_seconds(days * 86_400.0))?;
        let found: Vec<_> =
            sat_transit::search(&engine.eph, sat, &bodies, span, &obs, search_max, None)?
                .into_iter()
                .filter(keep)
                .collect();
        // 同一历元的根数不用比较
        let old = match previous.iter().find(|p| p.norad_id == sat.norad_id) {
            Some(p) if (p.epoch.tt_seconds() - sat.epoch.tt_seconds()).abs() > 1.0 => Some(
                sat_transit::search(&engine.eph, p, &bodies, span, &obs, search_max, None)?,
            ),
            _ => None,
        };
        for e in found {
            out.push(sat_item(&e, old.as_deref(), lang));
        }
    }
    out.sort_by(|a, b| a.tt_jd.total_cmp(&b.tt_jd));
    Ok(out)
}

fn geo(p: (f64, f64)) -> GeoPoint {
    GeoPoint {
        latitude_deg: p.0,
        longitude_deg: p.1,
    }
}

/// 点到折线的近似距离（km）：在点附近按等距圆柱投影成平面计算。
fn distance_to_polyline_km(p: (f64, f64), line: &[(f64, f64)]) -> Option<f64> {
    const R: f64 = 6371.0;
    let k = p.0.to_radians().cos();
    let xy = |q: (f64, f64)| {
        let dlon = (q.1 - p.1 + 540.0).rem_euclid(360.0) - 180.0;
        (dlon.to_radians() * k * R, (q.0 - p.0).to_radians() * R)
    };
    line.windows(2)
        .map(|w| {
            let (a, b) = (xy(w[0]), xy(w[1]));
            let (dx, dy) = (b.0 - a.0, b.1 - a.1);
            let len2 = dx * dx + dy * dy;
            let t = if len2 > 0.0 {
                (-(a.0 * dx + a.1 * dy) / len2).clamp(0.0, 1.0)
            } else {
                0.0
            };
            (a.0 + t * dx).hypot(a.1 + t * dy)
        })
        .min_by(f64::total_cmp)
}

fn sat_item(e: &SatTransit, old: Option<&[SatTransit]>, l: Lang) -> SatTransitItem {
    let is_transit = e.is_transit();
    let sun = e.body == Body::Sun;
    let what = match (l, sun, is_transit) {
        (Lang::Zh, true, true) => "凌日",
        (Lang::Zh, false, true) => "凌月",
        (Lang::Zh, true, false) => "近日（未凌）",
        (Lang::Zh, false, false) => "近月（未凌）",
        (Lang::En, true, true) => "transits the Sun",
        (Lang::En, false, true) => "transits the Moon",
        (Lang::En, true, false) => "passes near the Sun",
        (Lang::En, false, false) => "passes near the Moon",
    };
    let arcmin = |r: f64| r.to_degrees() * 60.0;

    // 旧根数里 120 秒内的同一天体事件视为同一事件
    let matched = old.and_then(|v| {
        v.iter()
            .filter(|o| o.body == e.body)
            .map(|o| (o, (o.closest.tt_seconds() - e.closest.tt_seconds()).abs()))
            .filter(|(_, dt)| *dt < 120.0)
            .min_by(|a, b| a.1.total_cmp(&b.1))
            .map(|(o, _)| o)
    });
    let previous_shift_s = matched.map(|o| e.closest.tt_seconds() - o.closest.tt_seconds());
    let previous_shift_km =
        matched.and_then(|o| distance_to_polyline_km(o.centerline_nearest, &e.centerline));

    let mut warnings = Vec::new();
    let age = e.elements_age_days.abs();
    if age > WARN_AGE_DAYS {
        warnings.push(match l {
            Lang::Zh => format!(
                "根数龄期 {age:.1} 天，预报误差可能达到数秒、数公里，请在观测前刷新根数。"
            ),
            Lang::En => format!(
                "The elements are {age:.1} days old; the prediction may be off by seconds and kilometres. Refresh before observing."
            ),
        });
    }
    if old.is_some() && matched.is_none() {
        warnings.push(
            l.s(
                "旧根数预报中没有这次事件，属于新出现的预报。",
                "This event was not in the prediction from the previous elements.",
            )
            .to_string(),
        );
    }
    if let Some(dt) = previous_shift_s.filter(|d| d.abs() > WARN_SHIFT_S) {
        warnings.push(match l {
            Lang::Zh => format!("与上一份根数相比，时刻变化 {dt:+.1} 秒。"),
            Lang::En => {
                format!("The time moved by {dt:+.1} s compared with the previous elements.")
            }
        });
    }
    if let Some(km) = previous_shift_km.filter(|d| *d > WARN_SHIFT_KM) {
        warnings.push(match l {
            Lang::Zh => format!("与上一份根数相比，中心线移动 {km:.1} km。"),
            Lang::En => {
                format!("The centre line moved by {km:.1} km compared with the previous elements.")
            }
        });
    }

    let body_name = l.body(e.body);
    // 这段时间卫星与日月的连线落不到地面上时，core 给出的中心线距离为无穷大
    let has_line = e.distance_to_centerline_km.is_finite();
    let mut details = vec![
        detail(l.s("最近时刻（UTC）", "Closest (UTC)"), utc_ms(&e.closest)),
        detail(
            l.s("最小角距", "Minimum separation"),
            match l {
                Lang::Zh => format!(
                    "{:.2}′（{body_name}视半径 {:.2}′）",
                    arcmin(e.min_separation),
                    arcmin(e.body_semidiameter)
                ),
                Lang::En => format!(
                    "{:.2}′ ({body_name} radius {:.2}′)",
                    arcmin(e.min_separation),
                    arcmin(e.body_semidiameter)
                ),
            },
        ),
    ];
    if let Some(d) = e.duration_s {
        details.push(detail(
            l.s("穿越历时", "Transit duration"),
            format!("{d:.2} s"),
        ));
    }
    details.extend([
        detail(l.s("卫星距离", "Range"), format!("{:.0} km", e.range_km)),
        detail(
            l.s("高度 / 方位", "Altitude / azimuth"),
            format!("{:.1}° / {:.1}°", e.altitude_deg, e.azimuth_deg),
        ),
        detail(
            l.s("离中心线", "Distance to centre line"),
            match (l, has_line) {
                (_, false) => l
                    .s(
                        "中心线这段时间不落在地面上",
                        "The centre line does not reach the ground",
                    )
                    .to_string(),
                (Lang::Zh, true) => format!(
                    "{:.2} km（可见带半宽约 {:.2} km）",
                    e.distance_to_centerline_km, e.band_half_width_km
                ),
                (Lang::En, true) => format!(
                    "{:.2} km (visibility half-width ≈ {:.2} km)",
                    e.distance_to_centerline_km, e.band_half_width_km
                ),
            },
        ),
    ]);
    if has_line {
        details.push(detail(
            l.s("中心线最近点", "Nearest centre-line point"),
            format!(
                "{:.4}°, {:.4}°",
                e.centerline_nearest.0, e.centerline_nearest.1
            ),
        ));
    }
    details.extend([detail(
        l.s("根数龄期", "Elements age"),
        match l {
            Lang::Zh => format!("{:.1} 天", e.elements_age_days),
            Lang::En => format!("{:.1} days", e.elements_age_days),
        },
    )]);
    if let Some(dt) = previous_shift_s {
        details.push(detail(
            l.s("与旧根数相比（时刻）", "Change vs previous (time)"),
            format!("{dt:+.2} s"),
        ));
    }
    if let Some(km) = previous_shift_km {
        details.push(detail(
            l.s("与旧根数相比（中心线）", "Change vs previous (centre line)"),
            format!("{km:.2} km"),
        ));
    }
    if sun {
        details.push(detail(l.s("安全提示", "Safety"), sun_safety_notice(l)));
    }

    SatTransitItem {
        norad_id: e.norad_id,
        satellite: e.satellite.clone(),
        body: e.body.name().to_string(),
        is_transit,
        title: match l {
            Lang::Zh => format!("{} {what}", e.satellite),
            Lang::En => format!("{} {what}", e.satellite),
        },
        utc: utc(&e.closest),
        tt_jd: e.closest.tt_jd(),
        summary: match (l, has_line) {
            (Lang::Zh, true) => format!(
                "角距 {:.2}′，离中心线 {:.1} km",
                arcmin(e.min_separation),
                e.distance_to_centerline_km
            ),
            (Lang::En, true) => format!(
                "Separation {:.2}′, {:.1} km from centre line",
                arcmin(e.min_separation),
                e.distance_to_centerline_km
            ),
            (Lang::Zh, false) => format!("角距 {:.2}′", arcmin(e.min_separation)),
            (Lang::En, false) => format!("Separation {:.2}′", arcmin(e.min_separation)),
        },
        details,
        distance_to_centerline_km: e.distance_to_centerline_km,
        band_half_width_km: e.band_half_width_km,
        elements_age_days: e.elements_age_days,
        centerline: e.centerline.iter().copied().map(geo).collect(),
        centerline_nearest: geo(e.centerline_nearest),
        previous_shift_s,
        previous_shift_km,
        warning: (!warnings.is_empty()).then(|| warnings.join("\n")),
    }
}

/// 精确到毫秒的 UTC。
fn utc_ms(t: &Time) -> String {
    t.to_utc()
        .map(|d| d.to_string()[..23].replace('T', " "))
        .unwrap_or_else(|_| format!("TT JD {:.7}", t.tt_jd()))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 测试用星历：`GUANXIANG_EPHEM` 或仓库根目录的 data/de440s.bsp；找不到时跳过（CI 不允许跳过）。
    fn test_engine() -> Option<Engine> {
        let path = std::env::var_os("GUANXIANG_EPHEM")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| {
                std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../data/de440s.bsp")
            });
        if !path.exists() {
            eprintln!("跳过：找不到 {}", path.display());
            return None;
        }
        Some(Engine::from_bytes(std::fs::read(path).unwrap()).unwrap())
    }

    /// 按食甚的 TT 儒略日找回日月食并给出示意图数据
    #[test]
    fn eclipse_diagrams_by_tt_jd() {
        let Some(engine) = test_engine() else { return };
        // 2025-09-07 月全食，食甚约 18:11 UTC
        let l = lunar_eclipse_diagram(&engine, 2_460_926.259, Lang::Zh).unwrap();
        let labels: Vec<&str> = l.marks.iter().map(|m| m.label.as_str()).collect();
        assert_eq!(labels, ["P1", "U1", "U2", "U3", "U4", "P4", "食甚"]);
        assert!(l.marks.last().unwrap().utc.starts_with("2025-09-07 18:1"));
        // 2027-08-02 日全食，食甚约 10:07 UTC
        let s = solar_eclipse_diagram(&engine, 2_461_619.923, Lang::En).unwrap();
        assert!(
            s.greatest.utc.starts_with("2027-08-02 10:0"),
            "{}",
            s.greatest.utc
        );
        assert!(s.umbra_radius < 0.0 && s.track.len() > 20);
    }

    /// 2025-09-07 月全食：北京全程可见，伦敦月出时已在食中，纽约看不到
    #[test]
    fn lunar_eclipse_detail_2025_09_07() {
        let Some(engine) = test_engine() else { return };
        let beijing = Site {
            latitude_deg: 39.9042,
            longitude_deg: 116.4074,
            height_m: 44.0,
        };
        let d = lunar_eclipse_detail(&engine, 2_460_926.259, Some(beijing), Lang::Zh).unwrap();
        let codes: Vec<&str> = d.phases.iter().map(|p| p.code.as_str()).collect();
        assert_eq!(codes, ["P1", "U1", "U2", "Max", "U3", "U4", "P4"]);
        assert_eq!(d.saros, "128（第 41 次，共 71 次）");
        // NASA：半影 326.7、本影 209.4、全食 82.1 分钟
        assert!((d.total_minutes.unwrap() - 82.1).abs() < 0.5);
        assert!((d.partial_minutes.unwrap() - 209.4).abs() < 0.5);
        assert!((d.penumbral_minutes - 326.7).abs() < 0.5);
        // NASA 星表：食甚时月亮在 6°S、87°E 的天顶
        let max = &d.phases[3];
        assert!((max.sublunar.latitude_deg + 6.0).abs() < 1.0);
        assert!(
            (max.sublunar.longitude_deg - 87.0).abs() < 1.0,
            "{:?}",
            max.sublunar
        );
        let local = d.local.unwrap();
        assert_eq!(local.verdict, LunarVisibility::Full);
        assert!(local.totality_visible);
        assert_eq!(local.track_altitude_deg.len(), d.diagram.path.len());
        assert!(max.horizon.unwrap().moon_altitude_deg > 20.0);

        // 伦敦：月出约 18:30 UTC，晚于初亏（16:27），月出时已在食中
        let london = Site {
            latitude_deg: 51.5074,
            longitude_deg: -0.1278,
            height_m: 11.0,
        };
        let d = lunar_eclipse_detail(&engine, 2_460_926.259, Some(london), Lang::En).unwrap();
        let v = d.local.unwrap();
        assert_eq!(v.verdict, LunarVisibility::Rises);
        assert!(v.moon_events.iter().any(|e| e.kind == SkyKind::Moonrise));
        // 纽约：全程在地平线以下
        let new_york = Site {
            latitude_deg: 40.7128,
            longitude_deg: -74.006,
            height_m: 10.0,
        };
        let d = lunar_eclipse_detail(&engine, 2_460_926.259, Some(new_york), Lang::En).unwrap();
        assert_eq!(d.local.unwrap().verdict, LunarVisibility::Hidden);
        assert!(lunar_eclipse_detail(&engine, 2_460_926.259, None, Lang::En)
            .unwrap()
            .local
            .is_none());
    }

    /// 2027-08-02 日全食：卢克索全食约 6 分 20 秒、伦敦偏食、北京不食
    #[test]
    fn solar_eclipse_detail_2027_08_02() {
        let Some(engine) = test_engine() else { return };
        let site = |lat, lon| Site {
            latitude_deg: lat,
            longitude_deg: lon,
            height_m: 0.0,
        };
        let d = solar_eclipse_detail(
            &engine,
            2_461_619.922,
            Some(site(25.6872, 32.6396)),
            Lang::Zh,
        )
        .unwrap();
        assert_eq!(d.saros, "136（第 38 次，共 71 次）");
        assert!(d.central_line.len() > 100);
        assert_eq!(d.central_line.len(), d.path_width_km.len());
        assert_eq!(d.grid.len(), (d.grid_rows * d.grid_cols) as usize);
        let v = d.local.unwrap();
        assert_eq!(v.kind, Some(LocalEclipseKind::Total));
        assert_eq!(v.verdict, SolarVisibility::Full);
        let codes: Vec<&str> = v.phases.iter().map(|p| p.code.as_str()).collect();
        assert_eq!(codes, ["C1", "C2", "Max", "C3", "C4"]);
        // NASA：卢克索附近全食约 6 分 20 秒
        let dur = v.central_seconds.unwrap();
        assert!((dur - 380.0).abs() < 15.0, "{dur}");
        assert!(v.centerline_distance_km.unwrap() < 30.0);
        // 轨迹按时间排列，全食阶段食面积为 1
        assert!(v.track.windows(2).all(|w| w[0].seconds < w[1].seconds));
        assert!(v.track.iter().any(|p| p.obscuration > 0.9999));

        let d = solar_eclipse_detail(
            &engine,
            2_461_619.922,
            Some(site(51.5074, -0.1278)),
            Lang::En,
        )
        .unwrap();
        let v = d.local.unwrap();
        assert_eq!(v.kind, Some(LocalEclipseKind::Partial));
        assert!(v.central_seconds.is_none());
        // 伦敦在中心线以南方向（食带经过直布罗陀海峡）
        let b = v.centerline_bearing_deg.unwrap();
        assert!((120.0..240.0).contains(&b), "{b}");

        let d = solar_eclipse_detail(&engine, 2_461_619.922, Some(site(39.9, 116.4)), Lang::Zh)
            .unwrap();
        assert_eq!(d.local.unwrap().verdict, SolarVisibility::NoEclipse);
    }

    #[test]
    fn moon_phase_names() {
        assert_eq!(moon_phase_name(0.0, Lang::Zh), "新月");
        assert_eq!(moon_phase_name(350.0, Lang::Zh), "新月");
        assert_eq!(moon_phase_name(90.0, Lang::Zh), "上弦月");
        assert_eq!(moon_phase_name(180.0, Lang::En), "Full moon");
        assert_eq!(moon_phase_name(270.0, Lang::Zh), "下弦月");
        assert_eq!(moon_phase_name(330.0, Lang::Zh), "残月");
    }

    /// 北京一晚（本地中午起 24 小时）：日落、晨昏、日出按顺序各出现一次，月相数据齐全。
    #[test]
    fn tonight_in_beijing() {
        let Some(engine) = test_engine() else { return };
        // 2026-11-07 12:00 北京时间 = 04:00 UTC
        let t = tonight(
            &engine,
            39.9042,
            116.4074,
            44.0,
            "2026-11-07T04:00:00".into(),
            24.0,
            Lang::Zh,
        )
        .unwrap();
        let suns: Vec<SkyKind> = t
            .events
            .iter()
            .map(|e| e.kind)
            .filter(|k| !matches!(k, SkyKind::Moonrise | SkyKind::Moonset))
            .collect();
        assert_eq!(
            suns,
            [
                SkyKind::Sunset,
                SkyKind::CivilDusk,
                SkyKind::NauticalDusk,
                SkyKind::AstronomicalDusk,
                SkyKind::AstronomicalDawn,
                SkyKind::NauticalDawn,
                SkyKind::CivilDawn,
                SkyKind::Sunrise,
            ]
        );
        // 北京 11 月上旬日落约 17:04（09:04 UTC）
        let sunset = &t
            .events
            .iter()
            .find(|e| e.kind == SkyKind::Sunset)
            .unwrap()
            .utc;
        assert!(sunset.starts_with("2026-11-07 09:0"), "{sunset}");
        assert!(t.sun_altitude_deg > 0.0);
        assert!((0.0..=1.0).contains(&t.moon.illuminated_fraction));
        assert!(!t.moon.next_new_utc.is_empty() && !t.moon.next_full_utc.is_empty());
    }

    #[test]
    fn radius_search_adds_nearby_centerlines() {
        let Some(engine) = test_engine() else { return };
        let omm = std::fs::read_to_string(
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../crates/guanxiang-core/tests/fixtures/satellite/omm_iss_css.json"),
        )
        .unwrap();
        let run = |radius: f64| {
            satellite_transits(
                &engine,
                omm.clone(),
                None,
                39.9,
                116.4,
                50.0,
                String::new(),
                14.0,
                1.0,
                radius,
                Lang::Zh,
            )
            .unwrap()
        };
        let base = run(0.0);
        let wide = run(150.0);
        // 普通搜索的结果都在范围搜索里
        for b in &base {
            assert!(
                wide.iter().any(|w| (w.tt_jd - b.tt_jd).abs() < 1e-9),
                "范围搜索漏掉了 {}",
                b.utc
            );
        }
        // 多出来的都是中心线在半径内经过的
        let extra: Vec<_> = wide
            .iter()
            .filter(|w| !base.iter().any(|b| (w.tt_jd - b.tt_jd).abs() < 1e-9))
            .collect();
        assert!(!extra.is_empty(), "14 天内 150 km 范围应该能找到更多事件");
        for w in &extra {
            assert!(w.distance_to_centerline_km <= 150.0, "{}", w.utc);
        }
        eprintln!(
            "普通 {} 个，范围 150 km {} 个，其中凌日凌月 {} 个",
            base.len(),
            wide.len(),
            wide.iter().filter(|w| w.is_transit).count()
        );
        // 半径超出范围要报错
        assert!(satellite_transits(
            &engine,
            omm.clone(),
            None,
            39.9,
            116.4,
            50.0,
            String::new(),
            1.0,
            1.0,
            501.0,
            Lang::Zh
        )
        .is_err());
    }

    #[test]
    fn polyline_distance() {
        // 沿赤道的线，点在其北 0.1°（约 11.1 km）
        let line = [(0.0, -1.0), (0.0, 0.0), (0.0, 1.0)];
        let d = distance_to_polyline_km((0.1, 0.5), &line).unwrap();
        assert!((d - 11.12).abs() < 0.05, "{d}");
        // 跨 180° 经线
        let line = [(10.0, 179.5), (10.0, -179.5)];
        let d = distance_to_polyline_km((10.0, 180.0), &line).unwrap();
        assert!(d < 1e-6, "{d}");
    }

    #[test]
    fn english_names_match_named_stars() {
        // 每颗有中文名的星都要有英文名，反之亦然
        for s in stars::catalog() {
            assert_eq!(
                s.name.is_some(),
                star_name_en(s.hip).is_some(),
                "HIP {} 的中英文名不对应",
                s.hip
            );
        }
        assert_eq!(Lang::En.body(Body::Jupiter), "Jupiter");
        assert_eq!(Lang::Zh.body(Body::Jupiter), "木星");
    }
}
