import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 随应用打包的陆地轮廓（Natural Earth 1:110m，公有领域），由 tools/geo/gen_land.py 生成。
const landAsset = 'assets/geo/land_110m.json';

/// 陆地轮廓：每个多边形是 [经度, 纬度, 经度, 纬度, …]（度）。只加载一次。
class LandOutline {
  LandOutline._(this.rings);

  final List<Float64List> rings;

  static Future<LandOutline>? _loading;

  static Future<LandOutline> load() => _loading ??= _load();

  static Future<LandOutline> _load() async {
    final j = jsonDecode(await rootBundle.loadString(landAsset)) as Map;
    final scale = (j['scale'] as num).toDouble();
    return LandOutline._([
      for (final r in j['rings'] as List)
        Float64List.fromList([for (final v in r as List) (v as num) / scale]),
    ]);
  }
}

/// 等距圆柱投影：经度 `centerLon` 放在正中，北在上；画布宽高比 2:1。
class MapProjection {
  MapProjection(this.size, this.centerLon);

  final Size size;
  final double centerLon;

  /// 每度多少像素
  double get k => size.width / 360;

  /// 不折回的横坐标：经度连续变化时坐标也连续，画的时候再按 ±360° 平移重画
  double rawX(double lon) => (lon - centerLon + 180) * k;

  double y(double lat) => (90 - lat) * k;

  /// 折回到画布内的位置
  Offset at(double lat, double lon) {
    final x = (lon - centerLon + 180) % 360;
    return Offset(x * k, y(lat));
  }

  /// 在三个平移位置（−360°、0、+360°）各画一次，跨过地图左右边缘的图形就完整了。
  void drawWrapped(Canvas canvas, void Function(Canvas canvas) draw) {
    for (final dx in [-360 * k, 0.0, 360 * k]) {
      canvas.save();
      canvas.translate(dx, 0);
      draw(canvas);
      canvas.restore();
    }
  }

  /// 一串 (纬度, 经度) 连成折线：相邻两点经度相差超过 180° 时按另一侧连（不折回）。
  Path polyline(Iterable<(double, double)> points) {
    final path = Path();
    double? prev;
    var lonAcc = 0.0;
    for (final (lat, lon) in points) {
      if (prev == null) {
        lonAcc = lon;
        path.moveTo(rawX(lonAcc), y(lat));
      } else {
        var d = lon - prev;
        d -= 360 * (d / 360).round();
        lonAcc += d;
        path.lineTo(rawX(lonAcc), y(lat));
      }
      prev = lon;
    }
    return path;
  }
}

/// 世界地图：海洋底色、陆地、经纬网。[fill] 画在陆地之上、海岸线之下（填色区域），
/// [marks] 画在最上面（曲线、点、标签）。
class WorldMap extends StatelessWidget {
  const WorldMap({super.key, required this.centerLon, this.fill, this.marks});

  final double centerLon;
  final void Function(Canvas canvas, MapProjection p)? fill;
  final void Function(Canvas canvas, MapProjection p)? marks;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<LandOutline>(
      future: LandOutline.load(),
      builder: (context, snap) => AspectRatio(
        aspectRatio: 2,
        child: CustomPaint(
          painter: _WorldMapPainter(
            land: snap.data,
            centerLon: centerLon,
            ocean: Color.alphaBlend(
              cs.primary.withValues(alpha: dark ? 0.08 : 0.06),
              cs.surface,
            ),
            landFill: Color.alphaBlend(
              cs.onSurface.withValues(alpha: dark ? 0.16 : 0.10),
              cs.surface,
            ),
            coast: cs.onSurfaceVariant.withValues(alpha: 0.7),
            grid: cs.outline.withValues(alpha: 0.6),
            fill: fill,
            marks: marks,
          ),
        ),
      ),
    );
  }
}

class _WorldMapPainter extends CustomPainter {
  _WorldMapPainter({
    required this.land,
    required this.centerLon,
    required this.ocean,
    required this.landFill,
    required this.coast,
    required this.grid,
    this.fill,
    this.marks,
  });

