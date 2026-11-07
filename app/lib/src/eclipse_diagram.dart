import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'errors.dart';
import 'locale.dart';
import 'rust/api/guanxiang.dart';
import 'theme.dart';
import 'time_format.dart';

/// 日月食详情页里的示意图（NASA 星表风格）：月食画地影和月球的经过，日食画影子扫过地球的轨迹。
class EclipseDiagramCard extends StatefulWidget {
  const EclipseDiagramCard({
    super.key,
    required this.engine,
    required this.event,
  });

  final Engine engine;
  final EventItem event;

  static bool supports(EventKind k) =>
      k == EventKind.solarEclipse || k == EventKind.lunarEclipse;

  @override
  State<EclipseDiagramCard> createState() => _EclipseDiagramCardState();
}

class _EclipseDiagramCardState extends State<EclipseDiagramCard> {
  Future<Object>? _future;
  Lang? _lang;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = rustLang(context);
    if (lang == _lang) return;
    _lang = lang;
    final e = widget.event;
    _future = e.kind == EventKind.lunarEclipse
        ? lunarEclipseDiagram(engine: widget.engine, ttJd: e.ttJd, lang: lang)
        : solarEclipseDiagram(engine: widget.engine, ttJd: e.ttJd, lang: lang);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: FutureBuilder<Object>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(
                describeError(snap.error!, l),
                style: TextStyle(color: theme.colorScheme.error),
              );
            }
            final d = snap.data;
            if (d == null) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final (Widget figure, String caption) = switch (d) {
              final LunarEclipseDiagram x => (
                _LunarFigure(diagram: x),
                l.diagramLunarCaption,
              ),
              final SolarEclipseDiagram x => (
                _SolarFigure(diagram: x),
                x.umbraRadius > 0
                    ? l.diagramSolarCaptionAnnular
                    : l.diagramSolarCaption,
              ),
              _ => (const SizedBox.shrink(), ''),
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.diagramTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: AspectRatio(aspectRatio: 1, child: figure),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  caption,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 示意图共用的颜色和字体。
class _Palette {
  _Palette(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    ink = cs.onSurface;
    muted = cs.onSurfaceVariant;
    line = cs.outline;
    // 本影必须比半影暗：浅色主题往前景色（深）混，深色主题往黑色混
    final dark = theme.brightness == Brightness.dark;
    fillLight = Color.alphaBlend(
      cs.onSurface.withValues(alpha: dark ? 0.12 : 0.07),
      cs.surface,
    );
    fillDark = dark
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.6), cs.surface)
        : Color.alphaBlend(cs.onSurface.withValues(alpha: 0.32), cs.surface);
    accent = AstroAccents.of(context).eclipse;
    primary = cs.primary;
    surface = cs.surface;
    label = (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
        .copyWith(color: cs.onSurfaceVariant);
  }

  late final Color ink;
  late final Color muted;
  late final Color line;
  late final Color fillLight;
  late final Color fillDark;
  late final Color accent;
  late final Color primary;
  late final Color surface;
  late final TextStyle label;
}

void _text(
  Canvas canvas,
  String s,
  Offset at,
  TextStyle style, {
  Alignment align = Alignment.center,
}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final o =
      at - Offset((align.x + 1) / 2 * tp.width, (align.y + 1) / 2 * tp.height);
  tp.paint(canvas, o);
}

void _arrowHead(Canvas canvas, Offset tip, Offset from, Paint paint) {
  final dir = tip - from;
  final len = dir.distance;
  if (len == 0) return;
  final u = dir / len;
  final n = Offset(-u.dy, u.dx);
  const s = 7.0;
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - u.dx * s + n.dx * s * 0.5,
        tip.dy - u.dy * s + n.dy * s * 0.5,
      )
      ..lineTo(
        tip.dx - u.dx * s - n.dx * s * 0.5,
        tip.dy - u.dy * s - n.dy * s * 0.5,
      )
      ..close(),
    paint..style = PaintingStyle.fill,
  );
}

void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
  const dashes = 48;
  for (var i = 0; i < dashes; i += 2) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      i * 2 * math.pi / dashes,
      2 * math.pi / dashes,
      false,
      paint,
    );
  }
}

// ---------------------------------------------------------------------------
// 月食
// ---------------------------------------------------------------------------

class _LunarFigure extends StatelessWidget {
  const _LunarFigure({required this.diagram});

  final LunarEclipseDiagram diagram;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _LunarPainter(diagram, _Palette(context)),
    size: Size.infinite,
  );
}

class _LunarPainter extends CustomPainter {
  _LunarPainter(this.d, this.p);

  final LunarEclipseDiagram d;
  final _Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // 半影加一个月球直径正好放进图里
    final extent = d.penumbraDeg + 2.4 * d.moonSemidiameterDeg;
    final k = size.shortestSide / 2 / extent;
    // 北在上、东在左（抬头看到的方向）
    Offset at(DiagramPoint q) => c + Offset(-q.x * k, -q.y * k);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawCircle(c, d.penumbraDeg * k, Paint()..color = p.fillLight);
    canvas.drawCircle(c, d.umbraDeg * k, Paint()..color = p.fillDark);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = p.line;
    canvas.drawCircle(c, d.penumbraDeg * k, edge);
    canvas.drawCircle(c, d.umbraDeg * k, edge);
    // 黄道附近的十字：地影中心
    final cross = Paint()
      ..strokeWidth = 1
      ..color = p.line;
    canvas.drawLine(c - const Offset(5, 0), c + const Offset(5, 0), cross);
    canvas.drawLine(c - const Offset(0, 5), c + const Offset(0, 5), cross);

