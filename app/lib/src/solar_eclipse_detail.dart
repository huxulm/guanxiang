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
                const SizedBox(height: 16),
                EclipseDiagramCard(engine: widget.engine, event: widget.event),
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
