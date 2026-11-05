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
use guanxiang_core::events::solar_eclipse::{self, SolarEclipseKind};
use guanxiang_core::events::visibility::{apparent_altitude, VisibilityFilter};
use guanxiang_core::events::{separation, transit, Span};
use guanxiang_core::{AniseEphemeris, Body, DateTime, Observer, Time};

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
    }
    Ok(out)
}