  final LandOutline? land;
  final double centerLon;
  final Color ocean;
  final Color landFill;
  final Color coast;
  final Color grid;
  final void Function(Canvas canvas, MapProjection p)? fill;
  final void Function(Canvas canvas, MapProjection p)? marks;

  @override
  void paint(Canvas canvas, Size size) {
    final p = MapProjection(size, centerLon);
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = ocean);

    final landPath = Path();
    for (final r in land?.rings ?? const <Float64List>[]) {
      for (var i = 0; i < r.length; i += 2) {
        final o = Offset(p.rawX(r[i]), p.y(r[i + 1]));
        i == 0 ? landPath.moveTo(o.dx, o.dy) : landPath.lineTo(o.dx, o.dy);
      }
      landPath.close();
    }
    p.drawWrapped(
      canvas,
      (c) => c.drawPath(landPath, Paint()..color = landFill),
    );

    fill?.call(canvas, p);

    p.drawWrapped(
      canvas,
      (c) => c.drawPath(
        landPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = coast,
      ),
    );

    // 经纬网：每 30°
    final g = Paint()
      ..strokeWidth = 0.5
      ..color = grid;
    for (var lat = -60; lat <= 60; lat += 30) {
      canvas.drawLine(
        Offset(0, p.y(lat.toDouble())),
        Offset(size.width, p.y(lat.toDouble())),
        g,
      );
    }
    for (var lon = -180; lon < 180; lon += 30) {
      final x = p.at(0, lon.toDouble()).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), g);
    }

    marks?.call(canvas, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WorldMapPainter old) =>
      old.land != land ||
      old.centerLon != centerLon ||
      old.fill != fill ||
      old.marks != marks ||
      old.ocean != ocean;
}

/// 天体正好在地平线上的地方（地心计算）：与地下点相距 90° 的大圆，按 (纬度, 经度) 返回。
List<(double, double)> horizonCircle(
  double subLatDeg,
  double subLonDeg, {
  int steps = 180,
}) {
  final phi = subLatDeg * math.pi / 180;
  final lam = subLonDeg * math.pi / 180;
  // s 为地下点单位向量，u、v 与 s 正交
  final s = [
    math.cos(phi) * math.cos(lam),
    math.cos(phi) * math.sin(lam),
    math.sin(phi),
  ];
  // u：沿 s 所在经线指向北（φ+90°）
  final u = [
    -math.sin(phi) * math.cos(lam),
    -math.sin(phi) * math.sin(lam),
    math.cos(phi),
  ];
  final v = [
    s[1] * u[2] - s[2] * u[1],
    s[2] * u[0] - s[0] * u[2],
    s[0] * u[1] - s[1] * u[0],
  ];
  return [
    for (var i = 0; i <= steps; i++)
      () {
        final t = 2 * math.pi * i / steps;
        final (c, sn) = (math.cos(t), math.sin(t));
        final x = c * u[0] + sn * v[0];
        final yv = c * u[1] + sn * v[1];
        final z = c * u[2] + sn * v[2];
        return (
          math.asin(z.clamp(-1.0, 1.0)) * 180 / math.pi,
          math.atan2(yv, x) * 180 / math.pi,
        );
      }(),
  ];
}

/// 地心高度角（度）：观测点 (lat, lon) 看地下点在 (subLat, subLon) 的天体。
double geocentricAltitude(
  double lat,
  double lon,
  double subLat,
  double subLon,
) {
  const r = math.pi / 180;
  final s =
      math.sin(lat * r) * math.sin(subLat * r) +
      math.cos(lat * r) * math.cos(subLat * r) * math.cos((lon - subLon) * r);
  return math.asin(s.clamp(-1.0, 1.0)) / r;
}

