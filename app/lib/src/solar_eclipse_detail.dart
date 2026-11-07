import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'eclipse_diagram.dart';
import 'eclipse_timeline.dart';
import 'errors.dart';
import 'locale.dart';
import 'lunar_eclipse_detail.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'time_format.dart';
import 'world_map.dart';

/// 日食详情页的增强部分：安全提示、本地情况（时间轴、各食相时刻）、示意图。
class SolarEclipseSections extends StatefulWidget {
  const SolarEclipseSections({
    super.key,
    required this.engine,
    required this.event,
    this.settings,
  });

  final Engine engine;
  final EventItem event;

  /// 有设置时用其中的观测地（手动位置或缓存的定位，不主动定位）
  final Settings? settings;

  @override
  State<SolarEclipseSections> createState() => _SolarEclipseSectionsState();
}

class _SolarEclipseSectionsState extends State<SolarEclipseSections> {
  Future<SolarEclipseDetail>? _future;
  String? _key;

  void _load(BuildContext context, Place? place) {
    final lang = rustLang(context);
    final key = '$lang,${place?.lat},${place?.lon},${place?.height}';
    if (key == _key) return;
    _key = key;
    _future = solarEclipseDetail(
      engine: widget.engine,
      ttJd: widget.event.ttJd,
      site: place == null
          ? null
          : Site(
              latitudeDeg: place.lat,
              longitudeDeg: place.lon,
              heightM: place.height,
            ),
      lang: lang,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    if (s == null) return _body(context, null);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _body(context, s.knownPlace),
    );
  }

  Widget _body(BuildContext context, Place? place) {
    _load(context, place);
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SafetyBanner(text: sunSafetyNotice(lang: rustLang(context))),
        const SizedBox(height: 16),
        FutureBuilder<SolarEclipseDetail>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    describeError(snap.error!, l),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              );
            }
            final d = snap.data;
            if (d == null) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LocalCard(
                  detail: d,
                  onSetLocation: widget.settings == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SettingsPage(settings: widget.settings!),
                          ),
                        ),
                ),
                if (d.local case final v? when v.track.length >= 2) ...[
                  const SizedBox(height: 16),
                  _SunSimulationCard(view: v),
                ],
                const SizedBox(height: 16),
                _SolarMapCard(detail: d, place: place),
                const SizedBox(height: 16),
                EclipseDiagramCard(engine: widget.engine, event: widget.event),
                const SizedBox(height: 16),
                const _SolarTips(),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 文字
// ---------------------------------------------------------------------------

/// “6 分 23 秒” / “58 秒”。
String formatSeconds(AppLocalizations l, double seconds) {
  final s = seconds.round();
  return l.durationMs(s ~/ 60, s % 60);
}

String solarKindText(AppLocalizations l, LocalEclipseKind k) => switch (k) {
  LocalEclipseKind.total => l.solarKindTotal,
  LocalEclipseKind.annular => l.solarKindAnnular,
  LocalEclipseKind.partial => l.solarKindPartial,
};

String solarVisibilityText(AppLocalizations l, SolarVisibility v) =>
    switch (v) {
      SolarVisibility.full => l.solarVisFull,
      SolarVisibility.rises => l.solarVisRises,
      SolarVisibility.sets => l.solarVisSets,
      SolarVisibility.risesAndSets => l.solarVisRisesAndSets,
      SolarVisibility.hidden => l.solarVisHidden,
      SolarVisibility.noEclipse => l.solarVisNone,
    };

/// 只要 16 方位名称（不带度数）。
String compassName(AppLocalizations l, double azimuthDeg) =>
    compassPoint(l, azimuthDeg).split(' ').first;

/// 太阳面模拟轨迹的绝对时刻。
DateTime trackTime(LocalSolarView v, SolarDiskPoint p) {
  final start = parseUtc(v.trackStartUtc) ?? DateTime.utc(2000);
  return start.add(Duration(milliseconds: (p.seconds * 1000).round()));
}

// ---------------------------------------------------------------------------
// 安全提示
// ---------------------------------------------------------------------------

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 本地情况
// ---------------------------------------------------------------------------

