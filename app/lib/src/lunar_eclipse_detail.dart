import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'eclipse_diagram.dart';
import 'eclipse_timeline.dart';
import 'errors.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'time_format.dart';
import 'world_map.dart';

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
            _SimulationCard(detail: d),
            const SizedBox(height: 16),
            _WorldMapCard(detail: d, place: place),
            const SizedBox(height: 16),
            const _ObservingTips(),
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
                  DetailChip(text: c, strong: i == 0 && d.totalMinutes != null),
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

/// 详情页里的小标签（持续时间、食分等）。
class DetailChip extends StatelessWidget {
  const DetailChip({super.key, required this.text, this.strong = false});

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

/// 月食时间轴：P1 到 P4 按时间比例分段（半影浅、本影深、全食古铜红）；
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
    final local = detail.local;
    final times = [
      for (final p in detail.diagram.path) parseUtc(p.utc) ?? DateTime.utc(0),
    ];
    return EclipseTimeline(
      phases: parsePhases(detail.phases.map((p) => (p.code, p.utc))),
      base: Color.alphaBlend(
        cs.onSurface.withValues(alpha: dark ? 0.16 : 0.10),
        cs.surface,
      ),
      segments: [
        TimelineSegment(
          'U1',
          'U4',
          Color.alphaBlend(
            cs.onSurface.withValues(alpha: dark ? 0.42 : 0.38),
            cs.surface,
          ),
        ),
        TimelineSegment('U2', 'U3', accents.bloodMoon),
      ],
      greatest: accents.eclipse,
      below: local == null
          ? const []
          : belowHorizonIntervals(times, local.trackAltitudeDeg),
    );
  }
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

// ---------------------------------------------------------------------------
// 可拖动的示意图和月面模拟
// ---------------------------------------------------------------------------

/// 沿示意图轨迹按时刻插值：月心位置和（有观测地时）月亮高度。
class TrackSampler {
  TrackSampler(this.diagram, this.altitudes)
    : _ms = [
        for (final p in diagram.path)
          parseUtc(p.utc)?.millisecondsSinceEpoch ?? 0,
      ];

  final LunarEclipseDiagram diagram;
  final List<double>? altitudes;
  final List<int> _ms;

  DateTime get start =>
      DateTime.fromMillisecondsSinceEpoch(_ms.first, isUtc: true);
  DateTime get end =>
      DateTime.fromMillisecondsSinceEpoch(_ms.last, isUtc: true);

  /// 时刻 t 落在第 i、i+1 个取样点之间的位置：(i, 比例)
  (int, double) _locate(DateTime t) {
    final ms = t.millisecondsSinceEpoch;
    if (ms <= _ms.first) return (0, 0);
    if (ms >= _ms.last) return (_ms.length - 2, 1);
    var lo = 0, hi = _ms.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_ms[mid] <= ms) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _ms[hi] - _ms[lo];
    return (lo, span == 0 ? 0 : (ms - _ms[lo]) / span);
  }

  /// 月心相对地影中心的位置（度）
  Offset positionAt(DateTime t) {
    final path = diagram.path;
    if (path.length < 2) return Offset(path.first.x, path.first.y);
    final (i, f) = _locate(t);
    final a = path[i], b = path[i + 1];
    return Offset(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f);
  }

  /// 月亮视高度（度）；没有观测地时为 null
  double? altitudeAt(DateTime t) {
    final alt = altitudes;
    if (alt == null || alt.length != _ms.length || alt.length < 2) return null;
    final (i, f) = _locate(t);
    return alt[i] + (alt[i + 1] - alt[i]) * f;
  }
}