    // 月心轨迹
    final path = Path();
    for (final (i, q) in d.path.indexed) {
      final o = at(q);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = p.muted;
    canvas.drawPath(path, track);
    if (d.path.length >= 2) {
      _arrowHead(
        canvas,
        at(d.path.last),
        at(d.path[d.path.length - 2]),
        Paint()..color = p.muted,
      );
    }

    // 各接触点和食甚时的月球
    final r = d.moonSemidiameterDeg * k;
    for (final (i, m) in d.marks.indexed) {
      final o = at(m);
      final greatest = i == d.marks.length - 1;
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..color = greatest
              ? p.accent.withValues(alpha: 0.55)
              : p.surface.withValues(alpha: 0.35),
      );
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = greatest ? 1.6 : 1
          ..color = greatest ? p.accent : p.ink.withValues(alpha: 0.6),
      );
      // 标签放在月球外侧（远离地影中心的方向）
      final out = o - c;
      final dir = out.distance < 1 ? const Offset(0, -1) : out / out.distance;
      _text(
        canvas,
        m.label,
        o + dir * (r + 9),
        p.label.copyWith(
          color: greatest ? p.accent : p.muted,
          fontWeight: greatest ? FontWeight.w700 : null,
        ),
      );
    }
    canvas.restore();

    // 方位
    _text(canvas, 'N', Offset(c.dx, 8), p.label, align: Alignment.topCenter);
    _text(canvas, 'E', Offset(6, c.dy), p.label, align: Alignment.centerLeft);
  }

  @override
  bool shouldRepaint(_LunarPainter old) => old.d != d;
}

// ---------------------------------------------------------------------------
// 日食
// ---------------------------------------------------------------------------

class _SolarFigure extends StatelessWidget {
  const _SolarFigure({required this.diagram});

  final SolarEclipseDiagram diagram;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SolarPainter(diagram, _Palette(context)),
    size: Size.infinite,
  );
}

class _SolarPainter extends CustomPainter {
  _SolarPainter(this.d, this.p);

  final SolarEclipseDiagram d;
  final _Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    var extent = 1.15;
    for (final q in d.track) {
      extent = math.max(extent, math.max(q.x.abs(), q.y.abs()) + 0.08);
    }
    extent = math.max(
      extent,
      math.max(d.greatest.x.abs(), d.greatest.y.abs()) + d.penumbraRadius,
    );
    final k = size.shortestSide / 2 / extent;
    // 从太阳方向看地球：北在上、东在右
    Offset at(double x, double y) => c + Offset(x * k, -y * k);

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 地球
    canvas.drawCircle(c, k, Paint()..color = p.fillLight);
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = p.line;
    canvas.drawCircle(c, k, thin);
    // 赤道（朝向太阳的半边）和地轴
    final dec = d.axisDeclinationDeg * math.pi / 180;
    final equator = Path();
    for (var i = 0; i <= 60; i++) {
      final h = -math.pi / 2 + math.pi * i / 60;
      final o = at(math.sin(h), -math.sin(dec) * math.cos(h));
      i == 0 ? equator.moveTo(o.dx, o.dy) : equator.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(equator, thin);
    final pole = at(0, math.cos(dec) * (dec >= 0 ? 1 : -1));
    canvas.drawLine(at(0, 0), pole, thin);
    canvas.drawCircle(pole, 2, Paint()..color = p.line);

    // 食甚时的半影（虚线圆）和本影（实心点）
    final g = at(d.greatest.x, d.greatest.y);
    _dashedCircle(
      canvas,
      g,
      d.penumbraRadius * k,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = p.accent,
    );

    // 影轴轨迹，每小时一个点
    final path = Path();
    for (final (i, q) in d.track.indexed) {
      final o = at(q.x, q.y);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = p.primary,
    );
    if (d.track.length >= 2) {
      final a = d.track[d.track.length - 2];
      final b = d.track.last;
      _arrowHead(
        canvas,
        at(b.x, b.y),
        at(a.x, a.y),
        Paint()..color = p.primary,
      );
    }
    for (var i = 0; i < d.track.length - 1; i += 12) {
      final q = d.track[i];
      final o = at(q.x, q.y);
      canvas.drawCircle(o, 2.5, Paint()..color = p.primary);
      final t = parseUtc(q.utc)?.toLocal();
      if (t != null) {
        _text(
          canvas,
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
          o + const Offset(0, 10),
          p.label,
          align: Alignment.topCenter,
        );
      }
    }

    canvas.drawCircle(
      g,
      math.max(d.umbraRadius.abs() * k, 3),
      Paint()..color = p.ink,
    );
    _text(
      canvas,
      d.greatest.label,
      g + const Offset(0, -8),
      p.label.copyWith(color: p.accent, fontWeight: FontWeight.w700),
      align: Alignment.bottomCenter,
    );
    canvas.restore();

    _text(canvas, 'N', Offset(c.dx, 8), p.label, align: Alignment.topCenter);
    _text(
      canvas,
      'E',
      Offset(size.width - 6, c.dy),
      p.label,
      align: Alignment.centerRight,
    );
  }

  @override
  bool shouldRepaint(_SolarPainter old) => old.d != d;
}