class _LocalCard extends StatelessWidget {
  const _LocalCard({required this.detail, this.onSetLocation});

  final SolarEclipseDetail detail;
  final VoidCallback? onSetLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final v = detail.local;
    final title = Text(
      l.lunarLocalTitle,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final saros = detail.saros.isEmpty
        ? null
        : Text(l.lunarSaros(detail.saros), style: muted);

    if (v == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(l.solarNeedsLocation, style: muted)),
                  if (onSetLocation != null)
                    TextButton(
                      onPressed: onSetLocation,
                      child: Text(l.tonightSetLocation),
                    ),
                ],
              ),
              if (saros != null) ...[const SizedBox(height: 8), saros],
            ],
          ),
        ),
      );
    }

    final kind = v.kind;
    final chips = <(String, bool)>[
      if (kind != null)
        (
          v.centralSeconds == null
              ? solarKindText(l, kind)
              : l.solarCentralDuration(
                  solarKindText(l, kind),
                  formatSeconds(l, v.centralSeconds!),
                ),
          true,
        ),
      if (kind != null)
        (l.solarMagnitude(v.magnitude.toStringAsFixed(3)), false),
      if (kind != null)
        (
          l.solarObscuration(
            (v.obscuration * 100).toStringAsFixed(
              v.obscuration > 0.999 ? 0 : 1,
            ),
          ),
          false,
        ),
    ];
    final pathLine = switch ((v.centerlineDistanceKm, v.centerlineBearingDeg)) {
      (final km?, final bearing?) =>
        kind == LocalEclipseKind.total || kind == LocalEclipseKind.annular
            ? l.solarInsidePath(
                solarKindText(l, kind!).toLowerCase(),
                km.round(),
              )
            : l.solarOutsidePath(compassName(l, bearing), km.round()),
      _ => null,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 8),
            _SolarVerdict(view: v),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (text, strong) in chips)
                    DetailChip(text: text, strong: strong),
                ],
              ),
            ],
            if (v.phases.length >= 2) ...[
              const SizedBox(height: 8),
              _SolarTimeline(view: v),
              _PhaseTable(view: v),
            ],
            if (pathLine != null || saros != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  ?pathLine,
                  if (detail.saros.isNotEmpty) l.lunarSaros(detail.saros),
                ].join(' · '),
                style: muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SolarVerdict extends StatelessWidget {
  const _SolarVerdict({required this.view});

  final LocalSolarView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final v = view.verdict;
    final (icon, color) = switch (v) {
      SolarVisibility.full => (Icons.visibility_outlined, cs.primary),
      SolarVisibility.hidden ||
      SolarVisibility.noEclipse => (Icons.visibility_off_outlined, cs.error),
      _ => (Icons.flaky_outlined, cs.tertiary),
    };
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            solarVisibilityText(l, v),
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// 本地日食时间轴：C1–C4 为偏食，C2–C3 为全食（深色）或环食（强调色）；太阳在地平线下的时段画斜线。
class _SolarTimeline extends StatelessWidget {
  const _SolarTimeline({required this.view});

  final LocalSolarView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accents = AstroAccents.of(context);
    final dark = theme.brightness == Brightness.dark;
    // 全食段画成接近黑色（太阳被完全遮住），环食段用强调色
    final central = view.kind == LocalEclipseKind.total
        ? (dark
              ? Colors.black
              : Color.alphaBlend(
                  cs.onSurface.withValues(alpha: 0.85),
                  cs.surface,
                ))
        : accents.eclipse;
    return EclipseTimeline(
      phases: parsePhases(view.phases.map((p) => (p.code, p.utc))),
      base: Color.alphaBlend(
        accents.eclipse.withValues(alpha: dark ? 0.30 : 0.28),
        cs.surface,
      ),
      segments: [TimelineSegment('C2', 'C3', central)],
      greatest: accents.eclipse,
      below: belowHorizonIntervals(
        [for (final p in view.track) trackTime(view, p)],
        [for (final p in view.track) p.sunAltitudeDeg],
      ),
    );
  }
}

class _PhaseTable extends StatelessWidget {
  const _PhaseTable({required this.view});

