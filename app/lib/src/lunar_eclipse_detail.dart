import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'eclipse_diagram.dart';
import 'errors.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'time_format.dart';

/// 月食详情页的增强部分：食相时间轴和持续时间、各食相时刻与本地可见情况、示意图。
class LunarEclipseSections extends StatefulWidget {
  const LunarEclipseSections({
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
  State<LunarEclipseSections> createState() => _LunarEclipseSectionsState();
}

class _LunarEclipseSectionsState extends State<LunarEclipseSections> {
  Future<LunarEclipseDetail>? _future;
  String? _key;

  void _load(BuildContext context, Place? place) {
    final lang = rustLang(context);
    final key = '$lang,${place?.lat},${place?.lon},${place?.height}';
    if (key == _key) return;
    _key = key;
    _future = lunarEclipseDetail(
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
    return FutureBuilder<LunarEclipseDetail>(
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
            _PhasesCard(detail: d),
            const SizedBox(height: 16),
            _TimesCard(
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
            const SizedBox(height: 16),
            EclipseDiagramCard(engine: widget.engine, event: widget.event),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 文字
// ---------------------------------------------------------------------------

/// “1 小时 22 分” / “47 分钟”，按分钟四舍五入。
String formatDuration(AppLocalizations l, double minutes) {
  final m = minutes.round();
  return m >= 60 ? l.durationHm(m ~/ 60, m % 60) : l.durationM(m);
}

/// 16 方位加度数：“东南 132°”。
String compassPoint(AppLocalizations l, double azimuthDeg) {
  final names = l.compassPoints.split(' ');
  final az = azimuthDeg % 360;
  final i = ((az + 11.25) ~/ 22.5) % 16;
  return '${names[i]} ${az.round() % 360}°';
}

String visibilityText(AppLocalizations l, LunarVisibility v) => switch (v) {
  LunarVisibility.full => l.lunarVisFull,
  LunarVisibility.rises => l.lunarVisRises,
  LunarVisibility.sets => l.lunarVisSets,
  LunarVisibility.risesAndSets => l.lunarVisRisesAndSets,
  LunarVisibility.hidden => l.lunarVisHidden,
};

/// 按太阳视高度分档：日出日落（上边缘）以上为白天，−18° 以上为晨昏，再往下是夜间。
String skyText(AppLocalizations l, double sunAltitudeDeg) =>
    sunAltitudeDeg > -0.833
    ? l.lunarSkyDay
    : sunAltitudeDeg > -18
    ? l.lunarSkyTwilight
    : l.lunarSkyNight;

String _two(int v) => v.toString().padLeft(2, '0');

/// 本地时刻：同一天写 “18:12:58”，跨日时在前面加 “9/8”。
String localClock(DateTime local, DateTime reference, {bool seconds = true}) {
  final hm = '${_two(local.hour)}:${_two(local.minute)}';
  final t = seconds ? '$hm:${_two(local.second)}' : hm;
  final sameDay =
      local.year == reference.year &&
      local.month == reference.month &&
      local.day == reference.day;
  return sameDay ? t : '${local.month}/${local.day} $t';
}

// ---------------------------------------------------------------------------
// 食相时间轴和持续时间
// ---------------------------------------------------------------------------

class _PhasesCard extends StatelessWidget {
  const _PhasesCard({required this.detail});

  final LunarEclipseDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final d = detail;
    final chips = <String>[
      if (d.totalMinutes != null)
        l.lunarDurationTotal(formatDuration(l, d.totalMinutes!)),
      if (d.partialMinutes != null)
        l.lunarDurationUmbral(formatDuration(l, d.partialMinutes!)),
      l.lunarDurationPenumbral(formatDuration(l, d.penumbralMinutes)),
    ];
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.lunarPhasesTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            PhaseTimeline(detail: d),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (i, c) in chips.indexed)
                  _Chip(text: c, strong: i == 0 && d.totalMinutes != null),
              ],
            ),
            if (d.saros.isNotEmpty || d.local != null) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (d.saros.isNotEmpty) l.lunarSaros(d.saros),
                  if (d.local != null) l.lunarHorizonHint,
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

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: strong ? cs.primaryContainer : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: strong ? cs.onPrimaryContainer : cs.onSurface,
          fontWeight: strong ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}

/// 横向时间轴：P1 到 P4 按时间比例分段（半影浅、本影深、全食古铜红），上面标食相、下面标本地时刻；
/// 有观测地时，月亮在地平线下的时段画斜线。
class PhaseTimeline extends StatelessWidget {
  const PhaseTimeline({super.key, required this.detail});

  final LunarEclipseDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accents = AstroAccents.of(context);
    final dark = theme.brightness == Brightness.dark;
    final label = (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
        .copyWith(color: cs.onSurfaceVariant);
    return SizedBox(
      height: 84,
      width: double.infinity,
      child: CustomPaint(
        painter: _TimelinePainter(
          detail: detail,
          penumbra: Color.alphaBlend(
            cs.onSurface.withValues(alpha: dark ? 0.16 : 0.10),
            cs.surface,
          ),
          umbra: Color.alphaBlend(
            cs.onSurface.withValues(alpha: dark ? 0.42 : 0.38),
            cs.surface,
          ),
          total: accents.bloodMoon,
          greatest: accents.eclipse,
          hatch: cs.surface,
          label: label,
          strongLabel: label.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.detail,
    required this.penumbra,
    required this.umbra,
    required this.total,
    required this.greatest,
    required this.hatch,
    required this.label,
    required this.strongLabel,
  });

  final LunarEclipseDetail detail;
  final Color penumbra;
  final Color umbra;
  final Color total;
  final Color greatest;
  final Color hatch;
  final TextStyle label;
  final TextStyle strongLabel;

  static const _barTop = 34.0;
  static const _barHeight = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final phases = [
      for (final p in detail.phases)
        if (parseUtc(p.utc) case final t?) (p.code, t),
    ];
    if (phases.length < 2) return;
    final t0 = phases.first.$2;
    final t1 = phases.last.$2;
    final span = t1.difference(t0).inMilliseconds.toDouble();
    if (span <= 0) return;
    // 两端留出半个标签的宽度
    const margin = 18.0;
    final w = size.width - 2 * margin;
    double x(DateTime t) => margin + w * t.difference(t0).inMilliseconds / span;
    DateTime? at(String code) {
      for (final p in phases) {
        if (p.$1 == code) return p.$2;
      }
      return null;
    }

    final bar = Rect.fromLTWH(margin, _barTop, w, _barHeight);
    final rr = RRect.fromRectAndRadius(bar, const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(bar, Paint()..color = penumbra);
    void seg(DateTime? a, DateTime? b, Color c) {
      if (a == null || b == null) return;
      canvas.drawRect(
        Rect.fromLTRB(x(a), _barTop, x(b), _barTop + _barHeight),
        Paint()..color = c,
      );
    }

    seg(at('U1'), at('U4'), umbra);
    seg(at('U2'), at('U3'), total);
    _hatchBelowHorizon(canvas, t0, t1, x);
    canvas.restore();

    // 食甚
    final g = at('Max');
    if (g != null) {
      canvas.drawLine(
        Offset(x(g), _barTop - 4),
        Offset(x(g), _barTop + _barHeight + 4),
        Paint()
          ..color = greatest
          ..strokeWidth = 2,
      );
    }

    // 上面标食相代号，下面标本地时刻；挤在一起时换到第二行，两行都放不下就省略
    final codeRows = [<Rect>[], <Rect>[]];
    final timeRows = [<Rect>[], <Rect>[]];
    for (final (code, t) in phases) {
      final isMax = code == 'Max';
      final cx = x(t);
      _place(
        canvas,
        isMax ? '★' : code,
        cx,
        (row) => _barTop - 4 - row * 14,
        Alignment.bottomCenter,
        isMax ? strongLabel.copyWith(color: greatest) : label,
        codeRows,
        size.width,
      );
      _place(
        canvas,
        localClock(t.toLocal(), t.toLocal(), seconds: false),
        cx,
        (row) => _barTop + _barHeight + 4 + row * 14,
        Alignment.topCenter,
        isMax ? strongLabel : label,
        timeRows,
        size.width,
      );
    }
  }

  void _place(
    Canvas canvas,
    String text,
    double cx,
    double Function(int row) y,
    Alignment align,
    TextStyle style,
    List<List<Rect>> rows,
    double width,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    for (var row = 0; row < rows.length; row++) {
      final left = (cx - tp.width / 2).clamp(0.0, width - tp.width);
      final top = align == Alignment.bottomCenter ? y(row) - tp.height : y(row);
      final r = Rect.fromLTWH(left - 2, top, tp.width + 4, tp.height);
      if (rows[row].any((o) => o.overlaps(r))) continue;
      rows[row].add(r);
      tp.paint(canvas, Offset(left, top));
      return;
    }
  }

  /// 月亮在地平线下的时段画斜线（高度在相邻取样点之间线性插值找零点）。
  void _hatchBelowHorizon(
    Canvas canvas,
    DateTime t0,
    DateTime t1,
    double Function(DateTime) x,
  ) {
    final local = detail.local;
    if (local == null) return;
    final path = detail.diagram.path;
    final alt = local.trackAltitudeDeg;
    if (alt.length != path.length || path.isEmpty) return;
    final times = [for (final p in path) parseUtc(p.utc)];
    final below = <(DateTime, DateTime)>[];
    DateTime? start;
    for (var i = 0; i < path.length; i++) {
      final t = times[i];
      if (t == null) continue;
      final down = alt[i] <= 0;
      if (i > 0 && times[i - 1] != null && (alt[i - 1] <= 0) != down) {
        final a = alt[i - 1], b = alt[i];
        final f = a / (a - b);
        final tc = times[i - 1]!.add(
          Duration(
            milliseconds: (t.difference(times[i - 1]!).inMilliseconds * f)
                .round(),
          ),
        );
        if (down) {
          start = tc;
        } else if (start != null) {
          below.add((start, tc));
          start = null;
        }
      } else if (i == 0 && down) {
        start = t;
      }
    }
    if (start != null) below.add((start, times.last ?? t1));

    final paint = Paint()
      ..color = hatch.withValues(alpha: 0.85)
      ..strokeWidth = 1.6;
    for (final (a, b) in below) {
      final from = x(a.isBefore(t0) ? t0 : a);
      final to = x(b.isAfter(t1) ? t1 : b);
      if (to <= from) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(from, _barTop, to, _barTop + _barHeight));
      for (var sx = from - _barHeight; sx < to; sx += 5) {
        canvas.drawLine(
          Offset(sx, _barTop + _barHeight),
          Offset(sx + _barHeight, _barTop),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.detail != detail || old.total != total || old.label != label;
}

// ---------------------------------------------------------------------------
// 各食相时刻与本地可见情况
// ---------------------------------------------------------------------------

class _TimesCard extends StatelessWidget {
  const _TimesCard({required this.detail, this.onSetLocation});

  final LunarEclipseDetail detail;
  final VoidCallback? onSetLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final d = detail;
    final local = d.local;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final greatest = d.phases.where((p) => p.code == 'Max').firstOrNull;
    final ref = parseUtc(greatest?.utc ?? d.phases.first.utc)!.toLocal();
    final zone = zoneLabel(ref);

    final rows = <TableRow>[
      TableRow(
        children: [
          _cell(Text(l.lunarColPhase, style: muted)),
          _cell(Text(l.lunarColTime(zone), style: muted)),
          if (local != null) ...[
            _cell(Text(l.lunarColAlt, style: muted)),
            _cell(Text(l.lunarColAz, style: muted)),
            _cell(Text(l.lunarColSky, style: muted)),
          ],
        ],
      ),
      for (final p in d.phases)
        _phaseRow(context, l, p, ref, strong: p.code == 'Max'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              local == null ? l.lunarTimesTitle : l.lunarLocalTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (local != null) ...[
              const SizedBox(height: 8),
              _Verdict(view: local, hasTotality: d.totalMinutes != null),
              if (local.moonEvents.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    for (final e in local.moonEvents)
                      if (parseUtc(e.utc) case final t?)
                        (e.kind == SkyKind.moonrise
                            ? l.lunarMoonrise
                            : l.lunarMoonset)(
                          localClock(t.toLocal(), ref, seconds: false),
                        ),
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ],
            const SizedBox(height: 8),
            Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: local == null
                  ? const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1)}
                  : const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(0.55),
                      3: FlexColumnWidth(1.1),
                      4: FlexColumnWidth(0.8),
                    },
              children: rows,
            ),
            if (local == null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(l.lunarNeedsLocation, style: muted)),
                  if (onSetLocation != null)
                    TextButton(
                      onPressed: onSetLocation,
                      child: Text(l.tonightSetLocation),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _cell(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
    child: child,
  );

  TableRow _phaseRow(
    BuildContext context,
    AppLocalizations l,
    EclipsePhase p,
    DateTime ref, {
    required bool strong,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: strong ? FontWeight.w600 : null,
    );
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final small = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final t = parseUtc(p.utc)?.toLocal();
    final h = p.horizon;
    // 月亮在地平线下的食相整行变灰，高度写负数
    final up = h == null || h.moonAltitudeDeg > 0;
    final alt = up ? body : muted;
    final code = p.code == 'Max' ? '' : ' ${p.code}';
    final otherDay =
        t != null &&
        (t.year != ref.year || t.month != ref.month || t.day != ref.day);
    return TableRow(
      children: [
        _cell(Text('${p.name}$code', style: body)),
        _cell(
          t == null
              ? Text(p.utc, style: body)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(localClock(t, t), style: body),
                    if (otherDay) Text('${t.month}/${t.day}', style: small),
                  ],
                ),
        ),
        if (detail.local != null) ...[
          _cell(
            h == null
                ? const SizedBox.shrink()
                : Text('${h.moonAltitudeDeg.round()}°', style: alt),
          ),
          _cell(
            h == null
                ? const SizedBox.shrink()
                : Text(compassPoint(l, h.moonAzimuthDeg), style: alt),
          ),
          _cell(
            h == null
                ? const SizedBox.shrink()
                : Text(skyText(l, h.sunAltitudeDeg), style: small),
          ),
        ],
      ],
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.view, required this.hasTotality});

  final LocalLunarView view;
  final bool hasTotality;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final v = view.verdict;
    final (icon, color) = switch (v) {
      LunarVisibility.full => (Icons.visibility_outlined, cs.primary),
      LunarVisibility.hidden => (Icons.visibility_off_outlined, cs.error),
      _ => (Icons.flaky_outlined, cs.tertiary),
    };
    final lines = [
      visibilityText(l, v),
      if (hasTotality && v != LunarVisibility.hidden)
        view.totalityVisible ? l.lunarTotalityVisible : l.lunarTotalityHidden,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lines.first,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final s in lines.skip(1))
                Text(s, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