/// 此刻处在哪个阶段。
String lunarStateText(
  AppLocalizations l,
  List<EclipsePhase> phases,
  DateTime t,
) {
  DateTime? at(String code) {
    for (final p in phases) {
      if (p.code == code) return parseUtc(p.utc);
    }
    return null;
  }

  bool inside(String a, String b) {
    final (x, y) = (at(a), at(b));
    return x != null && y != null && !t.isBefore(x) && !t.isAfter(y);
  }

  if (inside('U2', 'U3')) return l.lunarStateTotal;
  if (inside('U1', 'U4')) return l.lunarStatePartial;
  if (inside('P1', 'P4')) return l.lunarStatePenumbral;
  final p1 = at('P1');
  return p1 != null && t.isBefore(p1) ? l.lunarStateBefore : l.lunarStateAfter;
}

class _SimulationCard extends StatefulWidget {
  const _SimulationCard({required this.detail});

  final LunarEclipseDetail detail;

  @override
  State<_SimulationCard> createState() => _SimulationCardState();
}

class _SimulationCardState extends State<_SimulationCard> {
  late TrackSampler _track;
  late DateTime _t;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(_SimulationCard old) {
    super.didUpdateWidget(old);
    if (old.detail != widget.detail) {
      final keep = _t;
      _reset();
      if (!keep.isBefore(_track.start) && !keep.isAfter(_track.end)) _t = keep;
    }
  }

  void _reset() {
    final d = widget.detail;
    _track = TrackSampler(d.diagram, d.local?.trackAltitudeDeg);
    final max = d.phases.where((p) => p.code == 'Max').firstOrNull;
    _t = (max == null ? null : parseUtc(max.utc)) ?? _track.start;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final d = widget.detail;
    final pos = _track.positionAt(_t);
    final alt = _track.altitudeAt(_t);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final total = _track.end.difference(_track.start).inSeconds.toDouble();
    final value = _t.difference(_track.start).inSeconds.toDouble();
    final local = _t.toLocal();

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
          lunarStateText(l, d.phases, _t),
          style: theme.textTheme.bodyLarge?.copyWith(color: cs.primary),
        ),
        if (alt != null)
          Text(
            alt > 0 ? l.lunarMoonAlt(alt.round()) : l.lunarMoonDown,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: alt > 0 ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
      ],
    );
    final face = SizedBox.square(
      dimension: 112,
      child: CustomPaint(
        painter: _MoonFacePainter(
          diagram: d.diagram,
          position: pos,
          accents: AstroAccents.of(context),
          edge: cs.outline,
        ),
      ),
    );
    final figure = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: AspectRatio(
        aspectRatio: 1,
        child: LunarShadowFigure(diagram: d.diagram, current: pos),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.diagramTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) => c.maxWidth >= 560
                  ? Row(
                      children: [
                        Expanded(child: Center(child: figure)),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 180,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              face,
                              const SizedBox(height: 12),
                              readout,
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Center(child: figure),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            face,
                            const SizedBox(width: 16),
                            Expanded(child: readout),
                          ],
                        ),
                      ],
                    ),
            ),
            Slider(
              key: const ValueKey('lunarSlider'),
              value: value.clamp(0, total),
              max: total,
              label: localClock(local, local, seconds: false),
              semanticFormatterCallback: (_) =>
                  '${l.lunarSliderLabel} ${localClock(local, local)}',
              onChanged: (v) => setState(
                () => _t = _track.start.add(Duration(seconds: v.round())),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in d.phases)
                  if (parseUtc(p.utc) case final t?)
                    ChoiceChip(
                      label: Text(p.code == 'Max' ? p.name : p.code),
                      selected: t.difference(_t).inSeconds.abs() < 30,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _t = t),
                    ),
              ],
            ),
            const SizedBox(height: 10),
            Text(l.lunarDiagramCaption, style: muted),
            const SizedBox(height: 6),
            Text(l.lunarDanjonNote, style: muted),
          ],
        ),
      ),
    );
  }
}

/// 月面（分享图等处用）：[position] 为月心相对地影中心的位置（度）。
class MoonFace extends StatelessWidget {
  const MoonFace({super.key, required this.diagram, required this.position});