/// 栅格等值线（marching squares）：栅格第 r 行第 c 列的格子中心在
/// (90 − (r + 0.5)·step, −180 + (c + 0.5)·step)，经度方向首尾相接。
/// 返回线段列表，每段两个 (纬度, 经度) 端点；经度可能略超出 ±180°，画的时候折回。
List<((double, double), (double, double))> contourSegments(
  List<double> values,
  int rows,
  int cols,
  double step,
  double level,
) {
  final out = <((double, double), (double, double))>[];
  double v(int r, int c) => values[r * cols + (c % cols)];
  (double, double) pos(double r, double c) =>
      (90 - (r + 0.5) * step, -180 + (c + 0.5) * step);
  // 在边 (r0,c0)–(r1,c1) 上插值出等值点
  (double, double) edge(int r0, int c0, int r1, int c1) {
    final a = v(r0, c0), b = v(r1, c1);
    final f = a == b ? 0.5 : (level - a) / (b - a);
    return pos(r0 + (r1 - r0) * f, c0 + (c1 - c0) * f);
  }

  for (var r = 0; r < rows - 1; r++) {
    for (var c = 0; c < cols; c++) {
      // 角点：0 左上 (r,c)，1 右上 (r,c+1)，2 右下 (r+1,c+1)，3 左下 (r+1,c)
      final idx =
          (v(r, c) >= level ? 1 : 0) |
          (v(r, c + 1) >= level ? 2 : 0) |
          (v(r + 1, c + 1) >= level ? 4 : 0) |
          (v(r + 1, c) >= level ? 8 : 0);
      if (idx == 0 || idx == 15) continue;
      final top = edge(r, c, r, c + 1);
      final right = edge(r, c + 1, r + 1, c + 1);
      final bottom = edge(r + 1, c, r + 1, c + 1);
      final left = edge(r, c, r + 1, c);
      void seg((double, double) a, (double, double) b) => out.add((a, b));
      switch (idx) {
        case 1 || 14:
          seg(left, top);
        case 2 || 13:
          seg(top, right);
        case 3 || 12:
          seg(left, right);
        case 4 || 11:
          seg(right, bottom);
        case 6 || 9:
          seg(top, bottom);
        case 7 || 8:
          seg(left, bottom);
        case 5:
          seg(left, top);
          seg(right, bottom);
        case 10:
          seg(top, right);
          seg(left, bottom);
      }
    }
  }
  return out;
}

/// 把线段画成一条路径（不折回的坐标，配合 [MapProjection.drawWrapped] 使用）。
Path segmentsPath(
  MapProjection p,
  Iterable<((double, double), (double, double))> segments,
) {
  final path = Path();
  for (final (a, b) in segments) {
    // 第一个端点放到中心经度 ±180° 内，第二个端点跟着第一个，线段就不会被拆到两边
    var la = a.$2 - p.centerLon;
    la -= 360 * (la / 360).round();
    var db = b.$2 - a.$2;
    db -= 360 * (db / 360).round();
    final lonA = p.centerLon + la;
    path.moveTo(p.rawX(lonA), p.y(a.$1));
    path.lineTo(p.rawX(lonA + db), p.y(b.$1));
  }
  return path;
}

/// 中心线两侧各偏移半个食带宽，围成食带多边形（按 (纬度, 经度) 顺时针或逆时针）。
List<(double, double)> pathBand(
  List<(double, double)> centre,
  List<double> widthKm,
) {
  const kmPerDeg = 111.2;
  final n = centre.length;
  if (n < 2) return const [];
  final left = <(double, double)>[];
  final right = <(double, double)>[];
  for (var i = 0; i < n; i++) {
    final a = centre[i == 0 ? 0 : i - 1];
    final b = centre[i == n - 1 ? n - 1 : i + 1];
    final (lat, lon) = centre[i];
    final k = math.cos(lat * math.pi / 180);
    var dlon = b.$2 - a.$2;
    dlon -= 360 * (dlon / 360).round();
    // 行进方向（东、北，km），法向取向左（北侧）
    final e = dlon * k * kmPerDeg, nn = (b.$1 - a.$1) * kmPerDeg;
    final len = math.sqrt(e * e + nn * nn);
    if (len == 0) continue;
    final (ux, uy) = (-nn / len, e / len);
    final h = widthKm[i] / 2;
    final dLat = uy * h / kmPerDeg;
    final dLon = ux * h / (kmPerDeg * math.max(k, 0.05));
    left.add((lat + dLat, lon + dLon));
    right.add((lat - dLat, lon - dLon));
  }
  return [...left, ...right.reversed];
}