  final LocalSolarView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final max = view.phases.where((p) => p.code == 'Max').firstOrNull;
    final ref = parseUtc(max?.utc ?? view.phases.first.utc)!.toLocal();
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: child,
    );
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(0.6),
        3: FlexColumnWidth(1.1),
      },
      children: [
        TableRow(
          children: [
            cell(Text(l.lunarColPhase, style: muted)),
            cell(Text(l.lunarColTime(zoneLabel(ref)), style: muted)),
            cell(Text(l.lunarColAlt, style: muted)),
            cell(Text(l.lunarColAz, style: muted)),
          ],
        ),
        for (final p in view.phases)
          () {
            final strong = p.code == 'Max';
            final up = p.sun.altitudeDeg > 0;
            final body = theme.textTheme.bodyMedium?.copyWith(
              fontWeight: strong ? FontWeight.w600 : null,
              color: up ? null : cs.onSurfaceVariant,
            );
            final t = parseUtc(p.utc)?.toLocal();
            final code = p.code == 'Max' ? '' : ' ${p.code}';
            return TableRow(
              children: [
                cell(Text('${p.name}$code', style: body)),
                cell(Text(t == null ? p.utc : localClock(t, ref), style: body)),
                cell(Text('${p.sun.altitudeDeg.round()}°', style: body)),
                cell(Text(compassPoint(l, p.sun.azimuthDeg), style: body)),
              ],
            );
          }(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 太阳面模拟
// ---------------------------------------------------------------------------

/// 太阳面模拟轨迹按时刻插值。
class SolarTrackSampler {
  SolarTrackSampler(this.view);

  final LocalSolarView view;

  List<SolarDiskPoint> get _t => view.track;

  DateTime get start => trackTime(view, _t.first);
  DateTime get end => trackTime(view, _t.last);

  /// 时刻 t 处的取样值（相邻两点线性插值，两端截断）。
  SolarDiskPoint at(DateTime t) {
    final pts = _t;
    final s = t.difference(start).inMilliseconds / 1000 + pts.first.seconds;
    if (s <= pts.first.seconds) return pts.first;
    if (s >= pts.last.seconds) return pts.last;
    var lo = 0, hi = pts.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (pts[mid].seconds <= s) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = pts[lo], b = pts[hi];
    final f = (s - a.seconds) / (b.seconds - a.seconds);
    double mix(double x, double y) => x + (y - x) * f;
    // 天顶位置角跨 ±180° 时按近的一侧插值
    var dz = b.zenithAngleDeg - a.zenithAngleDeg;
    dz -= 360 * (dz / 360).round();
    return SolarDiskPoint(
      seconds: s,
      xArcmin: mix(a.xArcmin, b.xArcmin),
      yArcmin: mix(a.yArcmin, b.yArcmin),
      sunRadiusArcmin: mix(a.sunRadiusArcmin, b.sunRadiusArcmin),
      moonRadiusArcmin: mix(a.moonRadiusArcmin, b.moonRadiusArcmin),
      obscuration: mix(a.obscuration, b.obscuration),
      sunAltitudeDeg: mix(a.sunAltitudeDeg, b.sunAltitudeDeg),
      zenithAngleDeg: a.zenithAngleDeg + dz * f,
    );
  }
}

/// 此刻处在哪个阶段。
String solarStateText(AppLocalizations l, LocalSolarView v, DateTime t) {
  DateTime? at(String code) {
    for (final p in v.phases) {
      if (p.code == code) return parseUtc(p.utc);
    }
    return null;
  }

  bool inside(String a, String b) {
    final (x, y) = (at(a), at(b));
    return x != null && y != null && !t.isBefore(x) && !t.isAfter(y);
  }

  if (inside('C2', 'C3')) {
    return v.kind == LocalEclipseKind.annular
        ? l.solarStateAnnular
        : l.solarStateTotal;
  }
  if (inside('C1', 'C4')) return l.solarStatePartial;
  final c1 = at('C1');
  return c1 != null && t.isBefore(c1) ? l.solarStateBefore : l.solarStateAfter;
}

class _SunSimulationCard extends StatefulWidget {
  const _SunSimulationCard({required this.view});

  final LocalSolarView view;

  @override
  State<_SunSimulationCard> createState() => _SunSimulationCardState();
}

class _SunSimulationCardState extends State<_SunSimulationCard> {
  late SolarTrackSampler _track;
  late DateTime _t;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(_SunSimulationCard old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) _reset();
  }

  void _reset() {
    _track = SolarTrackSampler(widget.view);
    final max = widget.view.phases.where((p) => p.code == 'Max').firstOrNull;
    _t = (max == null ? null : parseUtc(max.utc)) ?? _track.start;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final v = widget.view;
    final p = _track.at(_t);
    final local = _t.toLocal();
    final total = _track.end.difference(_track.start).inSeconds.toDouble();
    final value = _t.difference(_track.start).inSeconds.toDouble();
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final ob = p.obscuration.clamp(0.0, 1.0);

    final readout = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${localClock(local, local)} ${zoneLabel(local)}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          solarStateText(l, v, _t),
          style: theme.textTheme.bodyLarge?.copyWith(color: cs.primary),
        ),
        Text(
          l.solarObscuration((ob * 100).toStringAsFixed(ob > 0.9999 ? 0 : 1)),
          style: theme.textTheme.bodyMedium,
        ),
        Text(
          p.sunAltitudeDeg > 0
              ? l.solarSunAlt(p.sunAltitudeDeg.round())
              : l.solarSunDown,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: p.sunAltitudeDeg > 0 ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
      ],
    );
    final face = SizedBox.square(
      dimension: 200,
      child: CustomPaint(
        painter: _SunFacePainter(
          point: p,
          accents: AstroAccents.of(context),
          sky: cs.surfaceContainerHigh,
          moon: theme.brightness == Brightness.dark
              ? Colors.black
              : Color.alphaBlend(
                  cs.onSurface.withValues(alpha: 0.85),
                  cs.surface,
                ),
          zenith: muted?.color ?? cs.onSurfaceVariant,
        ),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.solarSimTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) => c.maxWidth >= 420
                  ? Row(
                      children: [
                        face,
                        const SizedBox(width: 20),
                        Expanded(child: readout),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: face),
                        const SizedBox(height: 8),
                        readout,
                      ],
                    ),
            ),
            Slider(
              key: const ValueKey('solarSlider'),
              value: value.clamp(0, total),
              max: total,
              label: localClock(local, local, seconds: false),
              semanticFormatterCallback: (_) =>
                  '${l.lunarSliderLabel} ${localClock(local, local)}',
              onChanged: (x) => setState(
                () => _t = _track.start.add(
                  Duration(milliseconds: (x * 1000).round()),
                ),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final ph in v.phases)
                  if (parseUtc(ph.utc) case final t?)
                    ChoiceChip(
                      label: Text(ph.code == 'Max' ? ph.name : ph.code),
                      selected: t.difference(_t).inMilliseconds.abs() < 1500,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _t = t),
                    ),
              ],
            ),
            const SizedBox(height: 10),
            Text(l.solarSimCaption, style: muted),
          ],
        ),
      ),
    );
  }
}

