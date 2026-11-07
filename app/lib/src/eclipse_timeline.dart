import 'package:flutter/material.dart';

import 'time_format.dart';

/// 时间轴上的一段：从食相 [from] 到 [to]，用 [color] 填色。
class TimelineSegment {
  const TimelineSegment(this.from, this.to, this.color);

  final String from;
  final String to;
  final Color color;
}

/// 日月食通用的横向时间轴：第一个到最后一个食相按时间比例画成横条，底色 [base]，
/// 再按 [segments] 分段填色；上面标食相代号（食甚 `Max` 画成 ★），下面标本地时刻。
/// [below] 中的时段（天体在地平线下）画斜线。
class EclipseTimeline extends StatelessWidget {
  const EclipseTimeline({
    super.key,
    required this.phases,
    required this.base,
    required this.segments,
    required this.greatest,
    this.below = const [],
  });

  /// (代号, UTC 时刻)，按时间顺序
  final List<(String, DateTime)> phases;
  final Color base;
  final List<TimelineSegment> segments;
  final Color greatest;
  final List<(DateTime, DateTime)> below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
        .copyWith(color: cs.onSurfaceVariant);
    return SizedBox(
      height: 84,
      width: double.infinity,
      child: CustomPaint(
        painter: _TimelinePainter(
          phases: phases,
          base: base,
          segments: segments,
          greatest: greatest,
          below: below,
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

/// 由取样时刻和高度（度）求出在地平线下的时段；相邻取样点之间线性插值找零点。
List<(DateTime, DateTime)> belowHorizonIntervals(
  List<DateTime> times,
  List<double> altitudes,
) {
  final n = times.length < altitudes.length ? times.length : altitudes.length;
  final out = <(DateTime, DateTime)>[];
  DateTime? start;
  for (var i = 0; i < n; i++) {
    final down = altitudes[i] <= 0;
    if (i == 0) {
      if (down) start = times[0];
      continue;
    }
    if ((altitudes[i - 1] <= 0) == down) continue;
    final a = altitudes[i - 1], b = altitudes[i];
    final f = a / (a - b);
    final span = times[i].difference(times[i - 1]).inMilliseconds;
    final tc = times[i - 1].add(Duration(milliseconds: (span * f).round()));
    if (down) {
      start = tc;
    } else if (start != null) {
      out.add((start, tc));
      start = null;
    }
  }
  if (start != null && n > 0) out.add((start, times[n - 1]));
  return out;
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.phases,
    required this.base,
    required this.segments,
    required this.greatest,
    required this.below,
    required this.hatch,
    required this.label,
    required this.strongLabel,
  });

  final List<(String, DateTime)> phases;
  final Color base;
  final List<TimelineSegment> segments;
  final Color greatest;
  final List<(DateTime, DateTime)> below;
  final Color hatch;
  final TextStyle label;
  final TextStyle strongLabel;

  static const _barTop = 34.0;
  static const _barHeight = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
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
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(bar, const Radius.circular(4)));
    canvas.drawRect(bar, Paint()..color = base);
    for (final s in segments) {
      final (a, b) = (at(s.from), at(s.to));
      if (a == null || b == null) continue;
      canvas.drawRect(
        Rect.fromLTRB(x(a), _barTop, x(b), _barTop + _barHeight),
        Paint()..color = s.color,
      );
    }
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
      final local = t.toLocal();
      _place(
        canvas,
        isMax ? '★' : code,
        cx,
        (row) => _barTop - 4 - row * 14,
        true,
        isMax ? strongLabel.copyWith(color: greatest) : label,
        codeRows,
        size.width,
      );
      _place(
        canvas,
        '${_two(local.hour)}:${_two(local.minute)}',
        cx,
        (row) => _barTop + _barHeight + 4 + row * 14,
        false,
        isMax ? strongLabel : label,
        timeRows,
        size.width,
      );
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  void _place(
    Canvas canvas,
    String text,
    double cx,
    double Function(int row) y,
    bool above,
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
      final top = above ? y(row) - tp.height : y(row);
      final r = Rect.fromLTWH(left - 2, top, tp.width + 4, tp.height);
      if (rows[row].any((o) => o.overlaps(r))) continue;
      rows[row].add(r);
      tp.paint(canvas, Offset(left, top));
      return;
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.phases != phases ||
      old.base != base ||
      old.below != below ||
      old.label != label;
}

/// 解析一组 (代号, UTC 字符串)，丢掉解析不了的。
List<(String, DateTime)> parsePhases(Iterable<(String, String)> phases) => [
  for (final (code, utc) in phases)
    if (parseUtc(utc) case final t?) (code, t),
];