  final LunarEclipseDiagram diagram;
  final Offset position;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MoonFacePainter(
      diagram: diagram,
      position: position,
      accents: AstroAccents.of(context),
      edge: Colors.transparent,
    ),
    size: Size.infinite,
  );
}

/// 放大的月面：月心放在中间，地影按它与月心的相对位置画上去。
class _MoonFacePainter extends CustomPainter {
  _MoonFacePainter({
    required this.diagram,
    required this.position,
    required this.accents,
    required this.edge,
  });

  final LunarEclipseDiagram diagram;
  final Offset position;
  final AstroAccents accents;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    final k = r / diagram.moonSemidiameterDeg;
    // 北在上、东在左：月心在 (-x, -y)·k 处，所以地影中心相对月心在 (+x, +y)·k
    final shadow = c + Offset(position.dx * k, position.dy * k);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = lunarShadowShader(
          shadow,
          diagram.umbraDeg * k,
          diagram.penumbraDeg * k,
          accents,
        ),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(_MoonFacePainter old) =>
      old.position != position ||
      old.diagram != diagram ||
      old.accents != accents;
}

// ---------------------------------------------------------------------------
// 全球可见区域
// ---------------------------------------------------------------------------

/// 地图上的分区。
enum LunarZone { full, rises, sets, hidden }

/// 按网格划分可见区域：月偏食、月全食按 U1、U4，半影月食按 P1、P4 时月亮的地心高度。
/// 返回 (行数, 列数, 分区)，第 0 行是最北一行（中心纬度 90 − step/2），第 0 列中心经度 −180 + step/2。
(int, int, List<LunarZone>) lunarVisibilityGrid(
  List<EclipsePhase> phases, {
  double step = 2,
}) {
  EclipsePhase? find(String code) =>
      phases.where((p) => p.code == code).firstOrNull;
  final start = find('U1') ?? find('P1') ?? phases.first;
  final end = find('U4') ?? find('P4') ?? phases.last;
  final rows = (180 / step).round();
  final cols = (360 / step).round();
  final zones = List<LunarZone>.filled(rows * cols, LunarZone.hidden);
  for (var r = 0; r < rows; r++) {
    final lat = 90 - (r + 0.5) * step;
    for (var c = 0; c < cols; c++) {
      final lon = -180 + (c + 0.5) * step;
      final a =
          geocentricAltitude(
            lat,
            lon,
            start.sublunar.latitudeDeg,
            start.sublunar.longitudeDeg,
          ) >
          0;
      final b =
          geocentricAltitude(
            lat,
            lon,
            end.sublunar.latitudeDeg,
            end.sublunar.longitudeDeg,
          ) >
          0;
      zones[r * cols + c] = a && b
          ? LunarZone.full
          : b
          ? LunarZone.rises
          : a
          ? LunarZone.sets
          : LunarZone.hidden;
    }
  }
  return (rows, cols, zones);
}

class _WorldMapCard extends StatefulWidget {
  const _WorldMapCard({required this.detail, this.place});

  final LunarEclipseDetail detail;
  final Place? place;

  @override
  State<_WorldMapCard> createState() => _WorldMapCardState();
}

class _WorldMapCardState extends State<_WorldMapCard> {
  static const _step = 2.0;
  late (int, int, List<LunarZone>) _grid;

  @override
  void initState() {
    super.initState();
    _grid = lunarVisibilityGrid(widget.detail.phases, step: _step);
  }