/// 太阳面（分享图等处用）：没有圆形视场底色和天顶箭头，直接画在背景上。
class SunFace extends StatelessWidget {
  const SunFace({super.key, required this.point, required this.moon});

  final SolarDiskPoint point;

  /// 月面颜色（全食时一律为黑色）
  final Color moon;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SunFacePainter(
      point: point,
      accents: AstroAccents.of(context),
      sky: Colors.transparent,
      moon: moon,
      zenith: Colors.transparent,
      field: false,
    ),
    size: Size.infinite,
  );
}

/// 太阳面：天顶朝上；月亮圆面按此刻相对太阳的位置叠上去，全食时画日冕示意。
class _SunFacePainter extends CustomPainter {
  _SunFacePainter({
    required this.point,
    required this.accents,
    required this.sky,
    required this.moon,
    required this.zenith,
    this.field = true,
  });

  final SolarDiskPoint point;
  final AstroAccents accents;
  final Color sky;
  final Color moon;
  final Color zenith;

  /// 画圆形视场（底色、裁剪）和天顶箭头
  final bool field;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.3;
    final k = r / point.sunRadiusArcmin;
    final rm = point.moonRadiusArcmin * k;
    // 北在上、东在左时，月心在 (−x, −y)·k；再顺时针转天顶位置角，让天顶朝上
    final q = point.zenithAngleDeg * math.pi / 180;
    final rel = Offset(-point.xArcmin * k, -point.yArcmin * k);
    final moonAt =
        c +
        Offset(
          rel.dx * math.cos(q) - rel.dy * math.sin(q),
          rel.dx * math.sin(q) + rel.dy * math.cos(q),
        );
    final totality = point.obscuration > 0.9999 && rm >= r;

