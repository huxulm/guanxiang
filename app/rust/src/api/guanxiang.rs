//! Flutter 调用的 API。
//!
//! 桥接层保持很薄（D6）：只把 core 的结果整理成适合界面显示的结构，并负责进度回传和取消。
//! 搜索按年分块执行，每块结束后回传进度、检查取消标志，core 不需要知道进度和取消。
//! 显示文字按 [`Lang`] 输出中文或英文（M7）。

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use flutter_rust_bridge::frb;
use guanxiang_core::events::local_eclipse::{self, LocalSolarKind};
use guanxiang_core::events::longitude::{self, Aspect};
use guanxiang_core::events::lunar_eclipse::{self, LunarEclipseKind, ShadowModel};
use guanxiang_core::events::occultation::{self, Target};
use guanxiang_core::events::sat_transit::{self, SatTransit};
use guanxiang_core::events::solar_eclipse::{self, SolarEclipseKind};
use guanxiang_core::events::visibility::{apparent_altitude, VisibilityFilter};
use guanxiang_core::events::{separation, transit, Span};
use guanxiang_core::satellite::Satellite;
use guanxiang_core::stars::Star;
use guanxiang_core::{stars, AniseEphemeris, Body, DateTime, Observer, Time};

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
                    detail("γ", format!("{:+.4}", e.gamma)),
                    detail(
                        l.s("食分（全球）", "Magnitude"),
                        format!("{:.4}", e.magnitude),
                    ),
                ];
                if let Some(p) = e.greatest_point {
                    details.push(detail(
                        l.s("食甚点", "Point of greatest eclipse"),
                        format!("{:.2}°, {:.2}°", p.latitude_deg, p.longitude_deg),
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
                    detail("γ", format!("{:+.4}", e.gamma)),
                    detail(
                        l.s("半影食分", "Penumbral magnitude"),
                        format!("{:.4}", e.penumbral_magnitude),
                    ),
                    detail(
                        l.s("本影食分", "Umbral magnitude"),
                        format!("{:.4}", e.umbral_magnitude),
                    ),
                ];
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
                    title: name.to_string(),
                    utc: utc(&e.greatest),
                    tt_jd: e.greatest.tt_jd(),
                    summary: format!(
                        "{} {:.3}",
                        l.s("本影食分", "Umbral magnitude"),
                        e.umbral_magnitude
                    ),
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

/// 搜索卫星凌日、凌月。
///
/// `start_utc` 形如 "2026-11-06T12:00:00"，空字符串表示从根数历元开始。
/// `previous_omm_json` 为上一份根数（可为空），用于比较新旧预报。
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
    let bodies = [Body::Sun, Body::Moon];
    let max = max_separation_deg.to_radians();
    let mut out = Vec::new();
    for sat in &sats {
        let start = if start_utc.trim().is_empty() {
            sat.epoch
        } else {
            Time::from_utc(&start_utc.trim().parse::<DateTime>()?)?
        };
        let span = Span::new(start, start.add_seconds(days * 86_400.0))?;
        let found = sat_transit::search(&engine.eph, sat, &bodies, span, &obs, max, None)?;
        // 同一历元的根数不用比较
        let old = match previous.iter().find(|p| p.norad_id == sat.norad_id) {
            Some(p) if (p.epoch.tt_seconds() - sat.epoch.tt_seconds()).abs() > 1.0 => Some(
                sat_transit::search(&engine.eph, p, &bodies, span, &obs, max, None)?,
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
            match l {
                Lang::Zh => format!(
                    "{:.2} km（可见带半宽约 {:.2} km）",
                    e.distance_to_centerline_km, e.band_half_width_km
                ),
                Lang::En => format!(
                    "{:.2} km (visibility half-width ≈ {:.2} km)",
                    e.distance_to_centerline_km, e.band_half_width_km
                ),
            },
        ),
        detail(
            l.s("中心线最近点", "Nearest centre-line point"),
            format!(
                "{:.4}°, {:.4}°",
                e.centerline_nearest.0, e.centerline_nearest.1
            ),
        ),
        detail(
            l.s("根数龄期", "Elements age"),
            match l {
                Lang::Zh => format!("{:.1} 天", e.elements_age_days),
                Lang::En => format!("{:.1} days", e.elements_age_days),
            },
        ),
    ]);
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
        summary: match l {
            Lang::Zh => format!(
                "角距 {:.2}′，离中心线 {:.1} km",
                arcmin(e.min_separation),
                e.distance_to_centerline_km
            ),
            Lang::En => format!(
                "Separation {:.2}′, {:.1} km from centre line",
                arcmin(e.min_separation),
                e.distance_to_centerline_km
            ),
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
