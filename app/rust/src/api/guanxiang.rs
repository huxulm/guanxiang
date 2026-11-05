//! Flutter 调用的 API。
//!
//! 桥接层保持很薄（D6）：只把 core 的结果整理成适合界面显示的结构，并负责进度回传和取消。
//! 搜索按年分块执行，每块结束后回传进度、检查取消标志，core 不需要知道进度和取消。

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
use guanxiang_core::{stars, AniseEphemeris, Body, DateTime, Observer, Time};

use crate::frb_generated::StreamSink;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
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

    /// 星历覆盖的年份范围（取月球的覆盖范围）。
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

/// 支持的天体，供界面列出：(英文名, 中文名)。
#[frb(sync)]
pub fn body_names() -> Vec<Detail> {
    Body::ALL
        .iter()
        .filter(|b| **b != Body::Earth)
        .map(|b| Detail {
            label: b.name().to_string(),
            value: b.name_zh().to_string(),
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
    anyhow::ensure!(
        request.to_year > request.from_year,
        "结束年份必须晚于起始年份"
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
        .map_err(|e| anyhow::anyhow!("回传结果失败：{e:?}"))
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

fn detail(label: &str, value: String) -> Detail {
    Detail {
        label: label.to_string(),
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
                        "外切入（I）",
                        "内切入（II）",
                        "内切出（III）",
                        "外切出（IV）",
                    ];
                    for (label, c) in labels.iter().zip(&t.contacts) {
                        if let Some(c) = c {
                            details.push(detail(label, utc(c)));
                        }
                    }
                    details.push(detail("凌甚", utc(&t.greatest)));
                    details.push(detail(
                        "最小角距",
                        format!("{:.1}″", arcsec(t.min_separation)),
                    ));
                    details.push(detail(
                        "太阳视半径",
                        format!("{:.1}″", arcsec(t.sun_semidiameter)),
                    ));
                    details.push(detail(
                        "行星视半径",
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
                        details.push(detail("凌甚时太阳高度", format!("{:.1}°", h.to_degrees())));
                    }
                    out.push(EventItem {
                        kind: EventKind::Transit,
                        title: format!(
                            "{}凌日{}",
                            p.name_zh(),
                            if t.is_full() { "" } else { "（掠凌）" }
                        ),
                        utc: utc(&t.greatest),
                        tt_jd: t.greatest.tt_jd(),
                        summary: format!("最小角距 {:.1}″", arcsec(t.min_separation)),
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
                let name = if aspect == Aspect::Conjunction {
                    "合"
                } else {
                    "冲"
                };
                let mut title = format!("{}{}{}", a.name_zh(), b.name_zh(), name);
                if b == Body::Sun && a != Body::Moon && aspect == Aspect::Conjunction {
                    title.push_str(if e.distance_a_km < e.distance_b_km {
                        "（下合）"
                    } else {
                        "（上合）"
                    });
                }
                out.push(EventItem {
                    kind: req.kind,
                    title,
                    utc: utc(&e.time),
                    tt_jd: e.time.tt_jd(),
                    summary: format!("角距 {:.3}°", e.separation.to_degrees()),
                    details: vec![
                        detail("时刻（UTC）", utc(&e.time)),
                        detail("角距", format!("{:.4}°", e.separation.to_degrees())),
                        detail(
                            "黄纬差",
                            format!("{:.4}°", e.latitude_difference.to_degrees()),
                        ),
                        detail(
                            &format!("{}距离", a.name_zh()),
                            format!("{:.0} km", e.distance_a_km),
                        ),
                        detail(
                            &format!("{}距离", b.name_zh()),
                            format!("{:.0} km", e.distance_b_km),
                        ),
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
                out.push(EventItem {
                    kind: EventKind::Appulse,
                    title: format!("{}与{}相距最近", a.name_zh(), b.name_zh()),
                    utc: utc(&m.time),
                    tt_jd: m.time.tt_jd(),
                    summary: format!("角距 {:.3}°", m.separation.to_degrees()),
                    details: vec![
                        detail("时刻（UTC）", utc(&m.time)),
                        detail("角距", format!("{:.4}°", m.separation.to_degrees())),
                    ],
                });
            }
        }
        EventKind::SolarEclipse => {
            for e in solar_eclipse::search(eph, span)? {
                let name = match e.kind {
                    SolarEclipseKind::Partial => "日偏食",
                    SolarEclipseKind::Annular => "日环食",
                    SolarEclipseKind::Total => "日全食",
                    SolarEclipseKind::Hybrid => "全环食",
                };
                let non_central = e.kind != SolarEclipseKind::Partial && !e.central;
                let mut details = vec![
                    detail("食甚（全球，UTC）", utc(&e.greatest)),
                    detail("γ", format!("{:+.4}", e.gamma)),
                    detail("食分（全球）", format!("{:.4}", e.magnitude)),
                ];
                if let Some(p) = e.greatest_point {
                    details.push(detail(
                        "食甚点",
                        format!("{:.2}°, {:.2}°", p.latitude_deg, p.longitude_deg),
                    ));
                    details.push(detail(
                        "食甚点太阳高度",
                        format!("{:.0}°", p.sun_altitude_deg),
                    ));
                    details.push(detail("食带宽度", format!("{:.0} km", p.path_width_km)));
                }
                let mut summary = format!("食分 {:.3}", e.magnitude);
                if let Some(f) = filter {
                    let Some(l) = local_eclipse::local_solar(eph, &e, &f.observer, None)? else {
                        continue;
                    };
                    if !l.is_visible() {
                        continue;
                    }
                    let k = match l.kind {
                        LocalSolarKind::Partial => "偏食",
                        LocalSolarKind::Annular => "环食",
                        LocalSolarKind::Total => "全食",
                    };
                    summary = format!("本地{k}，食分 {:.3}", l.magnitude);
                    details.push(detail("本地类型", k.to_string()));
                    details.push(detail("本地食甚", utc(&l.maximum)));
                    details.push(detail("本地食分", format!("{:.3}", l.magnitude)));
                    details.push(detail("食面积", format!("{:.1}%", l.obscuration * 100.0)));
                    let names = ["初亏（C1）", "食既（C2）", "生光（C3）", "复圆（C4）"];
                    for (label, c) in names.iter().zip(&l.contacts) {
                        if let Some(c) = c {
                            details.push(detail(label, utc(c)));
                        }
                    }
                    details.push(detail(
                        "太阳高度（初亏/食甚/复圆）",
                        format!(
                            "{:.0}° / {:.0}° / {:.0}°",
                            l.sun_altitude_deg[0], l.sun_altitude_deg[1], l.sun_altitude_deg[2]
                        ),
                    ));
                }
                out.push(EventItem {
                    kind: EventKind::SolarEclipse,
                    title: format!("{name}{}", if non_central { "（非中心）" } else { "" }),
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
                    LunarEclipseKind::Penumbral => "半影月食",
                    LunarEclipseKind::Partial => "月偏食",
                    LunarEclipseKind::Total => "月全食",
                };
                let labels = [
                    "半影食始（P1）",
                    "初亏（U1）",
                    "食既（U2）",
                    "生光（U3）",
                    "复圆（U4）",
                    "半影食终（P4）",
                ];
                let mut details = vec![
                    detail("食甚（UTC）", utc(&e.greatest)),
                    detail("γ", format!("{:+.4}", e.gamma)),
                    detail("半影食分", format!("{:.4}", e.penumbral_magnitude)),
                    detail("本影食分", format!("{:.4}", e.umbral_magnitude)),
                ];
                for (label, c) in labels.iter().zip(&e.contacts) {
                    if let Some(c) = c {
                        details.push(detail(label, utc(c)));
                    }
                }
                if let Some(f) = filter {
                    let alt = local_eclipse::lunar_altitudes(eph, &e, &f.observer)?;
                    if !alt.iter().any(|h| *h > 0.0) {
                        continue;
                    }
                    details.push(detail("食甚时月亮高度", format!("{:.0}°", alt[3])));
                }
                out.push(EventItem {
                    kind: EventKind::LunarEclipse,
                    title: name.to_string(),
                    utc: utc(&e.greatest),
                    tt_jd: e.greatest.tt_jd(),
                    summary: format!("本影食分 {:.3}", e.umbral_magnitude),
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
                    Err(_) => Target::Star(
                        stars::find(key).ok_or_else(|| anyhow::anyhow!("星表中找不到 {key}"))?,
                    ),
                };
                cands.extend(occultation::candidates(eph, target, span)?);
            }
            cands.sort_by(|a, b| a.time.tt_seconds().total_cmp(&b.time.tt_seconds()));
            let mag = |t: &Target| match t {
                Target::Star(s) => format!("{:.1} 等", s.vmag),
                Target::Planet(_) => "行星".to_string(),
            };
            for c in cands {
                let label = c.target.label();
                match filter {
                    None => out.push(EventItem {
                        kind: EventKind::Occultation,
                        title: format!("月掩{label}（地心候选）"),
                        utc: utc(&c.time),
                        tt_jd: c.time.tt_jd(),
                        summary: format!(
                            "地心角距 {:.3}°，{}",
                            c.separation.to_degrees(),
                            mag(&c.target)
                        ),
                        details: vec![
                            detail("地心最近（UTC）", utc(&c.time)),
                            detail("地心几何角距", format!("{:.3}°", c.separation.to_degrees())),
                            detail("说明", "打开“只显示本地可见”可得到某地的掩始、掩终".into()),
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
                            title: format!("月掩{label}"),
                            utc: utc(&o.disappearance),
                            tt_jd: o.disappearance.tt_jd(),
                            summary: format!(
                                "掩终 {}，{}{}",
                                &utc(&o.reappearance)[11..],
                                mag(&o.target),
                                if daytime { "，白天" } else { "" }
                            ),
                            details: vec![
                                detail("掩始（UTC）", utc(&o.disappearance)),
                                detail("掩终（UTC）", utc(&o.reappearance)),
                                detail("最近（UTC）", utc(&o.closest)),
                                detail(
                                    "月亮高度（掩始/掩终）",
                                    format!(
                                        "{:.0}° / {:.0}°",
                                        o.moon_altitude_deg[0], o.moon_altitude_deg[1]
                                    ),
                                ),
                                detail(
                                    "太阳高度（掩始/掩终）",
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

/// 观测太阳的安全提示，所有涉及太阳的结果都附带。
pub const SUN_SAFETY: &str = "观测太阳必须使用合格的太阳滤光膜（ISO 12312-2）。切勿用肉眼、普通墨镜，或未加滤光的望远镜、相机直视太阳。";

/// 时刻变化超过此值（秒）时提醒。
const WARN_SHIFT_S: f64 = 1.0;
/// 中心线移动超过此值（km）时提醒。
const WARN_SHIFT_KM: f64 = 1.0;
/// 根数龄期超过此值（天）时提醒。
const WARN_AGE_DAYS: f64 = 3.0;

/// 观测安全提示，供界面显示。
#[frb(sync)]
pub fn sun_safety_notice() -> String {
    SUN_SAFETY.to_string()
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
) -> anyhow::Result<Vec<SatTransitItem>> {
    anyhow::ensure!(days > 0.0 && days <= 14.0, "搜索天数应在 0–14 天之间");
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
            out.push(sat_item(&e, old.as_deref()));
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

fn sat_item(e: &SatTransit, old: Option<&[SatTransit]>) -> SatTransitItem {
    let is_transit = e.is_transit();
    let (body_zh, body_en) = match e.body {
        Body::Sun => ("日", "sun"),
        _ => ("月", "moon"),
    };
    let what = if is_transit {
        format!("凌{body_zh}")
    } else {
        format!("近{body_zh}（未凌）")
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
    if e.elements_age_days.abs() > WARN_AGE_DAYS {
        warnings.push(format!(
            "根数龄期 {:.1} 天，预报误差可能达到数秒、数公里，请在观测前刷新根数。",
            e.elements_age_days.abs()
        ));
    }
    if old.is_some() && matched.is_none() {
        warnings.push("旧根数预报中没有这次事件，属于新出现的预报。".to_string());
    }
    if let Some(dt) = previous_shift_s.filter(|d| d.abs() > WARN_SHIFT_S) {
        warnings.push(format!("与上一份根数相比，时刻变化 {dt:+.1} 秒。"));
    }
    if let Some(km) = previous_shift_km.filter(|d| *d > WARN_SHIFT_KM) {
        warnings.push(format!("与上一份根数相比，中心线移动 {km:.1} km。"));
    }

    let mut details = vec![
        detail("最近时刻（UTC）", utc_ms(&e.closest)),
        detail(
            "最小角距",
            format!(
                "{:.2}′（{}视半径 {:.2}′）",
                arcmin(e.min_separation),
                if e.body == Body::Sun {
                    "太阳"
                } else {
                    "月球"
                },
                arcmin(e.body_semidiameter)
            ),
        ),
    ];
    if let Some(d) = e.duration_s {
        details.push(detail("穿越历时", format!("{d:.2} 秒")));
    }
    details.extend([
        detail("卫星距离", format!("{:.0} km", e.range_km)),
        detail(
            "高度 / 方位",
            format!("{:.1}° / {:.1}°", e.altitude_deg, e.azimuth_deg),
        ),
        detail(
            "离中心线",
            format!(
                "{:.2} km（可见带半宽约 {:.2} km）",
                e.distance_to_centerline_km, e.band_half_width_km
            ),
        ),
        detail(
            "中心线最近点",
            format!(
                "{:.4}°, {:.4}°",
                e.centerline_nearest.0, e.centerline_nearest.1
            ),
        ),
        detail("根数龄期", format!("{:.1} 天", e.elements_age_days)),
    ]);
    if let Some(dt) = previous_shift_s {
        details.push(detail("与旧根数相比（时刻）", format!("{dt:+.2} 秒")));
    }
    if let Some(km) = previous_shift_km {
        details.push(detail("与旧根数相比（中心线）", format!("{km:.2} km")));
    }
    if e.body == Body::Sun {
        details.push(detail("安全提示", SUN_SAFETY.to_string()));
    }

    SatTransitItem {
        norad_id: e.norad_id,
        satellite: e.satellite.clone(),
        body: body_en.to_string(),
        is_transit,
        title: format!("{} {what}", e.satellite),
        utc: utc(&e.closest),
        tt_jd: e.closest.tt_jd(),
        summary: format!(
            "角距 {:.2}′，离中心线 {:.1} km",
            arcmin(e.min_separation),
            e.distance_to_centerline_km
        ),
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
}