    // 所有内容都裁剪在圆形视场内（C1、C4 前后月亮在日面外）
    final view = Rect.fromCircle(center: c, radius: size.shortestSide / 2);
    canvas.save();
    if (field) {
      canvas.clipPath(Path()..addOval(view));
      canvas.drawRect(view, Paint()..color = totality ? Colors.black : sky);
    }
    if (totality) {
      // 日冕示意：从日面边缘向外淡出
      canvas.drawCircle(
        c,
        r * 2.4,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accents.moonLit.withValues(alpha: 0.9),
              accents.moonLit.withValues(alpha: 0.35),
              accents.moonLit.withValues(alpha: 0),
            ],
            stops: const [0.4, 0.55, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r * 2.4)),
      );
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(accents.eclipse, Colors.white, 0.45)!,
            accents.eclipse,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      moonAt,
      rm,
      Paint()..color = totality ? Colors.black : moon,
    );
    canvas.restore();
    if (!field) return;

    // 天顶方向
    final tp = TextPainter(
      text: TextSpan(
        text: '↑',
        style: TextStyle(color: zenith, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, 2));
  }

  @override
  bool shouldRepaint(_SunFacePainter old) =>
      old.point != point || old.accents != accents || old.sky != sky;
}

// ---------------------------------------------------------------------------
// 全球食况地图
// ---------------------------------------------------------------------------

/// 食分分档的填色：食分越大越不透明。
Color solarMagnitudeShade(AstroAccents a, double m) =>
    a.eclipse.withValues(alpha: 0.12 + 0.5 * m.clamp(0.0, 1.0));

/// 全食带画成接近黑色，环食带用强调色。
Color solarBandColor(ThemeData theme, AstroAccents a, bool annular) => annular
    ? a.eclipse
    : (theme.brightness == Brightness.dark
          ? Colors.black
          : theme.colorScheme.onSurface.withValues(alpha: 0.85));

/// 日食的全球食况地图（只有地图本身，2:1）：最大食分填色、等值线、食带、食甚点和观测地。
/// 详情页和分享图共用。
class SolarPathMap extends StatefulWidget {
  const SolarPathMap({super.key, required this.detail, this.place});

  final SolarEclipseDetail detail;

  /// 在地图上标出的观测地（null 时不标）
  final Place? place;

  /// 有没有食带（中心食）
  static bool hasBand(SolarEclipseDetail d) => d.centralLine.length >= 2;

  @override
  State<SolarPathMap> createState() => _SolarPathMapState();
}

class _SolarPathMapState extends State<SolarPathMap> {
  static const _levels = [0.001, 0.2, 0.5, 0.8];
  late List<double> _values;
  late Map<double, List<((double, double), (double, double))>> _contours;
  late List<(double, double)> _band;
  late double _center;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(SolarPathMap old) {
    super.didUpdateWidget(old);
    if (old.detail != widget.detail) _prepare();
  }

