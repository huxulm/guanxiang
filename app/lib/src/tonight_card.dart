import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';
import 'event_style.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'settings.dart';
import 'time_format.dart';

/// “今晚”的时间窗口起点：本地中午；凌晨 6 点前仍算前一晚，从前一天中午起。
DateTime tonightStart(DateTime now) {
  final l = now.toLocal();
  return DateTime(l.year, l.month, l.day - (l.hour < 6 ? 1 : 0), 12);
}

String _isoUtc(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)}T'
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
}

/// 看板上的“今晚”：日落、天黑（天文晨昏结束）、天亮（天文晨光开始）、日出，月出月落和月相。
///
/// 只用手动设置的观测地或已有的 GPS 定位，不为这张卡片主动定位。
class TonightCard extends StatefulWidget {
  const TonightCard({
    super.key,
    required this.engine,
    required this.settings,
    this.onSetLocation,
  });

  final Engine engine;
  final Settings settings;
  final VoidCallback? onSetLocation;

  @override
  State<TonightCard> createState() => _TonightCardState();
}

class _TonightCardState extends State<TonightCard> {
  late final Timer _timer;
  String? _key;
  Future<Tonight>? _future;

  @override
  void initState() {
    super.initState();
    // 过了中午或凌晨 6 点要换一晚；每 5 分钟检查一次
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Place? _place(Settings s) {
    return s.mode == LocationMode.manual
        ? (s.manual.isValid ? s.manual : null)
        : s.gpsFix;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final l = AppLocalizations.of(context);
        final place = _place(widget.settings);
        if (place == null) return _needsLocation(context, l);
        final start = tonightStart(DateTime.now());
        final lang = rustLang(context);
        final key =
            '${place.lat},${place.lon},${place.height},${start.toIso8601String()},$lang';
        if (key != _key) {
          _key = key;
          _future = tonight(
            engine: widget.engine,
            latitudeDeg: place.lat,
            longitudeDeg: place.lon,
            heightM: place.height,
            startUtc: _isoUtc(start),
            hours: 24,
            lang: lang,
          );
        }
        return FutureBuilder<Tonight>(
          future: _future,
          builder: (context, snap) => _frame(
            context,
            l,
            snap.hasError
                ? Text(
                    describeError(snap.error!, l),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : !snap.hasData
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _content(context, l, snap.data!, southern: place.lat < 0),
          ),
        );
      },
    );
  }

  Widget _frame(BuildContext context, AppLocalizations l, Widget child) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bedtime_outlined,
                  size: 20,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  l.tonightTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: l.tonightDarkHint,
                  triggerMode: TooltipTriggerMode.tap,
                  child: Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _needsLocation(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    return _frame(
      context,
      l,
      Row(
        children: [
          Expanded(
            child: Text(
              l.tonightNeedsLocation,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (widget.onSetLocation != null)
            TextButton(
              onPressed: widget.onSetLocation,
              child: Text(l.tonightSetLocation),
            ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l,
    Tonight t, {
    required bool southern,
  }) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    DateTime? first(SkyKind k) {
      for (final e in t.events) {
        if (e.kind == k) return parseUtc(e.utc)?.toLocal();
      }
      return null;
    }

    final sunset = first(SkyKind.sunset);
    final dusk = first(SkyKind.astronomicalDusk);
    final dawn = first(SkyKind.astronomicalDawn);
    final sunrise = first(SkyKind.sunrise);

    // 天黑时长，或极昼、极夜、白夜的说明
    final String darkLine;
    if (dusk != null && dawn != null && dawn.isAfter(dusk)) {
      final d = dawn.difference(dusk);
      darkLine = l.tonightDark(d.inHours, d.inMinutes % 60);
    } else if (sunset == null && sunrise == null) {
      darkLine = t.sunAltitudeDeg > 0 ? l.tonightPolarDay : l.tonightPolarNight;
    } else {
      darkLine = l.tonightWhiteNight;
    }

    final m = t.moon;
    final moonrise = first(SkyKind.moonrise);
    final moonset = first(SkyKind.moonset);
    // 朔、望里较近的一个
    final full = parseUtc(m.nextFullUtc);
    final newMoon = parseUtc(m.nextNewUtc);
    String? nextPhase;
    if (full != null && (newMoon == null || full.isBefore(newMoon))) {
      final w = countdown(l, full);
      if (w != null) nextPhase = l.tonightNextFull(w);
    } else if (newMoon != null) {
      final w = countdown(l, newMoon);
      if (w != null) nextPhase = l.tonightNextNew(w);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _TimeCell(label: l.tonightSunset, time: sunset),
            _TimeCell(label: l.tonightDusk, time: dusk),
            _TimeCell(label: l.tonightDawn, time: dawn),
            _TimeCell(label: l.tonightSunrise, time: sunrise),
          ],
        ),
        const SizedBox(height: 8),
        Text(darkLine, style: muted),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Row(
          children: [
            MoonPhaseIcon(
              fraction: m.illuminatedFraction,
              waxing: m.waxing,
              southern: southern,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${m.phaseName} · '
                    '${l.tonightIllumination((m.illuminatedFraction * 100).round())}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${l.tonightMoonrise} ${_hm(moonrise)} · '
                    '${l.tonightMoonset} ${_hm(moonset)}',
                    style: muted,
                  ),
                  if (nextPhase != null) Text(nextPhase, style: muted),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _hm(DateTime? t) => t == null
    ? '—'
    : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.label, required this.time});

  final String label;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _hm(time),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 月相图标：按照亮比例和盈亏画出亮面。北半球上半月亮在右侧，南半球相反。
class MoonPhaseIcon extends StatelessWidget {
  const MoonPhaseIcon({
    super.key,
    required this.fraction,
    required this.waxing,
    this.southern = false,
    this.size = 40,
  });

  final double fraction;
  final bool waxing;
  final bool southern;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: _MoonPainter(
        fraction: fraction.clamp(0.0, 1.0),
        litRight: waxing != southern,
        lit: cs.onSurface,
        dark: cs.surfaceContainerHigh,
        outline: cs.outline,
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  _MoonPainter({
    required this.fraction,
    required this.litRight,
    required this.lit,
    required this.dark,
    required this.outline,
  });

  final double fraction;
  final bool litRight;
  final Color lit;
  final Color dark;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final disc = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    canvas.drawRect(disc, Paint()..color = dark);
    // 亮的半边
    canvas.drawArc(
      disc,
      -math.pi / 2,
      litRight ? math.pi : -math.pi,
      true,
      Paint()..color = lit,
    );
    // 明暗界线是半宽 r·|2k−1| 的椭圆：不足一半时盖暗色，超过一半时补亮色
    final w = r * (2 * fraction - 1).abs();
    canvas.drawOval(
      Rect.fromCenter(center: c, width: 2 * w, height: 2 * r),
      Paint()..color = fraction < 0.5 ? dark : lit,
    );
    canvas.restore();
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(_MoonPainter old) =>
      old.fraction != fraction ||
      old.litRight != litRight ||
      old.lit != lit ||
      old.dark != dark ||
      old.outline != outline;
}