  @override
  void didUpdateWidget(_WorldMapCard old) {
    super.didUpdateWidget(old);
    if (old.detail != widget.detail) {
      _grid = lunarVisibilityGrid(widget.detail.phases, step: _step);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final accents = AstroAccents.of(context);
    final d = widget.detail;
    final max = d.phases.where((p) => p.code == 'Max').firstOrNull;
    final center = max?.sublunar.longitudeDeg ?? 0;
    final colors = {
      LunarZone.full: Colors.transparent,
      LunarZone.rises: cs.primary.withValues(alpha: 0.22),
      LunarZone.sets: cs.tertiary.withValues(alpha: 0.26),
      LunarZone.hidden: Colors.black.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.45 : 0.30,
      ),
    };
    final label = (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
        .copyWith(color: cs.onSurface, fontWeight: FontWeight.w600);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final place = widget.place;

    void fill(Canvas canvas, MapProjection p) {
      // 同一分区的格子并成一条路径一次画完，格子之间不会透出缝
      final (rows, cols, zones) = _grid;
      final cell = _step * p.k;
      final paths = {for (final z in LunarZone.values) z: Path()};
      for (var r = 0; r < rows; r++) {
        final y = r * cell;
        for (var c = 0; c < cols; c++) {
          final z = zones[r * cols + c];
          if (z == LunarZone.full) continue;
          final o = p.at(90 - (r + 0.5) * _step, -180 + (c + 0.5) * _step);
          paths[z]!.addRect(Rect.fromLTWH(o.dx - cell / 2, y, cell, cell));
        }
      }
      for (final MapEntry(key: z, value: path) in paths.entries) {
        if (z == LunarZone.full) continue;
        canvas.drawPath(
          path,
          Paint()
            ..color = colors[z]!
            ..isAntiAlias = false,
        );
      }
    }

    void marks(Canvas canvas, MapProjection p) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = cs.onSurface.withValues(alpha: 0.75);
      var n = 0;
      for (final ph in d.phases) {
        if (ph.code == 'Max') continue;
        final pts = horizonCircle(
          ph.sublunar.latitudeDeg,
          ph.sublunar.longitudeDeg,
        );
        final path = p.polyline(pts);
        p.drawWrapped(canvas, (c) => c.drawPath(path, line));
        // 标签放在曲线西侧（地下点以西 90° 那一支），纬度分三档错开，相邻曲线的标签不重叠
        final target = const [-12.0, -32.0, -52.0][n++ % 3];
        (double, double)? best;
        for (final q in pts) {
          var dl = q.$2 - ph.sublunar.longitudeDeg;
          dl -= 360 * (dl / 360).round();
          if (dl >= 0) continue;
          if (best == null ||
              (q.$1 - target).abs() < (best.$1 - target).abs()) {
            best = q;
          }
        }
        if (best == null) continue;
        final o = p.at(best.$1, best.$2);
        final tp = TextPainter(
          text: TextSpan(text: ph.code, style: label),
          textDirection: TextDirection.ltr,
        )..layout();
        final box = Rect.fromCenter(
          center: o,
          width: tp.width + 6,
          height: tp.height + 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(3)),
          Paint()..color = cs.surface.withValues(alpha: 0.85),
        );
        tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
      }
      if (max != null) {
        final o = p.at(max.sublunar.latitudeDeg, max.sublunar.longitudeDeg);
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
              l.lunarMapTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: WorldMap(centerLon: center, fill: fill, marks: marks),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                legend(Colors.transparent, l.lunarMapFull),
                legend(colors[LunarZone.rises]!, l.lunarMapRises),
                legend(colors[LunarZone.sets]!, l.lunarMapSets),
                legend(colors[LunarZone.hidden]!, l.lunarMapHidden),
              ],
            ),
            const SizedBox(height: 8),
            Text(l.lunarMapCaption, style: muted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 观测与拍摄提示
// ---------------------------------------------------------------------------

class _ObservingTips extends StatelessWidget {
  const _ObservingTips();

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
            tip(Icons.visibility_outlined, l.lunarTipEyes),
            tip(Icons.photo_camera_outlined, l.lunarTipPhoto),
            tip(Icons.exposure_outlined, l.lunarTipBracket),
            tip(Icons.wb_sunny_outlined, l.lunarTipSolar, color: cs.error),
          ],
        ),
      ),
    );
  }
}