  void _prepare() {
    final d = widget.detail;
    final rows = d.gridRows, cols = d.gridCols;
    _values = [for (final v in d.grid) v.toDouble()];
    _contours = {
      for (final lv in _levels)
        lv: contourSegments(_values, rows, cols, d.gridStepDeg, lv),
    };
    _band = pathBand([
      for (final p in d.centralLine) (p.latitudeDeg, p.longitudeDeg),
    ], d.pathWidthKm);
    // 地图以食甚点为中心；非中心食取食分最大的格子
    final g = d.greatestPoint;
    if (g != null) {
      _center = g.longitudeDeg;
    } else {
      var best = 0;
      for (var i = 1; i < _values.length; i++) {
        if (_values[i] > _values[best]) best = i;
      }
      _center = -180 + (best % cols + 0.5) * d.gridStepDeg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accents = AstroAccents.of(context);
    final d = widget.detail;
    final place = widget.place;
    final bandColor = solarBandColor(theme, accents, d.diagram.umbraRadius > 0);
    final label = (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
        .copyWith(color: cs.onSurface, fontWeight: FontWeight.w600);

    void fill(Canvas canvas, MapProjection p) {
      // 食分按 0.1 分档，同一档的格子并成一条路径
      final rows = d.gridRows, cols = d.gridCols;
      final step = d.gridStepDeg;
      final cell = step * p.k;
      final bands = List.generate(11, (_) => Path());
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final m = _values[r * cols + c];
          if (m <= 0) continue;
          final o = p.at(90 - (r + 0.5) * step, -180 + (c + 0.5) * step);
          bands[(m * 10).floor().clamp(0, 10)].addRect(
            Rect.fromLTWH(o.dx - cell / 2, r * cell, cell, cell),
          );
        }
      }
      for (var i = 0; i < bands.length; i++) {
        canvas.drawPath(
          bands[i],
          Paint()
            ..color = solarMagnitudeShade(accents, (i + 0.5) / 10)
            ..isAntiAlias = false,
        );
      }
    }

    void marks(Canvas canvas, MapProjection p) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = cs.onSurface.withValues(alpha: 0.7);
      for (final lv in _levels) {
        final segs = _contours[lv]!;
        if (segs.isEmpty) continue;
        final path = segmentsPath(p, segs);
        p.drawWrapped(canvas, (c) => c.drawPath(path, line));
      }
      if (_band.length >= 3) {
        final band = p.polyline(_band)..close();
        p.drawWrapped(
          canvas,
          (c) => c.drawPath(band, Paint()..color = bandColor),
        );
      }
      final g = d.greatestPoint;
      if (g != null) {
        final o = p.at(g.latitudeDeg, g.longitudeDeg);
        final tp = TextPainter(
          text: TextSpan(
            text: '★',
            style: label.copyWith(color: accents.eclipse, fontSize: 16),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
      }
      if (place != null) {
        final o = p.at(place.lat, place.lon);
        canvas.drawCircle(o, 4.5, Paint()..color = cs.surface);
        canvas.drawCircle(o, 3.2, Paint()..color = cs.primary);
      }
    }

    return WorldMap(centerLon: _center, fill: fill, marks: marks);
  }
}

class _SolarMapCard extends StatelessWidget {
  const _SolarMapCard({required this.detail, this.place});

  final SolarEclipseDetail detail;
  final Place? place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final accents = AstroAccents.of(context);
    final annular = detail.diagram.umbraRadius > 0;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    Widget legend(Color c, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: c,
            border: Border.all(color: cs.outline),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.solarMapTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SolarPathMap(detail: detail, place: place),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in [0.1, 0.4, 0.7, 1.0])
                      Container(
                        width: 14,
                        height: 14,
                        color: solarMagnitudeShade(accents, m),
                      ),
                    const SizedBox(width: 6),
                    Text(l.solarMapMagnitude, style: theme.textTheme.bodySmall),
                  ],
                ),
                if (SolarPathMap.hasBand(detail))
                  legend(
                    solarBandColor(theme, accents, annular),
                    annular ? l.solarMapAnnularPath : l.solarMapTotalPath,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l.solarMapCaption, style: muted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 观测与拍摄提示
// ---------------------------------------------------------------------------

class _SolarTips extends StatelessWidget {
  const _SolarTips();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    Widget tip(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color ?? cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.lunarTipsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            tip(Icons.shield_outlined, l.solarTipFilter, color: cs.error),
            tip(Icons.radio_button_checked, l.solarTipPinhole),
            tip(Icons.photo_camera_outlined, l.solarTipCamera),
            tip(Icons.brightness_3_outlined, l.solarTipTotality),
          ],
        ),
      ),
    );
  }
}
